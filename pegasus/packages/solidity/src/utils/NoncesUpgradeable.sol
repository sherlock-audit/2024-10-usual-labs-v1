// SPDX-License-Identifier: MIT
// Copyright (c) 2023 zOS Global Limited
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Provides tracking nonces for addresses. Nonces will only increment.
 */
abstract contract NoncesUpgradeable is Initializable {
    /**
     * @dev The nonce used for an `account` is not the expected current nonce.
     */
    error InvalidAccountNonce(address account, uint256 currentNonce);

    /// @custom:storage-location erc7201:openzeppelin.storage.Nonces
    struct NoncesStorage {
        mapping(address account => uint256) _nonces;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Nonces")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 private constant NoncesStorageLocation =
        0x5ab42ced628888259c08ac98db1eb0cf702fc1501344311d8b100cd1bfe4bb00;

    function _getNoncesStorage() private pure returns (NoncesStorage storage $) {
        // solhint-disable-next-line
        assembly {
            $.slot := NoncesStorageLocation
        }
    }

    // solhint-disable-next-line
    function __Nonces_init() internal onlyInitializing {}
    // solhint-disable-next-line
    function __Nonces_init_unchained() internal onlyInitializing {}
    /**
     * @dev Returns the next unused nonce for an address.
     */

    function nonces(address owner) public view virtual returns (uint256) {
        NoncesStorage storage $ = _getNoncesStorage();
        return $._nonces[owner];
    }

    /**
     * @dev Consumes a nonce.
     *
     * Returns the current value and increments nonce.
     */
    function _useNonce(address owner) internal virtual returns (uint256) {
        NoncesStorage storage $ = _getNoncesStorage();
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here.
            return $._nonces[owner]++;
        }
    }

    /**
     * @dev Same as {_useNonce} but checking that `nonce` is the next valid for `owner`.
     */
    function _useCheckedNonce(address owner, uint256 nonce) internal virtual {
        uint256 current = _useNonce(owner);
        if (nonce != current) {
            revert InvalidAccountNonce(owner, current);
        }
    }

    /**
     * @dev Invalidate all nonces up to a certain value.
     *
     */
    function _invalidateUpToNonce(address owner, uint256 newNonce)
        internal
        virtual
        returns (uint256)
    {
        NoncesStorage storage $ = _getNoncesStorage();
        if (newNonce <= $._nonces[owner]) {
            revert InvalidAccountNonce(owner, newNonce);
        }
        unchecked {
            $._nonces[owner] = newNonce;
        }
        return newNonce - 1;
    }
}
