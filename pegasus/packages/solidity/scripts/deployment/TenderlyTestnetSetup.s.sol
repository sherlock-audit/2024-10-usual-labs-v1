// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {CONTRACT_REGISTRY_ACCESS} from "src/constants.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IUSYCAuthority, USYCRole} from "test/interfaces/IUSYCAuthority.sol";
import {IUSYC} from "test/interfaces/IUSYC.sol";
import {USUAL_MULTISIG_MAINNET, REGISTRY_CONTRACT_MAINNET} from "src/constants.sol";
import {USYC, USDC} from "src/mock/constants.sol";
import {BaseScript} from "scripts/deployment/Base.s.sol";

import {console} from "forge-std/console.sol";

// solhint-disable-next-line no-console
contract TenderlyTestnetSetup is BaseScript {
    // array of 17 addresses
    address[17] public users = [
        0x411FAB2b2A2811Fa7DeE401F8822De1782561804,
        0x62ca69D36F2425824b06BC2572069d9a1FE77A84,
        0x9374f2991Af90Cf9C72651f7b1DdAbAeD606597c,
        0xdFB5461d5Cc1CDeA956a69B0308970C10eAAEfea,
        0xF095731c807A08009099B0a3EBa61FA2Cf09b10B,
        0x60C54759ECF885e6f5Eb946A54479C2D92Ce4798,
        0x9AA63Dd70F7a4c8793d5570f4F2Bf6833C082A77,
        0x0E521985C17d45bE9F1B45C1106b99e711739383,
        0x007335277ddf0fA6d20dBB6Bf4f4b22799e2b8cB,
        0x61201ee3bc5B988d7c616870FA0381200AA9A11C,
        0x331817bB43e652611Ed53Ff9d8D2568159c666Aa,
        0x8e46Cc63f1DaE605D8B5fb74CC75458E217441c5,
        0xcdCa1ec25a2DB92C15586A6c23A3f7c4fb480DBf,
        0x66c7bE851fc1D042BAF6c720f3242CF5e29aaAfD,
        0xCE9832DC769092FcCf66b010a0B4484FE98cb3fa,
        0x071d4E75D72B31976d9FDF5755a8a36590950A27,
        0x4DA9c3b6b2925D00a12F265BeCC221dC32eCFdcB
    ];

    function run() public virtual override {
        super.run();
        // registryContract on mainnet
        registryContract = IRegistryContract(REGISTRY_CONTRACT_MAINNET);
        // go through all testers and allowlist them
        for (uint256 i = 0; i < users.length; i++) {
            _allowlist(users[i]);
            _whitelist(users[i]);
            _dealETHWithTenderly(users[i]);
            _dealERC20WithTenderly(USYC, users[i], 1_000_000e18);
            _dealERC20WithTenderly(USDC, users[i], 1_000_000e6);
        }
    }

    function _allowlist(address _to) internal {
        // get the registry access contract from the registry contract
        IRegistryAccess curRegistryAccess =
            IRegistryAccess(registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        vm.startBroadcast(USUAL_MULTISIG_MAINNET);
        curRegistryAccess.grantRole(keccak256("ALLOWLISTED"), _to);
        vm.stopBroadcast();
        console.log("%s ALLOWLISTED", _to);
    }

    function _dealETHWithTenderly(address _to) internal {
        if (_to.balance >= 100e18) return;
        console.log("dealing ETH WithTenderly to", _to);
        // set balance
        // string concatenation of the address and the amount
        string memory begin = "[\"";
        console.log("_to", _to);
        // convert address to into string
        string memory addressString = Strings.toHexString(uint160(_to), 20);
        string memory end = "\", \"0x56BC75E2D63100000\"]";
        string memory args = string(abi.encodePacked(begin, addressString, end));
        bytes memory result = vm.rpc("tenderly_setBalance", args);
        console.logBytes(result);
    }

    function _dealERC20WithTenderly(address _token, address _to, uint256 _amount) internal {
        // set balance
        console.log("set ERC20:%s balance WithTenderly to:%s", _token, _to);
        // string concatenation of the address and the amount
        string memory begin = "[\"";
        // convert address to into string
        string memory toAddressString = Strings.toHexString(uint160(_to), 20);
        string memory tokenAddressString = Strings.toHexString(uint160(_token), 20);
        string memory amountString = Strings.toHexString(_amount);
        string memory end = "\"]";
        string memory comma = "\",\"";
        string memory args = string(
            abi.encodePacked(
                begin, tokenAddressString, comma, toAddressString, comma, amountString, end
            )
        );
        console.logString(args);

        try vm.rpc("tenderly_setErc20Balance", args) {} catch {}
    }

    function _whitelist(address addressToWhitelist) internal {
        address authority = IUSYC(USYC).authority(); //0x470f3b37B9B20E13b0A2a5965Df6bD3f9640DFB4 authority
        address authOwner = IUSYCAuthority(authority).owner(); // 0xeE89a9eE62a5cC8a1FF4e9566ECe542856fE1C6D
        vm.startBroadcast(authOwner);
        IUSYCAuthority(authority).setUserRole(
            addressToWhitelist, USYCRole.Investor_MFFeederDomestic, true
        );
        vm.stopBroadcast();
    }
}
