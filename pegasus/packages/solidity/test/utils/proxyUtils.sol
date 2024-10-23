// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

// solhint-disable-next-line no-global-import
import "forge-std/Test.sol";

contract ProxyUtils is Test {
    function getImplementation(address proxyAddress) public view returns (address addr) {
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 proxySlot = vm.load(proxyAddress, implSlot);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0, proxySlot)
            addr := mload(0)
        }
    }

    function getAdmin(address proxyAddress) public view returns (address addr) {
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        bytes32 proxySlot = vm.load(proxyAddress, adminSlot);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0, proxySlot)
            addr := mload(0)
        }
    }
}
