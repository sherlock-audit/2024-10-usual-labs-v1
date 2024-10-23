// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VerifyAdapterOwnershipScript is Script {
    address public constant USUAL_MULTISIG = 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7;

    address public constant USD0_ADAPTER_ETHEREUM = 0xE14C486b93C3B62F76F88cf8FE4B36fb672f3B26;
    address public constant USD0PP_ADAPTER_ETHEREUM = 0xd155d91009cbE9B0204B06CE1b62bf1D793d3111;

    function run() public view {
        if (block.chainid != 1) {
            revert("This script is intended to run on Ethereum mainnet only");
        }

        console.log("Verifying ownership of USD0 L1OFTAdapter");
        verifyOwnership(USD0_ADAPTER_ETHEREUM);

        console.log("Verifying ownership of USD0PP L1OFTAdapter");
        verifyOwnership(USD0PP_ADAPTER_ETHEREUM);

        console.log("Ownership verification completed successfully");
    }

    function verifyOwnership(address adapterAddress) internal view {
        Ownable adapter = Ownable(adapterAddress);
        address currentOwner = adapter.owner();

        require(currentOwner == USUAL_MULTISIG, "Ownership not transferred to the expected address");
        console.log("Ownership verified for adapter:", adapterAddress);
    }
}
