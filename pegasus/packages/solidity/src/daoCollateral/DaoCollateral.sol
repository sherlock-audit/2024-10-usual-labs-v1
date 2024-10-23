// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {EIP712Upgradeable} from
    "openzeppelin-contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {NoncesUpgradeable} from "src/utils/NoncesUpgradeable.sol";

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {ITokenMapping} from "src/interfaces/tokenManager/ITokenMapping.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";
import {IDaoCollateral, Approval, Intent} from "src/interfaces/IDaoCollateral.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {Normalize} from "src/utils/normalize.sol";
import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";
import {
    SCALAR_ONE,
    DEFAULT_ADMIN_ROLE,
    MAX_REDEEM_FEE,
    SCALAR_TEN_KWEI,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_TOKEN_MAPPING,
    CONTRACT_ORACLE,
    CONTRACT_TREASURY,
    CONTRACT_USD0,
    CONTRACT_SWAPPER_ENGINE,
    INTENT_TYPE_HASH,
    INTENT_MATCHING_ROLE,
    NONCE_THRESHOLD_SETTER_ROLE,
    PAUSING_CONTRACTS_ROLE
} from "src/constants.sol";

import {
    NullContract,
    InvalidToken,
    AmountIsZero,
    AmountTooLow,
    AmountTooBig,
    ApprovalFailed,
    RedeemMustNotBePaused,
    RedeemMustBePaused,
    SwapMustNotBePaused,
    SwapMustBePaused,
    SameValue,
    CBRIsTooHigh,
    CBRIsNull,
    RedeemFeeTooBig,
    InvalidSigner,
    InvalidDeadline,
    ExpiredSignature,
    NoOrdersIdsProvided,
    InvalidOrderAmount
} from "src/errors.sol";

