pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

// @dev This contract is a patch to the Usd0PP contract, it set the bondStart variable to a new value.
contract Patch0000 {
    struct Addr {
        address value;
    }

    struct Usd0PPStorageV0 {
        /// The start time of the bond period.
        uint256 bondStart;
        /// The address of the registry contract.
        address registryContract;
        /// The address of the registry access contract.
        address registryAccess;
        /// The USD0 token.
        IERC20 usd0;
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

    function patch(address oldImplementation, uint256 newBondStart) public {
        // Set name and symbol
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.bondStart = newBondStart;
        // Set implementation back to previous Usd0 implementation
        Addr storage implementation;
        assembly {
            implementation.slot :=
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc // IMPLEMENTATION_SLOT
        }
        implementation.value = oldImplementation; // current implementation
    }
}
