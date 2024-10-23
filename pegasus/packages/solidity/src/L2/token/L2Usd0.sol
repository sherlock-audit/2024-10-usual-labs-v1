// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IL2Usd0} from "src/interfaces/token/IL2Usd0.sol";
import {IERC677} from "src/interfaces/token/IERC677.sol";
import {IERC677Receiver} from "src/interfaces/token/IERC677Receiver.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {
    PAUSING_CONTRACTS_ROLE,
    DEFAULT_ADMIN_ROLE,
    USD0_MINT,
    USD0_BURN,
    BLACKLIST_ROLE,
    CONTRACT_REGISTRY_ACCESS
} from "src/constants.sol";
import {
    AmountIsZero,
    NullAddress,
    Blacklisted,
    SameValue,
    InvalidSymbol,
    InvalidName,
    NullContract
} from "src/errors.sol";
import {ERC20PausableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

/// @title   L2Usd0 contract
/// @notice  Manages the USD0 token on Layer 2, including minting, burning, and transfers with blacklist checks.
/// @dev     Implements IL2Usd0 for USD0-specific logic on Layer 2.
/// @author  Usual Tech team
contract L2Usd0 is ERC20PausableUpgradeable, ERC20PermitUpgradeable, IL2Usd0, IERC677 {
    using CheckAccessControl for IRegistryAccess;
    using SafeERC20 for ERC20;

    /// @notice Event emitted when an address is blacklisted.
    /// @param account The address that was blacklisted.
    event Blacklist(address account);

    /// @notice Event emitted when an address is removed from blacklist.
    /// @param account The address that was removed from blacklist.
    event UnBlacklist(address account);

    /// @custom:storage-location erc7201:Usd0.storage.v0
    struct Usd0StorageV0 {
        IRegistryAccess registryAccess;
        mapping(address => bool) isBlacklisted;
        IRegistryContract registryContract;
    }

    // keccak256(abi.encode(uint256(keccak256("Usd0.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant Usd0StorageV0Location =
        0x1d0cf51e4a8c83492710be318ea33bb77810af742c934c6b56e7b0fecb07db00;

    /// @notice Returns the storage struct of the contract.
    /// @return $ The storage struct.
    function _usd0StorageV0() internal pure returns (Usd0StorageV0 storage $) {
        bytes32 position = Usd0StorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }
    /// @custom:oz-upgrades-unsafe-allow constructor

    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice  Initializes the contract with a registry contract, name, and symbol.
    /// @param   registryContract_ Address of the registry contract for role management.
    /// @param   name_ The name of the USD0 token.
    /// @param   symbol_ The symbol of the USD0 token.
    function initialize(address registryContract_, string memory name_, string memory symbol_)
        public
        initializer
    {
        _createUsd0Check(name_, symbol_, registryContract_);
        // Initialize the contract with token details.
        __ERC20_init_unchained(name_, symbol_);
        // Initialize the contract in an unpaused state.
        __Pausable_init_unchained();
        // Initialize the contract with permit functionality.
        __ERC20Permit_init_unchained(name_);
        __EIP712_init_unchained(name_, "1");
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryContract = IRegistryContract(registryContract_);
        $.registryAccess = IRegistryAccess(
            IRegistryContract(registryContract_).getContract(CONTRACT_REGISTRY_ACCESS)
        );
    }

    /// @notice Checks the parameters for creating the token.
    /// @param name The name of the token (cannot be empty)
    /// @param symbol The symbol of the token (cannot be empty)
    /// @param registryContract The address of the registry contract.
    function _createUsd0Check(string memory name, string memory symbol, address registryContract)
        internal
        pure
    {
        // Initialize the contract with the registry contract.
        if (registryContract == address(0)) {
            revert NullContract();
        }
        // Check if the name is not empty
        if (bytes(name).length == 0) {
            revert InvalidName();
        }
        // Check if the symbol is not empty
        if (bytes(symbol).length == 0) {
            revert InvalidSymbol();
        }
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses all token transfers.
    /// @dev Can only be called by an account with the PAUSING_CONTRACTS_ROLE.
    function pause() external {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    /// @notice Unpauses all token transfers.
    /// @dev Can only be called by the admin.
    function unpause() external {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /// @notice Mints new USD0 tokens.
    /// @dev Can only be called by an account with the USD0_MINT role.
    /// @param to The address to mint the tokens to.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) public {
        if (amount == 0) {
            revert AmountIsZero();
        }

        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(USD0_MINT);
        _mint(to, amount);
    }

    /// @notice Burns USD0 tokens from an account.
    /// @dev Can only be called by an account with the USD0_BURN role.
    /// @param account The address of the account to burn the tokens from.
    /// @param amount The amount of tokens to burn.
    function burnFrom(address account, uint256 amount) public {
        if (amount == 0) {
            revert AmountIsZero();
        }
        Usd0StorageV0 storage $ = _usd0StorageV0();
        //  Ensures the caller has the USD0_BURN role.
        $.registryAccess.onlyMatchingRole(USD0_BURN);
        _burn(account, amount);
    }

    /// @notice Burns USD0 tokens from the caller's account.
    /// @dev Can only be called by an account with the USD0_BURN role.
    /// @param amount The amount of tokens to burn.
    function burn(uint256 amount) public {
        if (amount == 0) {
            revert AmountIsZero();
        }
        Usd0StorageV0 storage $ = _usd0StorageV0();

        //  Ensures the caller has the USD0_BURN role.
        $.registryAccess.onlyMatchingRole(USD0_BURN);
        _burn(msg.sender, amount);
    }

    /// @inheritdoc IERC677
    function transferAndCall(address to, uint256 amount, bytes memory data)
        public
        returns (bool success)
    {
        super.transfer(to, amount);
        emit Transfer(msg.sender, to, amount, data);
        //@notice .isContract from OZ4 was deprecated, which is why we replaced it with code.length;
        if (address(to).code.length != 0) {
            IERC677Receiver(to).onTokenTransfer(msg.sender, amount, data);
        }
        return true;
    }

    /// @notice Hook that ensures token transfers are not made from or to blacklisted addresses.
    /// @dev This function overrides the _update function from ERC20PausableUpgradeable and ERC20Upgradeable.
    /// @param from The address sending the tokens.
    /// @param to The address receiving the tokens.
    /// @param amount The amount of tokens being transferred.
    function _update(address from, address to, uint256 amount)
        internal
        virtual
        override(ERC20PausableUpgradeable, ERC20Upgradeable)
    {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        if ($.isBlacklisted[from] || $.isBlacklisted[to]) {
            revert Blacklisted();
        }
        super._update(from, to, amount);
    }

    /// @notice  Adds an address to the blacklist.
    /// @dev     Can only be called by an account with the BLACKLIST_ROLE.
    /// @param   account  The address to be blacklisted.
    function blacklist(address account) external {
        if (account == address(0)) {
            revert NullAddress();
        }
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if ($.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = true;

        emit Blacklist(account);
    }

    /// @notice  Removes an address from the blacklist.
    /// @dev     Can only be called by an account with the BLACKLIST_ROLE.
    /// @param   account  The address to be removed from the blacklist.
    function unBlacklist(address account) external {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if (!$.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = false;

        emit UnBlacklist(account);
    }

    /// @notice  Checks if an address is blacklisted.
    /// @param   account  The address to check.
    /// @return  bool True if the account is blacklisted, false otherwise.
    function isBlacklisted(address account) external view returns (bool) {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        return $.isBlacklisted[account];
    }
}
