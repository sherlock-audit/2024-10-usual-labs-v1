// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {ITokenMapping} from "src/interfaces/tokenManager/ITokenMapping.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";
import {
    CONTRACT_TOKEN_MAPPING,
    DEFAULT_ADMIN_ROLE,
    USD0_MINT,
    USD0_BURN,
    CONTRACT_ORACLE,
    CONTRACT_TREASURY,
    PAUSING_CONTRACTS_ROLE,
    BLACKLIST_ROLE
} from "src/constants.sol";
import {
    AmountIsZero, NullAddress, Blacklisted, SameValue, AmountExceedBacking
} from "src/errors.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ERC20PausableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

/// @title   Usd0 contract
/// @notice  Manages the USD0 token, including minting, burning, and transfers with blacklist checks.
/// @dev     Implements IUsd0 for USD0-specific logic.
/// @author  Usual Tech team
contract Usd0 is ERC20PausableUpgradeable, ERC20PermitUpgradeable, IUsd0 {
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
        ITokenMapping tokenMapping;
    }

    // keccak256(abi.encode(uint256(keccak256("Usd0.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant Usd0StorageV0Location =
        0x1d0cf51e4a8c83492710be318ea33bb77810af742c934c6b56e7b0fecb07db00;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
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

    function initializeV2() public reinitializer(3) {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.tokenMapping =
            ITokenMapping(IRegistryContract($.registryContract).getContract(CONTRACT_TOKEN_MAPPING));
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
    /// @dev Can only be called by an account with the DEFAULT_ADMIN_ROLE.
    function unpause() external {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /// @inheritdoc IUsd0
    /// @dev Can only be called by an account with the USD0_MINT role.
    function mint(address to, uint256 amount) public {
        if (amount == 0) {
            revert AmountIsZero();
        }

        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(USD0_MINT);
        IOracle oracle = IOracle($.registryContract.getContract(CONTRACT_ORACLE));
        address treasury = $.registryContract.getContract(CONTRACT_TREASURY);

        address[] memory rwas = $.tokenMapping.getAllUsd0Rwa();
        uint256 wadRwaBackingInUSD = 0;
        for (uint256 i = 0; i < rwas.length;) {
            address rwa = rwas[i];
            uint256 rwaPriceInUSD = uint256(oracle.getPrice(rwa));
            uint8 decimals = IERC20Metadata(rwa).decimals();

            wadRwaBackingInUSD +=
                Math.mulDiv(rwaPriceInUSD, IERC20(rwa).balanceOf(treasury), 10 ** decimals);

            unchecked {
                ++i;
            }
        }
        if (totalSupply() + amount > wadRwaBackingInUSD) {
            revert AmountExceedBacking();
        }
        _mint(to, amount);
    }

    /// @inheritdoc IUsd0
    /// @dev Can only be called by an account with the USD0_BURN role.
    function burnFrom(address account, uint256 amount) public {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(USD0_BURN);
        _burn(account, amount);
    }

    /// @inheritdoc IUsd0
    /// @dev Can only be called by an account with the USD0_BURN role.
    function burn(uint256 amount) public {
        Usd0StorageV0 storage $ = _usd0StorageV0();

        $.registryAccess.onlyMatchingRole(USD0_BURN);
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
        Usd0StorageV0 storage $ = _usd0StorageV0();
        if ($.isBlacklisted[from] || $.isBlacklisted[to]) {
            revert Blacklisted();
        }
        super._update(from, to, amount);
    }

    /// @notice Adds an address to the blacklist.
    /// @dev Can only be called by an account with the BLACKLIST_ROLE.
    /// @param account The address to be blacklisted.
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

    /// @notice Removes an address from the blacklist.
    /// @dev Can only be called by an account with the BLACKLIST_ROLE.
    /// @param account The address to be removed from the blacklist.
    function unBlacklist(address account) external {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryAccess.onlyMatchingRole(BLACKLIST_ROLE);
        if (!$.isBlacklisted[account]) {
            revert SameValue();
        }
        $.isBlacklisted[account] = false;

        emit UnBlacklist(account);
    }

    /// @inheritdoc IUsd0
    function isBlacklisted(address account) external view returns (bool) {
        Usd0StorageV0 storage $ = _usd0StorageV0();
        return $.isBlacklisted[account];
    }
}