/// @title   DaoCollateral Contract
/// @notice  Manages the swapping of collateral tokens for stablecoins, with functionalities for swap (direct mint) and redeeming tokens
/// @dev     Provides mechanisms for token swap operations, fee management, called Dao Collateral for historical reasons
/// @author  Usual Tech team
contract DaoCollateral is
    IDaoCollateral,
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    NoncesUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20 for IERC20Metadata;
    using CheckAccessControl for IRegistryAccess;
    using Normalize for uint256;

    struct DaoCollateralStorageV0 {
        /// @notice Indicates if the redeem functionality is paused.
        bool _redeemPaused;
        /// @notice Indicates if the swap functionality is paused.
        bool _swapPaused;
        /// @notice Indicates if the Counter Bank Run (CBR) functionality is active.
        bool isCBROn;
        /// @notice The fee for redeeming tokens, in basis points.
        uint256 redeemFee;
        /// @notice The coefficient for calculating the returned rwaToken amount when CBR is active.
        uint256 cbrCoef;
        /// @notice The RegistryAccess contract instance for role checks.
        IRegistryAccess registryAccess;
        /// @notice The RegistryContract instance for contract interactions.
        IRegistryContract registryContract;
        /// @notice The TokenMapping contract instance for managing token mappings.
        ITokenMapping tokenMapping;
        /// @notice The USD0 token contract instance.
        IUsd0 usd0;
        /// @notice The Oracle contract instance for price feeds.
        IOracle oracle;
        /// @notice The address of treasury holding RWA tokens.
        address treasury;
        /// @notice The SwapperEngine contract instance for managing token swaps.
        ISwapperEngine swapperEngine;
        /// @notice the threshold for intents to be considered used in USD0 _getPriceAndDecimals
        uint256 nonceThreshold;
        /// @notice The mapping of the amount of the order taken that matches up to current nonce for each account
        mapping(address account => uint256) _orderAmountTaken;
    }

    // keccak256(abi.encode(uint256(keccak256("daoCollateral.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant DaoCollateralStorageV0Location =
        0xb6b5806749b83e5a37ff64f3aa7a7ce3ac6e8a80a998e853c1d3efe545237c00;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when tokens are swapped.
    event Swap(
        address indexed owner, address indexed tokenSwapped, uint256 amount, uint256 amountInUSD
    );

    /// @notice Emitted when tokens are redeemed.
    event Redeem(
        address indexed redeemer,
        address indexed rwaToken,
        uint256 amountRedeemed,
        uint256 returnedRwaAmount,
        uint256 stableFeeAmount
    );

    /// @notice Emitted when an intent is matched.
    event IntentMatched(
        address indexed owner,
        uint256 indexed nonce,
        address indexed tokenSwapped,
        uint256 amountInTokenDecimals,
        uint256 amountInUSD
    );

    /// @notice Emitted when an intent and associated nonce is consumed.
    event IntentConsumed(
        address indexed owner,
        uint256 indexed nonce,
        address indexed tokenSwapped,
        uint256 totalAmountInTokenDecimals
    );

    /// @notice Emitted when a nonce is invalidated.
    event NonceInvalidated(address indexed signer, uint256 indexed nonceInvalidated);

    /// @notice Emitted when redeem functionality is paused.
    event RedeemPaused();

    /// @notice Emitted when redeem functionality is unpaused.
    event RedeemUnPaused();

    /// @notice Emitted when swap functionality is paused.
    event SwapPaused();

    /// @notice Emitted when swap functionality is unpaused.
    event SwapUnPaused();

    /// @notice Emitted when the Counter Bank Run (CBR) mechanism is activated.
    /// @param cbrCoef The Counter Bank Run (CBR) coefficient.
    event CBRActivated(uint256 cbrCoef);

    /// @notice Emitted when the Counter Bank Run (CBR) mechanism is deactivated.
    event CBRDeactivated();

    /// @notice Emitted when the redeem fee is updated.
    /// @param redeemFee The new redeem fee.
    event RedeemFeeUpdated(uint256 redeemFee);

    /// @notice Emitted when the nonce threshold is set.
    event NonceThresholdSet(uint256 newThreshold);

    /*//////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensures the function is called only when the redeem is not paused.
    modifier whenRedeemNotPaused() {
        _requireRedeemNotPaused();
        _;
    }

    /// @notice Ensures the function is called only when the redeem is paused.
    modifier whenRedeemPaused() {
        _requireRedeemPaused();
        _;
    }

    /// @notice Ensures the function is called only when the swap is not paused.
    modifier whenSwapNotPaused() {
        _requireSwapNotPaused();
        _;
    }

    /// @notice Ensures the function is called only when the swap is paused.
    modifier whenSwapPaused() {
        _requireSwapPaused();
        _;
    }

    /// @notice  _requireRedeemNotPaused method will check if the redeem is not paused
    /// @dev Throws if the contract is paused.
    function _requireRedeemNotPaused() internal view virtual {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        if ($._redeemPaused) {
            revert RedeemMustNotBePaused();
        }
    }

    /// @notice  _requireRedeemPaused method will check if the redeem is paused
    /// @dev Throws if the contract is not paused.
    function _requireRedeemPaused() internal view virtual {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        if (!$._redeemPaused) {
            revert RedeemMustBePaused();
        }
    }

    /// @notice  _requireSwapNotPaused method will check if the redeem is not paused
    /// @dev Throws if the contract is paused.

    function _requireSwapNotPaused() internal view virtual {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        if ($._swapPaused) {
            revert SwapMustNotBePaused();
        }
    }

    /// @notice  _requireSwapPaused method will check if the redeem is paused
    /// @dev Throws if the contract is not paused.
    function _requireSwapPaused() internal view virtual {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        if (!$._swapPaused) {
            revert SwapMustBePaused();
        }
    }

    /// @notice Ensures the caller is authorized as part of the Usual Tech team.
    function _requireOnlyAdmin() internal view {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
    }

    /// @notice Ensures the caller is authorized as a pauser
    function _requireOnlyPauser() internal view {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
    }

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Returns the storage struct of the contract.
    /// @return $ The pointer to the storage struct of the contract.
    function _daoCollateralStorageV0() internal pure returns (DaoCollateralStorageV0 storage $) {
        bytes32 position = DaoCollateralStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /// @notice Initializes the DaoCollateral contract with registry information and initial configuration.
    /// @param _registryContract The address of the registry contract.
    /// @param _redeemFee The initial redeem fee, in basis points.
    function initialize(address _registryContract, uint256 _redeemFee) public initializer {
        // can't have a redeem fee greater than 25%
        if (_redeemFee > MAX_REDEEM_FEE) {
            revert RedeemFeeTooBig();
        }

        if (_registryContract == address(0)) {
            revert NullContract();
        }

        __EIP712_init_unchained("DaoCollateral", "1");
        __Nonces_init_unchained();
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.redeemFee = _redeemFee;

        IRegistryContract registryContract = IRegistryContract(_registryContract);
        $.registryAccess = IRegistryAccess(registryContract.getContract(CONTRACT_REGISTRY_ACCESS));

        $.treasury = address(registryContract.getContract(CONTRACT_TREASURY));
        $.tokenMapping = ITokenMapping(registryContract.getContract(CONTRACT_TOKEN_MAPPING));
        $.usd0 = IUsd0(registryContract.getContract(CONTRACT_USD0));

        $.oracle = IOracle(registryContract.getContract(CONTRACT_ORACLE));

        $.swapperEngine = ISwapperEngine(registryContract.getContract(CONTRACT_SWAPPER_ENGINE));
    }

    /// @notice Initializes the DaoCollateral contract with registry information and update configuration.
    /// @param _registryContract The address of the registry contract.
    /* cspell:disable-next-line */
    function initializeV1(address _registryContract) public reinitializer(2) {
        if (_registryContract == address(0)) {
            revert NullContract();
        }

        __EIP712_init_unchained("DaoCollateral", "1");
        __Nonces_init_unchained();

        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.registryContract = IRegistryContract(_registryContract);
        $.swapperEngine = ISwapperEngine(
            IRegistryContract(_registryContract).getContract(CONTRACT_SWAPPER_ENGINE)
        );
    }

    /*//////////////////////////////////////////////////////////////
                               Setters
    //////////////////////////////////////////////////////////////*/

    /// @notice Activates the Counter Bank Run (CBR) mechanism.
    /// @dev Enables the CBR
    /// @param coefficient the CBR coefficient to activate
    function activateCBR(uint256 coefficient) external {
        // we should revert if the coef is greater than 1
        if (coefficient > SCALAR_ONE) {
            revert CBRIsTooHigh();
        } else if (coefficient == 0) {
            revert CBRIsNull();
        }
        _requireOnlyAdmin();
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.isCBROn = true;
        $._swapPaused = true;
        $.cbrCoef = coefficient;
        emit CBRActivated($.cbrCoef);
        emit SwapPaused();
    }

    /// @notice Deactivates the Counter Bank Run (CBR) mechanism.
    /// @dev Disables the CBR functionality.
    function deactivateCBR() external {
        _requireOnlyAdmin();
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        if ($.isCBROn == false) revert SameValue();
        $.isCBROn = false;
        emit CBRDeactivated();
    }

    /// @notice Sets the redeem fee.
    /// @dev Updates the fee for redeeming tokens, in basis points.
    /// @param _redeemFee The new redeem fee to set.
    function setRedeemFee(uint256 _redeemFee) external {
        if (_redeemFee > MAX_REDEEM_FEE) revert RedeemFeeTooBig();
        _requireOnlyAdmin();
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        if ($.redeemFee == _redeemFee) revert SameValue();
        $.redeemFee = _redeemFee;
        emit RedeemFeeUpdated(_redeemFee);
    }

    /// @notice Pauses the redeem functionality.
    /// @dev Triggers the stopped state, preventing redeem operations.
    function pauseRedeem() external whenRedeemNotPaused {
        _requireOnlyPauser();
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $._redeemPaused = true;
        emit RedeemPaused();
    }

    /// @notice Unpauses the redeem functionality.
    /// @dev Returns to normal state, allowing redeem operations.
    function unpauseRedeem() external whenRedeemPaused {
        _requireOnlyAdmin();
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $._redeemPaused = false;
        emit RedeemUnPaused();
    }

    /// @notice Pauses the swap functionality.
    /// @dev Triggers the stopped state, preventing swap operations.
    function pauseSwap() external whenSwapNotPaused {
        _requireOnlyPauser();
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $._swapPaused = true;
        emit SwapPaused();
    }

    /// @notice Unpauses the swap functionality.
    /// @dev Returns to normal state, allowing swap operations.
    function unpauseSwap() external whenSwapPaused {
        _requireOnlyAdmin();
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $._swapPaused = false;
        emit SwapUnPaused();
    }

    /// @notice Pauses the contract.
    /// @dev Can be called by the DAO to pause all contract operations.
    function pause() external {
        _requireOnlyPauser();
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev Can be called by the DAO to unpause all contract operations.
    function unpause() external {
        _requireOnlyAdmin();
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    /// @notice  _swapCheckAndGetUSDQuote method will check if the token is a USD0-supported RWA token and if the amount is not 0
    /// @dev     Function that do sanity check on the inputs
    /// @dev      and return the normalized USD quoted price of RWA tokens for the given amount
    /// @param   rwaToken  address of the token to swap MUST be a rwa token.
    /// @param   amountInToken  amount of RWA token to swap.
    /// @return  wadQuoteInUSD The quoted amount in USD with 18 decimals for the specified token and amount.
    function _swapCheckAndGetUSDQuote(address rwaToken, uint256 amountInToken)
        internal
        view
        returns (uint256 wadQuoteInUSD)
    {
        if (amountInToken == 0) {
            revert AmountIsZero();
        }

        // Amount can't be greater than uint128
        if (amountInToken > type(uint128).max) {
            revert AmountTooBig();
        }

        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        if (!$.tokenMapping.isUsd0Collateral(rwaToken)) {
            revert InvalidToken();
        }
        wadQuoteInUSD = _getQuoteInUsd(amountInToken, rwaToken);
        //slither-disable-next-line incorrect-equality
        if (wadQuoteInUSD == 0) {
            revert AmountTooLow();
        }
    }

    /// @notice  transfers RWA Token And Mint Stable
    /// @dev     will transfer the RWA to the treasury and mints the corresponding stableAmount in USD0 stablecoin
    /// @param   rwaToken  address of the token to swap MUST be a RWA token.
    /// @param   amount  amount of rwa token to swap.
    /// @param   wadAmountInUSD amount of USD0 stablecoin to mint.
    function _transferRWATokenAndMintStable(
        address rwaToken,
        uint256 amount,
        uint256 wadAmountInUSD
    ) internal {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        // Should revert if balance is insufficient
        IERC20Metadata(address(rwaToken)).safeTransferFrom(msg.sender, $.treasury, amount);
        // Mint some stablecoin
        $.usd0.mint(msg.sender, wadAmountInUSD);
    }

    /// @dev call the oracle to get the price in USD
    /// @param rwaToken the collateral token address
    /// @return wadPriceInUSD the price in USD with 18 decimals
    /// @return decimals number of decimals of the token
    function _getPriceAndDecimals(address rwaToken)
        internal
        view
        returns (uint256 wadPriceInUSD, uint8 decimals)
    {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        wadPriceInUSD = uint256($.oracle.getPrice(rwaToken));
        decimals = uint8(IERC20Metadata(rwaToken).decimals());
    }

    /// @notice  get the price in USD of an `tokenAmount` of `rwaToken`
    /// @dev call the oracle to get the price in USD of `tokenAmount` of token with 18 decimals
    /// @param tokenAmount the amount of token to convert in USD with 18 decimals
    /// @param rwaToken the collateral token address
    /// @return wadAmountInUSD the amount in USD with 18 decimals
    function _getQuoteInUsd(uint256 tokenAmount, address rwaToken)
        internal
        view
        returns (uint256 wadAmountInUSD)
    {
        (uint256 wadPriceInUSD, uint8 decimals) = _getPriceAndDecimals(rwaToken);
        uint256 wadAmount = tokenAmount.tokenAmountToWad(decimals);
        wadAmountInUSD = Math.mulDiv(wadAmount, wadPriceInUSD, SCALAR_ONE, Math.Rounding.Floor);
    }

    /// @notice  get the amount of token for an amount of USD
    /// @dev call the oracle to get the price in USD of `amount` of token with 18 decimals
    /// @param wadStableAmount the amount of USD with 18 decimals
    /// @param rwaToken the RWA token address
    /// @return amountInToken the amount in token corresponding to the amount of USD
    function _getQuoteInToken(uint256 wadStableAmount, address rwaToken)
        internal
        view
        returns (uint256 amountInToken)
    {
        (uint256 wadPriceInUSD, uint8 decimals) = _getPriceAndDecimals(rwaToken);
        // will result in an amount with the same 'decimals' as the token
        amountInToken = wadStableAmount.wadTokenAmountForPrice(wadPriceInUSD, decimals);
    }

    /// @notice Calculates the returned amount of rwaToken give an amount of USD
    /// @dev return the amountInToken of token for `wadStableAmount` of USD at the current price
    /// @param wadStableAmount the amount of USD
    /// @param rwaToken the RWA token address
    /// @return amountInToken the amount of token that is worth `wadStableAmount` of USD with 18 decimals
    function _getTokenAmountForAmountInUSD(uint256 wadStableAmount, address rwaToken)
        internal
        view
        returns (uint256 amountInToken)
    {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        amountInToken = _getQuoteInToken(wadStableAmount, rwaToken);
        // if cbr is on we need to apply the coef to the rwa price
        // cbrCoef should be less than 1e18
        if ($.isCBROn) {
            amountInToken = Math.mulDiv(amountInToken, $.cbrCoef, SCALAR_ONE, Math.Rounding.Floor);
        }
    }

    /// @notice  _transferFee method will transfer the fee to the treasury
    /// @dev     Function that transfer the fee to the treasury
    /// @dev     The fee is calculated as a percentage of the amount of USD0 stablecoin to redeem
    /// @dev     The fee is minted to avoid transfer and allowance as the whole USD0 amount is burnt afterwards
    /// @param   usd0Amount  Amount of USD0 to transfer to treasury.
    /// @param   rwaToken  address of the token to swap should be a rwa token.
    /// @return stableFee The amount of stablecoin minted as fees for the treasury.
    function _transferFee(uint256 usd0Amount, address rwaToken)
        internal
        returns (uint256 stableFee)
    {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        stableFee = Math.mulDiv(usd0Amount, $.redeemFee, SCALAR_TEN_KWEI, Math.Rounding.Floor);
        uint8 tokenDecimals = IERC20Metadata(rwaToken).decimals();
        // if the token has less decimals than USD0 we need to normalize the fee
        if (tokenDecimals < 18) {
            // we scale down the fee to the token decimals
            // and we scale it up to 18 decimals
            stableFee = Normalize.tokenAmountToWad(
                Normalize.wadAmountToDecimals(stableFee, tokenDecimals), tokenDecimals
            );
        }
        // transfer the fee to the treasury
        if (stableFee > 0) {
            $.usd0.mint($.treasury, stableFee);
        }
    }

    /// @notice  _burnStableTokenAndTransferCollateral method will burn the stable token and transfer the collateral token
    /// @dev     Function that burns the stable token and transfer the collateral token
    /// @param   rwaToken  address of the token to swap should be a rwa token.
    /// @param   stableAmount  amount of token to swap.
    /// @param   stableFee  amount of fee in stablecoin.
    /// @return returnedCollateral The amount of collateral token returned.
    function _burnStableTokenAndTransferCollateral(
        address rwaToken,
        uint256 stableAmount,
        uint256 stableFee
    ) internal returns (uint256 returnedCollateral) {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        // we burn the remaining stable token
        uint256 burnedStable = stableAmount - stableFee;
        // we burn all the stable token USD0
        $.usd0.burnFrom(msg.sender, stableAmount);

        // get the amount of collateral token for the amount of stablecoin burned by calling the oracle
        returnedCollateral = _getTokenAmountForAmountInUSD(burnedStable, rwaToken);
        if (returnedCollateral == 0) {
            revert AmountTooLow();
        }

        // we distribute the collateral token from the treasury to the user
        // slither-disable-next-line arbitrary-send-erc20
        IERC20Metadata(rwaToken).safeTransferFrom($.treasury, msg.sender, returnedCollateral);
    }

    /// @notice Swap RWA for USDC through offers on the SwapperContract
    /// @dev Takes RWA, mints USD0 and provides it to the Swapper Contract directly
    /// Sends USD0 to the offer's creator and sends USDC to the recipient
    /// @dev the recipient Address to receive the USDC is msg.sender
    /// @param caller Address of the caller (msg.sender or intent recipient)
    /// @param rwaToken Address of the RWA to swap for USDC
    /// @param amountInTokenDecimals Amount of the RWA to swap for USDC
    /// @param partialMatching flag to allow partial matching
    /// @param orderIdsToTake orderIds to be taken
    /// @param approval ERC20Permit approval data and signature of data
    /// @return matchedAmountInTokenDecimals The amount of RWA tokens which have been matched.
    /// @return matchedAmountInUSD           The net amount of USD0 tokens minted.
    // solhint-disable-next-line code-complexity
    function _swapRWAtoStbc(
        address caller,
        address rwaToken,
        uint256 amountInTokenDecimals,
        bool partialMatching,
        uint256[] calldata orderIdsToTake,
        Approval calldata approval
    ) internal returns (uint256 matchedAmountInTokenDecimals, uint256 matchedAmountInUSD) {
        if (amountInTokenDecimals == 0) {
            revert AmountIsZero();
        }
        if (amountInTokenDecimals > type(uint128).max) {
            revert AmountTooBig();
        }
        if (orderIdsToTake.length == 0) {
            revert NoOrdersIdsProvided();
        }
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        if (!$.tokenMapping.isUsd0Collateral(rwaToken)) {
            revert InvalidToken();
        }

        // Check if the approval isn't null, if it isn't, use it for the permit
        if (approval.deadline != 0 && approval.v != 0 && approval.r != 0 && approval.s != 0) {
            // Authorization transfer
            try IERC20Permit(rwaToken).permit( //NOTE: this will fail if permit already used but that's ok as long as there is enough allowance
                caller,
                address(this),
                type(uint256).max,
                approval.deadline,
                approval.v,
                approval.r,
                approval.s
            ) {} catch {} // solhint-disable-line no-empty-blocks
        }

        // Take the RWA token from the recipient
        IERC20Metadata(rwaToken).safeTransferFrom(caller, address(this), amountInTokenDecimals);
        // Get the price quote of the RWA token to mint USD0
        uint256 wadRwaQuoteInUSD = _getQuoteInUsd(amountInTokenDecimals, rwaToken);
        // Mint the corresponding amount of USD0 stablecoin
        $.usd0.mint(address(this), wadRwaQuoteInUSD);
        if (!IERC20($.usd0).approve(address($.swapperEngine), wadRwaQuoteInUSD)) {
            revert ApprovalFailed();
        }
        // Provide the USD0 to the SwapperEngine and receive USDC for the caller
        uint256 wadRwaNotTakenInUSD =
            $.swapperEngine.swapUsd0(caller, wadRwaQuoteInUSD, orderIdsToTake, partialMatching);

        // Burn any unmatched USD0 and return the RWA
        if (wadRwaNotTakenInUSD > 0) {
            if (!IERC20($.usd0).approve(address($.swapperEngine), 0)) {
                revert ApprovalFailed();
            }
            $.usd0.burnFrom(address(this), wadRwaNotTakenInUSD);

            // Get amount of RWA for the wadRwaNotTakenInUSD pricing
            uint256 rwaTokensToReturn = _getQuoteInToken(wadRwaNotTakenInUSD, rwaToken);

            // Transfer back the remaining RWA tokens to the recipient
            IERC20Metadata(rwaToken).safeTransfer(caller, rwaTokensToReturn);

            matchedAmountInTokenDecimals = amountInTokenDecimals - rwaTokensToReturn;
        } else {
            matchedAmountInTokenDecimals = amountInTokenDecimals;
        }

        // Send the matched RWA to the treasury
        IERC20Metadata(rwaToken).safeTransfer($.treasury, matchedAmountInTokenDecimals);

        matchedAmountInUSD = wadRwaQuoteInUSD - wadRwaNotTakenInUSD;
        emit Swap(caller, rwaToken, matchedAmountInTokenDecimals, matchedAmountInUSD);

        return (matchedAmountInTokenDecimals, matchedAmountInUSD);
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDaoCollateral
    function swap(address rwaToken, uint256 amount, uint256 minAmountOut)
        public
        nonReentrant
        whenSwapNotPaused
        whenNotPaused
    {
        uint256 wadQuoteInUSD = _swapCheckAndGetUSDQuote(rwaToken, amount);
        // Check if the amount is greater than the minAmountOut
        if (wadQuoteInUSD < minAmountOut) {
            revert AmountTooLow();
        }
        _transferRWATokenAndMintStable(rwaToken, amount, wadQuoteInUSD);
        // Emit the event
        emit Swap(msg.sender, rwaToken, amount, wadQuoteInUSD);
    }

    /// @inheritdoc IDaoCollateral
    function swapWithPermit(
        address rwaToken,
        uint256 amount,
        uint256 minAmountOut,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // solhint-disable-next-line no-empty-blocks
        try IERC20Permit(rwaToken).permit(msg.sender, address(this), amount, deadline, v, r, s) {}
            catch {} // solhint-disable-line no-empty-blocks
        swap(rwaToken, amount, minAmountOut);
    }

    /// @inheritdoc IDaoCollateral
    function redeem(address rwaToken, uint256 amount, uint256 minAmountOut)
        external
        nonReentrant
        whenRedeemNotPaused
        whenNotPaused
    {
        // Amount can't be 0
        if (amount == 0) {
            revert AmountIsZero();
        }

        // check that rwaToken is a RWA token
        if (!_daoCollateralStorageV0().tokenMapping.isUsd0Collateral(rwaToken)) {
            revert InvalidToken();
        }
        uint256 stableFee = _transferFee(amount, rwaToken);
        uint256 returnedCollateral =
            _burnStableTokenAndTransferCollateral(rwaToken, amount, stableFee);
        // Check if the amount is greater than the minAmountOut
        if (returnedCollateral < minAmountOut) {
            revert AmountTooLow();
        }
        emit Redeem(msg.sender, rwaToken, amount, returnedCollateral, stableFee);
    }

    /// @inheritdoc IDaoCollateral
    function redeemDao(address rwaToken, uint256 amount) external nonReentrant {
        // Amount can't be 0
        if (amount == 0) {
            revert AmountIsZero();
        }

        _requireOnlyAdmin();
        // check that rwaToken is a RWA token
        if (!_daoCollateralStorageV0().tokenMapping.isUsd0Collateral(rwaToken)) {
            revert InvalidToken();
        }
        uint256 returnedCollateral = _burnStableTokenAndTransferCollateral(rwaToken, amount, 0);
        emit Redeem(msg.sender, rwaToken, amount, returnedCollateral, 0);
    }

    /// @inheritdoc IDaoCollateral
    function swapRWAtoStbc(
        address rwaToken,
        uint256 amountInTokenDecimals,
        bool partialMatching,
        uint256[] calldata orderIdsToTake,
        Approval calldata approval
    ) external nonReentrant whenNotPaused whenSwapNotPaused {
        _swapRWAtoStbc(
            msg.sender, rwaToken, amountInTokenDecimals, partialMatching, orderIdsToTake, approval
        );
    }

    /// @inheritdoc IDaoCollateral
    function invalidateNonce() external {
        uint256 nonceUsed = _useNonce(msg.sender);
        _daoCollateralStorageV0()._orderAmountTaken[msg.sender] = 0;
        emit NonceInvalidated(msg.sender, nonceUsed);
    }

    /// @inheritdoc IDaoCollateral
    function invalidateUpToNonce(uint256 newNonce) external {
        _invalidateUpToNonce(msg.sender, newNonce);
        _daoCollateralStorageV0()._orderAmountTaken[msg.sender] = 0;
        emit NonceInvalidated(msg.sender, newNonce - 1);
    }

    /// @inheritdoc IDaoCollateral
    function setNonceThreshold(uint256 threshold) external {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.registryAccess.onlyMatchingRole(NONCE_THRESHOLD_SETTER_ROLE);
        $.nonceThreshold = threshold;
        emit NonceThresholdSet(threshold);
    }

    /// @inheritdoc IDaoCollateral
    function nonceThreshold() external view returns (uint256) {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        return $.nonceThreshold;
    }

    /// @notice Checks if an Intent is valid by verifying its signature and returns the remaining amount unmatched
    /// @dev Function should be called internally before any fields from intent are used in contract logic
    /// @param intent Intent data and signature of data
    /// @return remainingAmountUnmatched Amount left in the current intent for swap
    /// @return nonce The current nonce for this reusable intent
    function _isValidIntent(Intent calldata intent)
        internal
        virtual
        returns (uint256 remainingAmountUnmatched, uint256 nonce)
    {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        //if we increment the nonce this wont match so the user can cancel the order essentially
        uint256 currentOrderNonce = nonces(intent.recipient);
        // check the signature w/ nonce
        bytes32 structHash = keccak256(
            abi.encode(
                INTENT_TYPE_HASH,
                intent.recipient,
                intent.rwaToken,
                intent.amountInTokenDecimals,
                currentOrderNonce,
                intent.deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        if (!SignatureChecker.isValidSignatureNow(intent.recipient, hash, intent.signature)) {
            revert InvalidSigner(intent.recipient);
        }

        if ($._orderAmountTaken[intent.recipient] > intent.amountInTokenDecimals) {
            revert InvalidOrderAmount(intent.recipient, intent.amountInTokenDecimals);
        }

        // return the amount left to be filled
        remainingAmountUnmatched =
            (intent.amountInTokenDecimals - $._orderAmountTaken[intent.recipient]);
        return (remainingAmountUnmatched, currentOrderNonce);
    }

    /// @notice Partially or fully consumes an amount of an intent
    /// @dev Function should be called internally after verifying the intent is valid
    /// @param amount The amount to consume from the remaining reusable intent
    /// @param intent Intent data and signature of data
    /// @return remainingAmountUnmatched Amount left in the current intent for swap
    function _useIntentAmount(uint256 amount, Intent memory intent)
        internal
        virtual
        returns (uint256 remainingAmountUnmatched)
    {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        // check that the amount they want to use is less than the remaining amount unmatched in the smart order
        remainingAmountUnmatched =
            (intent.amountInTokenDecimals - $._orderAmountTaken[intent.recipient]);

        if (amount > remainingAmountUnmatched) {
            revert InvalidOrderAmount(intent.recipient, amount);
        } else if ((remainingAmountUnmatched - amount) <= $.nonceThreshold) {
            emit IntentConsumed(
                intent.recipient,
                nonces(intent.recipient),
                intent.rwaToken,
                intent.amountInTokenDecimals
            );
            _useNonce(intent.recipient);
            //reset the intent amount taken for the next nonce
            $._orderAmountTaken[intent.recipient] = 0;
            return 0;
        } else {
            $._orderAmountTaken[intent.recipient] += amount;
        }

        remainingAmountUnmatched =
            intent.amountInTokenDecimals - $._orderAmountTaken[intent.recipient];
        return remainingAmountUnmatched;
    }

    function orderAmountTakenCurrentNonce(address owner) public view virtual returns (uint256) {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        return $._orderAmountTaken[owner];
    }

    /// @inheritdoc IDaoCollateral
    function swapRWAtoStbcIntent(
        uint256[] calldata orderIdsToTake,
        Approval calldata approval,
        Intent calldata intent,
        bool partialMatching
    ) external nonReentrant whenNotPaused whenSwapNotPaused {
        if (block.timestamp > intent.deadline) {
            revert ExpiredSignature(intent.deadline);
        }
        if (approval.deadline != intent.deadline) {
            revert InvalidDeadline(approval.deadline, intent.deadline);
        }

        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        $.registryAccess.onlyMatchingRole(INTENT_MATCHING_ROLE);

        (uint256 remainingAmountUnmatched, uint256 nonce) = _isValidIntent(intent);
        //NOTE: if its a full match then we increment the nonce
        if (!partialMatching) {
            emit IntentConsumed(
                intent.recipient, nonce, intent.rwaToken, intent.amountInTokenDecimals
            );
            _useNonce(intent.recipient);
            $._orderAmountTaken[intent.recipient] = 0;
        }

        (uint256 matchedAmountInTokenDecimals, uint256 matchedAmountInUSD) = _swapRWAtoStbc(
            intent.recipient,
            intent.rwaToken,
            remainingAmountUnmatched,
            partialMatching,
            orderIdsToTake,
            approval
        );
        //NOTE: if it is a partial match then we deduct the matched amount from the remaining unmatched, if the intent is used up then increment the nonce
        if (partialMatching) {
            _useIntentAmount(matchedAmountInTokenDecimals, intent);
        }

        emit IntentMatched(
            intent.recipient,
            nonce,
            intent.rwaToken,
            matchedAmountInTokenDecimals,
            matchedAmountInUSD
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IDaoCollateral

    function isCBROn() external view returns (bool) {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        return $.isCBROn;
    }

    /// @notice Returns the cbrCoef value.
    function cbrCoef() public view returns (uint256) {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        return $.cbrCoef;
    }

    /// @inheritdoc IDaoCollateral
    function redeemFee() public view returns (uint256) {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        return $.redeemFee;
    }

    /// @inheritdoc IDaoCollateral
    function isRedeemPaused() public view returns (bool) {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        return $._redeemPaused;
    }

    /// @inheritdoc IDaoCollateral
    function isSwapPaused() public view returns (bool) {
        DaoCollateralStorageV0 storage $ = _daoCollateralStorageV0();
        return $._swapPaused;
    }
}
