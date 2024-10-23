// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import {IUsualS} from "src/interfaces/token/IUsualS.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USUALSP,
    DEFAULT_ADMIN_ROLE,
    USUALS_BURN,
    BLACKLIST_ROLE,
    USUALSP,
    USUALS_TOTAL_SUPPLY,
    PAUSING_CONTRACTS_ROLE
} from "src/constants.sol";
import {
    NullContract,
    NullAddress,
    Blacklisted,
    SameValue,
    InvalidName,
    InvalidSymbol,
    NotAuthorized
} from "src/errors.sol";

/// @title   UsualS contract
/// @notice  Manages the USUALS token, including initial minting, burning, and transfers with blacklist checks.
/// @dev     Implements IUsualS for USUALS-specific logic.
/// @author  Usual Tech team
contract UsualS is ERC20PausableUpgradeable, ERC20PermitUpgradeable, IUsualS {
    using CheckAccessControl for IRegistryAccess;

    /// @custom:storage-location erc7201:UsualS.storage.v0
    struct UsualSStorageV0 {
        // The registry access contract.
        IRegistryAccess registryAccess;
        // The registry contract.
        IRegistryContract registryContract;
        // A mapping of blacklisted addresses.
        mapping(address => bool) isBlacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("UsualS.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant UsualSStorageV0Location =
        0xec0992155067fea9cd5767187f0dab81717debff03e73f74c0b70baa10bf5700;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _usualSStorageV0() internal pure returns (UsualSStorageV0 storage $) {
        bytes32 position = UsualSStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an account is blacklisted.
    /// @param account The address that was blacklisted.
    event Blacklist(address account);

    /// @notice Emitted when an account is removed from the blacklist.
    /// @param account The address that was unblacklisted.
    event UnBlacklist(address account);

    /// @notice Emitted when the stake is made.
    /// @param account The address of the insider.
    /// @param amount The amount of tokens staked.
    event Stake(address account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice  Initializes the contract with a registry contract, name, and symbol.
    /// @param   registryContract_ Address of the registry contract for role management.
    /// @param   name_ The name of the USUALS token.
    /// @param   symbol_ The symbol of the USUALS token.
    function initialize(
        IRegistryContract registryContract_,
        string memory name_,
        string memory symbol_
    ) public initializer {
        _createUsualSCheck(name_, symbol_, address(registryContract_));
        // Initialize the contract with token details.
        __ERC20_init_unchained(name_, symbol_);
        // Initialize the contract in an unpaused state.
        __Pausable_init_unchained();
        // Initialize the contract with permit functionality.
        __ERC20Permit_init_unchained(name_);
        // Initialize the contract with EIP712 functionality.
        __EIP712_init_unchained(name_, "1");
        // Initialize the contract with the registry contract.
        UsualSStorageV0 storage $ = _usualSStorageV0();
        $.registryContract = registryContract_;
        $.registryAccess = IRegistryAccess(registryContract_.getContract(CONTRACT_REGISTRY_ACCESS));

        // Mint the total supply of USUALS at the initialization.
        _mint(address(this), USUALS_TOTAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses all token transfers.
    /// @dev Can only be called by the pauser.
    function pause() external {
        UsualSStorageV0 storage $ = _usualSStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    /// @notice Unpauses all token transfers.
    /// @dev Can only be called by the admin.
    function unpause() external {
        UsualSStorageV0 storage $ = _usualSStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /// @inheritdoc IUsualS
    function burnFrom(address account, uint256 amount) external {
        UsualSStorageV0 storage $ = _usualSStorageV0();
        //  Ensures the caller has the USUALS_BURN role.
        $.registryAccess.onlyMatchingRole(USUALS_BURN);
        _burn(account, amount);
    }

    /// @inheritdoc IUsualS
    function burn(uint256 amount) external {
        UsualSStorageV0 storage $ = _usualSStorageV0();

        //  Ensures the caller has the USUALS_BURN role.
        $.registryAccess.onlyMatchingRole(USUALS_BURN);
        _burn(msg.sender, amount);
    }

    /// @notice  Adds an address to the blacklist.
    /// @dev     Can only be called by the BLACKLIST_ROLE.
    /// @param   account  The address to be blacklisted.
    function blacklist(address account) external {
        if (account == address(0)) {
            revert NullAddress();
        }
        UsualSStorageV0 storage $ = _usualSStorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if ($.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = true;

        emit Blacklist(account);
    }

    /// @notice  Removes an address from the blacklist.
    /// @dev     Can only be called by the BLACKLIST_ROLE.
    /// @param   account  The address to be removed from the blacklist.
    function unBlacklist(address account) external {
        UsualSStorageV0 storage $ = _usualSStorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if (!$.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = false;

        emit UnBlacklist(account);
    }

    /// @notice Sends the total supply of USUALS to the staking contract.
    /// @dev     Can only be called by the staking contract role.
    function stakeAll() external {
        UsualSStorageV0 storage $ = _usualSStorageV0();
        address usualSP = $.registryContract.getContract(CONTRACT_USUALSP);
        if (msg.sender != usualSP) {
            revert NotAuthorized();
        }
        uint256 balanceOfThis = balanceOf(address(this));
        _transfer(address(this), usualSP, balanceOfThis);
        emit Stake(usualSP, balanceOfThis);
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks the parameters for creating UsualS.
    /// @param name The name of the UsualS token (cannot be empty)
    /// @param symbol The symbol of the UsualS token (cannot be empty)
    function _createUsualSCheck(string memory name, string memory symbol, address registryContract)
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

    /// @notice Hook that ensures token transfers are not made from or to not blacklisted addresses.
    /// @param from The address sending the tokens.
    /// @param to The address receiving the tokens.
    /// @param amount The amount of tokens being transferred.
    function _update(address from, address to, uint256 amount)
        internal
        virtual
        override(ERC20PausableUpgradeable, ERC20Upgradeable)
    {
        UsualSStorageV0 storage $ = _usualSStorageV0();
        if ($.isBlacklisted[from] || $.isBlacklisted[to]) {
            revert Blacklisted();
        }
        super._update(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                               Getters
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUsualS
    function isBlacklisted(address account) external view returns (bool) {
        UsualSStorageV0 storage $ = _usualSStorageV0();
        return $.isBlacklisted[account];
    }
}
