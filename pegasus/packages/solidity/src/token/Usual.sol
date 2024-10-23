// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IUsual} from "src/interfaces/token/IUsual.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {
    CONTRACT_REGISTRY_ACCESS,
    DEFAULT_ADMIN_ROLE,
    USUAL_MINT,
    USUAL_BURN,
    BLACKLIST_ROLE,
    PAUSING_CONTRACTS_ROLE
} from "src/constants.sol";
import {AmountIsZero, NullContract, NullAddress, Blacklisted, SameValue} from "src/errors.sol";
import {ERC20PausableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

/// @title   Usual contract
/// @notice  Manages the USUAL token, including minting, burning, and transfers with blacklist checks.
/// @dev     Implements IUsual for USUAL-specific logic.
/// @author  Usual Tech team
contract Usual is ERC20PausableUpgradeable, ERC20PermitUpgradeable, IUsual {
    using CheckAccessControl for IRegistryAccess;
    using SafeERC20 for ERC20;

    /// @notice Emitted when an account is blacklisted
    /// @param account The address that was blacklisted
    event Blacklist(address account);

    /// @notice Emitted when an account is removed from the blacklist
    /// @param account The address that was unblacklisted
    event UnBlacklist(address account);

    /// @custom:storage-location erc7201:Usual.storage.v0
    struct UsualStorageV0 {
        IRegistryAccess registryAccess;
        mapping(address => bool) isBlacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("Usual.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant UsualStorageV0Location =
        0xef28303bc727ce4292bbfc822cd1bd55856334a6c8fea26a82814184b0a91900;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _usualStorageV0() internal pure returns (UsualStorageV0 storage $) {
        bytes32 position = UsualStorageV0Location;
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
    /// @param   name_ The name of the USUAL token.
    /// @param   symbol_ The symbol of the USUAL token.
    function initialize(address registryContract_, string memory name_, string memory symbol_)
        public
        initializer
    {
        // Initialize the contract with token details.
        __ERC20_init_unchained(name_, symbol_);
        // Initialize the contract in an unpaused state.
        __Pausable_init_unchained();
        // Initialize the contract with permit functionality.
        __ERC20Permit_init_unchained(name_);
        // Initialize the contract with EIP712 functionality.
        __EIP712_init_unchained(name_, "1");
        // Initialize the contract with the registry contract.
        if (registryContract_ == address(0)) {
            revert NullContract();
        }
        _usualStorageV0().registryAccess = IRegistryAccess(
            IRegistryContract(registryContract_).getContract(CONTRACT_REGISTRY_ACCESS)
        );
    }
    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses all token transfers
    /// @dev Can only be called by an account with the PAUSING_CONTRACTS_ROLE
    function pause() external {
        UsualStorageV0 storage $ = _usualStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    /// @notice Unpauses all token transfers
    /// @dev Can only be called by an account with the DEFAULT_ADMIN_ROLE
    function unpause() external {
        UsualStorageV0 storage $ = _usualStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /// @inheritdoc IUsual
    function mint(address to, uint256 amount) public {
        if (amount == 0) {
            revert AmountIsZero();
        }

        UsualStorageV0 storage $ = _usualStorageV0();
        $.registryAccess.onlyMatchingRole(USUAL_MINT);
        _mint(to, amount);
    }

    /// @inheritdoc IUsual
    function burnFrom(address account, uint256 amount) public {
        UsualStorageV0 storage $ = _usualStorageV0();
        //  Ensures the caller has the USUAL_BURN role.
        $.registryAccess.onlyMatchingRole(USUAL_BURN);
        _burn(account, amount);
    }

    /// @inheritdoc IUsual
    function burn(uint256 amount) public {
        UsualStorageV0 storage $ = _usualStorageV0();

        $.registryAccess.onlyMatchingRole(USUAL_BURN);
        _burn(msg.sender, amount);
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
        UsualStorageV0 storage $ = _usualStorageV0();
        if ($.isBlacklisted[from] || $.isBlacklisted[to]) {
            revert Blacklisted();
        }
        super._update(from, to, amount);
    }

    /// @notice Adds an address to the blacklist
    /// @dev Can only be called by an account with the BLACKLIST_ROLE
    /// @param account The address to be blacklisted
    function blacklist(address account) external {
        if (account == address(0)) {
            revert NullAddress();
        }
        UsualStorageV0 storage $ = _usualStorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if ($.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = true;

        emit Blacklist(account);
    }

    /// @notice Removes an address from the blacklist
    /// @dev Can only be called by an account with the BLACKLIST_ROLE
    /// @param account The address to be removed from the blacklist
    function unBlacklist(address account) external {
        UsualStorageV0 storage $ = _usualStorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if (!$.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = false;

        emit UnBlacklist(account);
    }

    /// @inheritdoc IUsual
    function isBlacklisted(address account) external view returns (bool) {
        UsualStorageV0 storage $ = _usualStorageV0();
        return $.isBlacklisted[account];
    }
}
