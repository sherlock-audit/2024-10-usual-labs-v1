// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/ERC20Permit.sol";
import {
    DEFAULT_ADMIN_ROLE, CONTRACT_REGISTRY_ACCESS, PAUSING_CONTRACTS_ROLE
} from "src/constants.sol";

import {NullContract, NullAddress, NotAuthorized, SameValue} from "src/errors.sol";

import {NotWhitelisted} from "src/mock/errors.sol";

/// @title   ERC20Whitelist Contract
/// @notice  Provides an abstract contract for managing a whitelist for ERC20 tokens, allowing only whitelisted addresses to transfer tokens.
/// @dev     Inherits from ERC20, ERC20Permit, and Pausable to provide ERC20 functionality with permit and pausing capabilities.
/// @author  Usual Tech team
abstract contract ERC20Whitelist is ERC20Permit, Pausable {
    // solhint-disable-next-line
    IRegistryContract internal immutable _REGISTRY_CONTRACT;
    // solhint-disable-next-line
    IRegistryAccess internal immutable _REGISTRY_ACCESS;

    event Blacklist(address indexed user);
    event Whitelist(address indexed user);

    /// @custom:storage-location erc7201:ecr20whitelist.storage.v0
    struct ERC20WhitelistStorageV0 {
        mapping(address => bool) _isWhitelisted;
    }

    // keccak256(abi.encode(uint256(keccak256("ecr20whitelist.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant ERC20WhitelistStorageV0Location =
        0xbc5a1848ecc7b9a17808d4fff4ed6d37ea2a51bbb1252e72ed68a7e16e321e00;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    // solhint-disable-next-line
    function _erc20WhitelistStorageV0() internal pure returns (ERC20WhitelistStorageV0 storage $) {
        bytes32 position = ERC20WhitelistStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /// @notice Ensures the caller is authorized as part of the Usual Tech team.
    modifier onlyAdmin() {
        if (!_REGISTRY_ACCESS.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyPauser() {
        if (!_REGISTRY_ACCESS.hasRole(PAUSING_CONTRACTS_ROLE, msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    /// @notice Initializes the contract with registry information and token details.
    /// @param registryContract_ The address of the registry contract.
    /// @param name The name of the token.
    /// @param symbol The symbol of the token.
    constructor(address registryContract_, string memory name, string memory symbol)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        if (registryContract_ == address(0)) {
            revert NullContract();
        }
        _REGISTRY_CONTRACT = IRegistryContract(registryContract_);
        _REGISTRY_ACCESS = IRegistryAccess(_REGISTRY_CONTRACT.getContract(CONTRACT_REGISTRY_ACCESS));
    }

    /// @notice Whitelists an address, allowing it to transfer tokens.
    /// @param to The address to whitelist.
    function whitelist(address to) public virtual onlyAdmin {
        ERC20WhitelistStorageV0 storage $ = _erc20WhitelistStorageV0();
        if (to == address(0)) {
            revert NullAddress();
        }
        if ($._isWhitelisted[to]) revert SameValue();
        $._isWhitelisted[to] = true;
        emit Whitelist(to);
    }

    /// @notice Removes an address from the whitelist, preventing further transfers.
    /// @param to The address to remove from the whitelist.
    function removeFromWhitelist(address to) public virtual onlyAdmin {
        ERC20WhitelistStorageV0 storage $ = _erc20WhitelistStorageV0();
        if (to == address(0)) {
            revert NullAddress();
        }
        if (!$._isWhitelisted[to]) revert SameValue();
        $._isWhitelisted[to] = false;
        emit Blacklist(to);
    }

    /// @notice Checks if an address is whitelisted.
    /// @param user The address to check.
    /// @return bool True if the address is whitelisted.
    function isWhitelisted(address user) public view virtual returns (bool) {
        ERC20WhitelistStorageV0 storage $ = _erc20WhitelistStorageV0();
        return $._isWhitelisted[user];
    }

    /// @notice Pauses all token transfers.
    /// @dev Can only be called by the pauser.
    function pause() external onlyPauser {
        _pause();
    }

    /// @notice Unpauses all token transfers.
    /// @dev Can only be called by an admin.
    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @notice Hook that ensures token transfers are between whitelisted addresses.
    /// @param from The address sending the tokens.
    /// @param to The address receiving the tokens.
    /// @param amount The amount of tokens being transferred.
    function _update(address from, address to, uint256 amount) internal virtual override {
        if (
            (!isWhitelisted(from) && from != address(0)) || (!isWhitelisted(to) && to != address(0))
        ) {
            revert NotWhitelisted();
        }
        super._update(from, to, amount);
    }
}
