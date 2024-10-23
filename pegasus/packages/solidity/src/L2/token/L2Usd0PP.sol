// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IL2Usd0PP} from "src/interfaces/token/IL2Usd0PP.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {IERC677Receiver} from "src/interfaces/token/IERC677Receiver.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IERC677} from "src/interfaces/token/IERC677.sol";

import {
    CONTRACT_REGISTRY_ACCESS,
    PAUSING_CONTRACTS_ROLE,
    USD0PP_MINT,
    DEFAULT_ADMIN_ROLE,
    USD0PP_BURN,
    CONTRACT_USD0
} from "src/constants.sol";

import {AmountIsZero, InvalidName, InvalidSymbol, NullContract, Blacklisted} from "src/errors.sol";

/// @title   L2Usd0PP Contract
/// @notice  Manages USD0PP tokens on Layer 2, providing functionality for minting, burning, and transferring tokens.
/// @dev     Inherits from ERC20PausableUpgradeable and ERC20PermitUpgradeable to provide pausable and permit functionalities.
/// @dev     This contract is upgradeable, allowing for future improvements and enhancements.
/// @author  Usual Tech team

contract L2Usd0PP is IL2Usd0PP, ERC20PausableUpgradeable, ERC20PermitUpgradeable, IERC677 {
    using CheckAccessControl for IRegistryAccess;

    struct Usd0PPStorageV0 {
        /// The address of the registry contract.
        IRegistryContract registryContract;
        /// The address of the registry access contract.
        IRegistryAccess registryAccess;
        /// The USD0 token.
        IUsd0 usd0;
    }

    // keccak256(abi.encode(uint256(keccak256("Usd0PP.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant Usd0PPStorageV0Location =
        0x1519c21cc5b6e62f5c0018a7d32a0d00805e5b91f6eaa9f7bc303641242e3000;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _usd0ppStorageV0() private pure returns (Usd0PPStorageV0 storage $) {
        bytes32 position = Usd0PPStorageV0Location;
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

    /// @notice Initializes the contract with token parameters and related registry information.
    /// @param registryContract The address of the registry contract.
    /// @param name_ The name of the token.
    /// @param symbol_ The symbol of the token.
    // solhint-disable code-complexity
    function initialize(address registryContract, string memory name_, string memory symbol_)
        public
        initializer
    {
        _createUsd0PPCheck(name_, symbol_, registryContract);
        // Initialize the contract in an unpaused state.
        __Pausable_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
        __ERC20Permit_init_unchained(name_);
        __EIP712_init_unchained(name_, "1");
        // Initialize storage
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        $.registryContract = IRegistryContract(registryContract);
        $.usd0 = IUsd0(IRegistryContract(registryContract).getContract(CONTRACT_USD0));
        $.registryAccess = IRegistryAccess(
            IRegistryContract(registryContract).getContract(CONTRACT_REGISTRY_ACCESS)
        );
    }

    /// @notice Checks the parameters for creating the token.
    /// @param name The name of the token (cannot be empty)
    /// @param symbol The symbol of the token (cannot be empty)
    /// @param registryContract The address of the registry contract.
    function _createUsd0PPCheck(string memory name, string memory symbol, address registryContract)
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

    /// @notice Pauses all token transfers.
    /// @dev Can only be called by an account with the PAUSING_CONTRACTS_ROLE.
    function pause() public {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    /// @notice Unpauses all token transfers.
    /// @dev Can only be called by an account with the DEFAULT_ADMIN_ROLE.
    function unpause() external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /// @notice Mints new USD0PP tokens.
    /// @dev Can only be called by an account with the USD0PP_MINT role.
    /// @param to The address to mint the tokens to.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) public {
        if (amount == 0) {
            revert AmountIsZero();
        }

        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(USD0PP_MINT);
        _mint(to, amount);
    }

    /// @notice Burns USD0PP tokens from an account.
    /// @dev Can only be called by an account with the USD0PP_BURN role.
    /// @param account The account to burn the tokens from.
    /// @param amount The amount of tokens to burn.
    function burnFrom(address account, uint256 amount) public {
        if (amount == 0) {
            revert AmountIsZero();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(USD0PP_BURN);
        _burn(account, amount);
    }

    /// @notice Burns USD0PP tokens from the caller's account.
    /// @dev Can only be called by an account with the USD0PP_BURN role.
    /// @param amount The amount of tokens to burn.
    function burn(uint256 amount) public {
        if (amount == 0) {
            revert AmountIsZero();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(USD0PP_BURN);
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

    function _update(address sender, address recipient, uint256 amount)
        internal
        override(ERC20PausableUpgradeable, ERC20Upgradeable)
    {
        if (amount == 0) {
            revert AmountIsZero();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        IUsd0 usd0 = IUsd0(address($.usd0));
        if (usd0.isBlacklisted(sender) || usd0.isBlacklisted(recipient)) {
            revert Blacklisted();
        }
        super._update(sender, recipient, amount);
    }
}
