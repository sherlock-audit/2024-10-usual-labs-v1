// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VerifyAdapterOwnershipScript is Script {
    address public constant USUAL_MULTISIG = 0x192482bdB33B670ac7dA705cEF9E98C93abeEc9a;

    address public constant USD0_ADAPTER_ARBITRUM = 0xE14C486b93C3B62F76F88cf8FE4B36fb672f3B26;
    address public constant USD0PP_ADAPTER_ARBITRUM = 0xd155d91009cbE9B0204B06CE1b62bf1D793d3111;

    function run() public view {
        if (block.chainid != 42_161) {
            revert("This script is intended to run on Arbitrum mainnet only");
        }

        console.log("Verifying ownership of USD0 OFTMintAndBurnAdapter on Arbitrum");
        verifyOwnership(USD0_ADAPTER_ARBITRUM);

        console.log("Verifying ownership of USD0PP OFTMintAndBurnAdapter on Arbitrum");
        verifyOwnership(USD0PP_ADAPTER_ARBITRUM);

        console.log("Ownership verification completed successfully");
    }

    function verifyOwnership(address adapterAddress) internal view {
        Ownable adapter = Ownable(adapterAddress);
        address currentOwner = adapter.owner();

        require(currentOwner == USUAL_MULTISIG, "Ownership not transferred to the expected address");
        console.log("Ownership verified for adapter:", adapterAddress);
    }
}
