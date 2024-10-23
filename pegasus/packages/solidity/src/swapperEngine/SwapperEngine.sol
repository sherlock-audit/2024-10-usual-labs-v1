// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";
import {IUsd0} from "./../interfaces/token/IUsd0.sol";

import {IOracle} from "src/interfaces/oracles/IOracle.sol";

import {Normalize} from "src/utils/normalize.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {
    ONE_USDC,
    CONTRACT_REGISTRY_ACCESS,
    DEFAULT_ADMIN_ROLE,
    CONTRACT_ORACLE,
    CONTRACT_USD0,
    CONTRACT_USDC,
    MINIMUM_USDC_PROVIDED,
    PAUSING_CONTRACTS_ROLE
} from "src/constants.sol";

import {
    NullContract,
    InsufficientUSD0Balance,
    OrderNotActive,
    NoOrdersIdsProvided,
    NotRequester,
    AmountTooLow,
    AmountIsZero,
    NotAuthorized
} from "src/errors.sol";

/// @title SwapperEngine
/// @notice A contract for swapping USDC tokens for USD0 tokens using order matching.
/// @dev This contract allows users to deposit USDC tokens, create orders, and match those orders
///      against USD0 tokens provided by other users.
///      Order matching works by allowing users to create individual orders specifying the amount
///      of USDC tokens they wish to swap. Other users can then provide USD0 tokens to match against
///      these orders, directly swapping their USD0 tokens for the USDC tokens in the orders.
///      Tradeoffs:
///      + Direct swaps: Users can directly swap their tokens with each other, without the need for
///        intermediary liquidity pools.
///      + Low Slippage: The price of the swap is determined by the usdc oracle price at that block height irrespective of liquidity depth.
///      - Liquidity: Order matching relies on the presence of active orders to facilitate swaps.
///        If there are no matching orders available, users may need to wait for new orders to be created.
///      - Match to Market: The price of the swaps is determined by the individual orders when they are executed not when they are placed (offset by low price volatility of stables)
/// @custom:mechanism Effectively this facilitates RWA --> USD0 --> USDC --> $$$ --> RWA ... limited only by USDC orderbook depth
/// @author  Usual Tech team
contract SwapperEngine is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ISwapperEngine
{
    using SafeERC20 for IERC20;
    using Normalize for uint256;
    using CheckAccessControl for IRegistryAccess;

    struct UsdcOrder {
        address requester;
        uint256 tokenAmount;
        bool active;
    }

    struct SwapperEngineStorageV0 {
        IRegistryAccess registryAccess;
        IRegistryContract registryContract;
        IOracle oracle;
        IERC20 usdcToken;
        IERC20 usd0;
        mapping(uint256 => UsdcOrder) orders;
        uint256 nextOrderId;
        uint256 minimumUSDCAmountProvided;
    }

    event Deposit(address indexed requester, uint256 indexed orderId, uint256 amount);
    event Withdraw(address indexed requester, uint256 indexed orderId, uint256 amount);
    event OrderMatched(
        address indexed usdcProviderAddr,
        address indexed usd0Provider,
        uint256 indexed orderId,
        uint256 amount
    );

    // keccak256(abi.encode(uint256(keccak256("swapperengine.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant SwapperEngineStorageV0Location =
        0x6c3529a15b63e79e1691946ad3dcd9eb824ac76513a1aed382fd5661938dea00;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _swapperEngineStorageV0() internal pure returns (SwapperEngineStorageV0 storage $) {
        bytes32 position = SwapperEngineStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Constructor for initializing the contract.
    /// @dev This constructor is used to set the initial state of the contract.
    /// @param registryContract The registry contract address.
    function initialize(address registryContract) public initializer {
        if (registryContract == address(0)) {
            revert NullContract();
        }
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        $.registryContract = IRegistryContract(registryContract);
        $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        $.usdcToken = IERC20($.registryContract.getContract(CONTRACT_USDC));
        $.usd0 = IERC20($.registryContract.getContract(CONTRACT_USD0));
        $.nextOrderId = 1;
        $.oracle = IOracle($.registryContract.getContract(CONTRACT_ORACLE));
        $.minimumUSDCAmountProvided = MINIMUM_USDC_PROVIDED;
    }

    /// @notice Ensures the caller is authorized as part of the Usual Tech team.
    function _requireOnlyAdmin() internal view {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
    }

    function _requireOnlyPauser() internal view {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
    }

    /// @notice Returns the minimum USDC amount required for providing liquidity.
    /// @dev This function retrieves the minimum USDC amount from the storage variable.
    /// @return minimumUSDCAmount The minimum USDC amount required for providing liquidity.
    function minimumUSDCAmountProvided() public view returns (uint256 minimumUSDCAmount) {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        minimumUSDCAmount = $.minimumUSDCAmountProvided;
    }

    ///@notice Retrieves the current price of USDC in WAD format (18 decimals).
    ///@dev This function fetches the price of USDC from the oracle contract and returns it in WAD format.
    ///@return usdcWadPrice The current price of USDC in WAD format.
    function _getUsdcWadPrice() private view returns (uint256 usdcWadPrice) {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        usdcWadPrice = uint256($.oracle.getPrice(address($.usdcToken)));
    }

    ///@notice Retrieves the details of a specific USDC order.
    ///@dev This function returns the active status and token amount of the specified order.
    ///@param orderId The unique identifier of the order.
    ///@return active A boolean indicating whether the order is active or not.
    ///@return tokenAmount The amount of USDC tokens associated with the order.
    function getOrder(uint256 orderId) public view returns (bool active, uint256 tokenAmount) {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        UsdcOrder memory order = $.orders[orderId];
        active = order.active;
        tokenAmount = order.tokenAmount;
    }

    ///@notice Calculates the USD0 equivalent amount in WAD format for a given USDC token amount.
    ///@dev This function converts the USDC token amount from its native decimal representation to WAD format (18 decimals),
    ///     and then calculates the equivalent USD0 amount based on the provided USDC price in WAD format.
    ///@param usdcTokenAmountInNativeDecimals The amount of USDC tokens in their native decimal representation (6 decimals).
    ///@param usdcWadPrice The price of USDC in WAD format.
    ///@return usd0WadEquivalent The equivalent amount of USD0 in WAD format.
    function _getUsd0WadEquivalent(uint256 usdcTokenAmountInNativeDecimals, uint256 usdcWadPrice)
        private
        view
        returns (uint256 usd0WadEquivalent)
    {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        uint8 decimals = IERC20Metadata(address($.usdcToken)).decimals();
        uint256 usdcWad = usdcTokenAmountInNativeDecimals.tokenAmountToWad(decimals);
        usd0WadEquivalent = usdcWad.wadAmountByPrice(usdcWadPrice);
    }

    /// @notice Calculates the USDC token amount in native decimals for a given USD0 amount in WAD format.
    /// @dev This function calculates the expected USDC amount to receive based on the provided usd0WadAmount and USDC price in WAD format.
    /// @param usd0WadAmount The amount of USD0 in WAD format.
    /// @param usdcWadPrice The price of USDC in WAD format.
    /// @return usdcTokenAmountInNativeDecimals The equivalent amount of USDC tokens in their native decimal representation.
    function _getUsdcAmountFromUsd0WadEquivalent(uint256 usd0WadAmount, uint256 usdcWadPrice)
        private
        view
        returns (uint256 usdcTokenAmountInNativeDecimals)
    {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        uint8 decimals = IERC20Metadata(address($.usdcToken)).decimals();
        usdcTokenAmountInNativeDecimals =
            usd0WadAmount.wadTokenAmountForPrice(usdcWadPrice, decimals);
    }

    // @title Update Minimum USDC Amount Provided
    /// @notice Updates the minimum amount of USDC that must be provided in a deposit.
    /// @dev This function can only be called by an administrator.
    /// @param minimumUSDCAmount The new minimum amount of USDC to deposit
    ///        The new minimumUSDCAmount must be greater than 1 USDC (1e6)
    function updateMinimumUSDCAmountProvided(uint256 minimumUSDCAmount) external {
        if (minimumUSDCAmount < ONE_USDC) {
            // Minimum amount must be at least 1 USDC
            revert AmountTooLow();
        }
        _requireOnlyAdmin();
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        $.minimumUSDCAmountProvided = minimumUSDCAmount;
    }

    /// @notice Pauses the contract.
    /// @dev This function can only be called by a pauser.
    function pause() external {
        _requireOnlyPauser();
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev This function can only be called by an administrator.
    function unpause() external {
        _requireOnlyAdmin();
        _unpause();
    }

    function _depositUSDC(SwapperEngineStorageV0 storage $, uint256 amountToDeposit) internal {
        if (amountToDeposit < $.minimumUSDCAmountProvided) {
            // amountToDeposit must be equal or greater than MINIMUM_USDC_PROVIDED
            revert AmountTooLow();
        }
        if (IUsd0(address($.usd0)).isBlacklisted(msg.sender)) {
            revert NotAuthorized();
        }

        uint256 orderId = $.nextOrderId++;
        $.orders[orderId] =
            UsdcOrder({requester: msg.sender, tokenAmount: amountToDeposit, active: true});

        // Transfer USDC tokens to this contract
        $.usdcToken.safeTransferFrom(msg.sender, address(this), amountToDeposit);

        emit Deposit(msg.sender, orderId, amountToDeposit);
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISwapperEngine
    function depositUSDC(uint256 amountToDeposit) external nonReentrant whenNotPaused {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        _depositUSDC($, amountToDeposit);
    }

    /// @inheritdoc ISwapperEngine
    function depositUSDCWithPermit(
        uint256 amountToDeposit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        try IERC20Permit(address($.usdcToken)).permit(
            msg.sender, address(this), amountToDeposit, deadline, v, r, s
        ) {} catch {} // solhint-disable-line no-empty-blocks
        _depositUSDC($, amountToDeposit);
    }

    /// @inheritdoc ISwapperEngine
    function withdrawUSDC(uint256 orderToCancel) external nonReentrant whenNotPaused {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        UsdcOrder storage order = $.orders[orderToCancel];

        if (!order.active) {
            // Order not active or does not exist
            revert OrderNotActive();
        }
        if (order.requester != msg.sender) {
            // Only the requester can cancel their order
            revert NotRequester();
        }

        uint256 amountToWithdraw = order.tokenAmount;
        order.active = false; // Deactivate the order
        order.tokenAmount = 0; // Set the amount to zero

        // Transfer USDC back to the requester
        $.usdcToken.safeTransfer(msg.sender, amountToWithdraw);

        emit Withdraw(msg.sender, orderToCancel, amountToWithdraw);
    }

    /// @notice Allows a user to provide USD0 tokens and receive USDC tokens by matching against existing orders.
    /// @dev This function allows users to specify an amount of USDC tokens they want, calculating the corresponding
    ///      USD0 tokens they need and exchanging it against active orders.
    /// @param recipient The address to receive the USDC tokens.
    /// @param amountUsdcToTakeInNativeDecimals The amount of USDC tokens to take, in the token's native decimal representation.
    /// @param orderIdsToTake An array of order IDs to match against.
    /// @param partialMatchingAllowed A flag indicating whether partial matching is allowed.
    /// @return unmatchedUsdcAmount The amount of USDC tokens that were not matched.
    /// @return totalUsd0Provided The total amount of USD0 tokens provided.
    function _provideUsd0ReceiveUSDC( // solhint-disable-line
        address recipient,
        uint256 amountUsdcToTakeInNativeDecimals,
        uint256[] memory orderIdsToTake,
        bool partialMatchingAllowed,
        uint256 usdcWadPrice
    ) internal returns (uint256 unmatchedUsdcAmount, uint256 totalUsd0Provided) {
        if (amountUsdcToTakeInNativeDecimals == 0) {
            // Amount must be greater than 0
            revert AmountIsZero();
        }
        if (orderIdsToTake.length == 0) {
            revert NoOrdersIdsProvided();
        }

        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();

        uint256 totalUsdcTaken = 0;

        for (
            uint256 i;
            i < orderIdsToTake.length && totalUsdcTaken < amountUsdcToTakeInNativeDecimals;
        ) {
            uint256 orderId = orderIdsToTake[i];
            UsdcOrder storage order = $.orders[orderId];

            if (order.active) {
                uint256 remainingAmountToTake = amountUsdcToTakeInNativeDecimals - totalUsdcTaken;
                // if the usdcOrder tokenAmount > remainingAmountToTake only take the remaining else take the whole order
                uint256 amountOfUsdcFromOrder = order.tokenAmount > remainingAmountToTake
                    ? remainingAmountToTake
                    : order.tokenAmount;

                // @NOTE oracle price check & calculation of nominal USDC TokenAmount to USD in 18 decimals.
                // USD0 has 18 decimals and we are considering it with a static USD value of 1.
                // USDC has 6 decimals, needs to be normalized to 18 decimals.

                order.tokenAmount -= amountOfUsdcFromOrder;
                totalUsdcTaken += amountOfUsdcFromOrder;

                if (order.tokenAmount == 0) {
                    order.active = false;
                }

                uint256 usd0Amount = _getUsd0WadEquivalent(amountOfUsdcFromOrder, usdcWadPrice);
                totalUsd0Provided += usd0Amount;
                // Transfer USD0 from sender to order requester
                $.usd0.safeTransferFrom(msg.sender, order.requester, usd0Amount);

                emit OrderMatched(order.requester, msg.sender, orderId, amountOfUsdcFromOrder);
            }

            unchecked {
                ++i;
            }
        }

        // Transfer USDC from this contract to the recipient
        $.usdcToken.safeTransfer(recipient, totalUsdcTaken);
        // Revert if partial matching is not allowed and we haven't taken all of the USD0
        if (
            !partialMatchingAllowed && totalUsdcTaken != amountUsdcToTakeInNativeDecimals
                || totalUsdcTaken == 0
        ) {
            revert AmountTooLow();
        }

        return ((amountUsdcToTakeInNativeDecimals - totalUsdcTaken), totalUsd0Provided);
    }

    /// @inheritdoc ISwapperEngine
    function provideUsd0ReceiveUSDC(
        address recipient,
        uint256 amountUsdcToTakeInNativeDecimals,
        uint256[] memory orderIdsToTake,
        bool partialMatchingAllowed
    ) external nonReentrant whenNotPaused returns (uint256) {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 requiredUsd0Amount =
            _getUsd0WadEquivalent(amountUsdcToTakeInNativeDecimals, usdcWadPrice);
        if ($.usd0.balanceOf(msg.sender) < requiredUsd0Amount) {
            revert InsufficientUSD0Balance();
        }
        (uint256 unmatchedUsdcAmount,) = _provideUsd0ReceiveUSDC(
            recipient,
            amountUsdcToTakeInNativeDecimals,
            orderIdsToTake,
            partialMatchingAllowed,
            usdcWadPrice
        );
        return unmatchedUsdcAmount;
    }

    /// @inheritdoc ISwapperEngine
    function provideUsd0ReceiveUSDCWithPermit(
        address recipient,
        uint256 amountUsdcToTakeInNativeDecimals,
        uint256[] memory orderIdsToTake,
        bool partialMatchingAllowed,
        uint256 usd0ToPermit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused returns (uint256) {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 requiredUsd0Amount =
            _getUsd0WadEquivalent(amountUsdcToTakeInNativeDecimals, usdcWadPrice);
        // Authorization transfer
        if ($.usd0.balanceOf(msg.sender) < requiredUsd0Amount || usd0ToPermit < requiredUsd0Amount)
        {
            revert InsufficientUSD0Balance();
        }
        try IERC20Permit(address($.usd0)).permit(
            msg.sender, address(this), usd0ToPermit, deadline, v, r, s
        ) {} catch {} // solhint-disable-line no-empty-blocks
        (uint256 unmatchedUsdcAmount,) = _provideUsd0ReceiveUSDC(
            recipient,
            amountUsdcToTakeInNativeDecimals,
            orderIdsToTake,
            partialMatchingAllowed,
            usdcWadPrice
        );
        return unmatchedUsdcAmount;
    }

    /// @inheritdoc ISwapperEngine
    function swapUsd0(
        address recipient,
        uint256 amountUsd0ToProvideInWad,
        uint256[] memory orderIdsToTake,
        bool partialMatchingAllowed
    ) external nonReentrant whenNotPaused returns (uint256) {
        uint256 usdcWadPrice = _getUsdcWadPrice();

        (, uint256 totalUsd0Provided) = _provideUsd0ReceiveUSDC(
            recipient,
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideInWad, usdcWadPrice),
            orderIdsToTake,
            partialMatchingAllowed,
            usdcWadPrice
        );

        return amountUsd0ToProvideInWad - totalUsd0Provided;
    }

    /// @inheritdoc ISwapperEngine
    function getNextOrderId() external view override returns (uint256) {
        SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
        return $.nextOrderId;
    }
}
