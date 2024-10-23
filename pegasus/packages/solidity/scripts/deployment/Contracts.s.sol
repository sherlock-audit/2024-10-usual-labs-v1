// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {DataPublisher} from "src/mock/dataPublisher.sol";
import {UsualOracle} from "src/oracles/UsualOracle.sol";
import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {TokenMapping} from "src/TokenMapping.sol";
import {Usd0} from "src/token/Usd0.sol";
import {AirdropTaxCollector} from "src/airdrop/AirdropTaxCollector.sol";

import {Usd0Harness} from "src/mock/token/Usd0Harness.sol";
import {Usd0PPHarness} from "src/mock/token/Usd0PPHarness.sol";
import {Usual} from "src/token/Usual.sol";
import {UsualX} from "src/vaults/UsualX.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {UsualS} from "src/token/UsualS.sol";
import {UsualSP} from "src/token/UsualSP.sol";

import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";
import {RwaFactoryMock} from "src/mock/rwaFactoryMock.sol";

import {SwapperEngine} from "src/swapperEngine/SwapperEngine.sol";
import {AirdropDistribution} from "src/airdrop/AirdropDistribution.sol";
import {DistributionModule} from "src/distribution/DistributionModule.sol";

import {ClassicalOracle} from "src/oracles/ClassicalOracle.sol";

import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {ProxyAdmin} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {
    CONTRACT_DAO_COLLATERAL,
    CONTRACT_DATA_PUBLISHER,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_AIRDROP_DISTRIBUTION,
    CONTRACT_DISTRIBUTION_MODULE,
    CONTRACT_ORACLE,
    CONTRACT_ORACLE_USUAL,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_TOKEN_MAPPING,
    CONTRACT_TREASURY,
    CONTRACT_USD0PP,
    CONTRACT_USD0,
    CONTRACT_USDC,
    VESTING_DURATION_THREE_YEARS,
    USUALSP_VESTING_STARTING_DATE,
    CONTRACT_USUALS,
    CONTRACT_USUALSP,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    CONTRACT_USUAL,
    CONTRACT_USUALX,
    USUALSName,
    USUALSSymbol,
    RATE0,
    USUALSSymbol,
    USUALX_WITHDRAW_FEE,
    USUALXName,
    USUALXSymbol,
    USUALName,
    USUALSymbol
} from "src/constants.sol";
import {
    USD0Name,
    USD0Symbol,
    REGISTRY_SALT,
    DETERMINISTIC_DEPLOYMENT_PROXY,
    REDEEM_FEE,
    CONTRACT_RWA_FACTORY
} from "src/mock/constants.sol";
import {BaseScript} from "scripts/deployment/Base.s.sol";

contract ContractScript is BaseScript {
    TokenMapping public tokenMapping;

    DaoCollateral public daoCollateral;
    RwaFactoryMock public rwaFactoryMock;
    Usual public usualToken;
    UsualX public usualX;
    Usd0PP public usd0PP;
    UsualS public usualS;
    UsualSP public usualSP;
    SwapperEngine public swapperEngine;
    AirdropDistribution public airdropDistribution;
    DistributionModule public distributionModule;
    DataPublisher public dataPublisher;
    UsualOracle public usualOracle;
    ClassicalOracle public classicalOracle;
    AirdropTaxCollector public airdropTaxCollector;

    function _computeAddress(bytes32 salt, bytes memory _code, address _usual)
        internal
        pure
        returns (address addr)
    {
        bytes memory bytecode = abi.encodePacked(_code, abi.encode(_usual));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), DETERMINISTIC_DEPLOYMENT_PROXY, salt, keccak256(bytecode)
            )
        );
        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    function run() public virtual override {
        super.run();
        Options memory upgradeOptions;
        vm.startBroadcast(deployerPrivateKey);
        address computedRegAccessAddress =
            _computeAddress(REGISTRY_SALT, type(RegistryAccess).creationCode, usual);
        registryAccess = IRegistryAccess(computedRegAccessAddress);
        // RegistryAccess
        if (computedRegAccessAddress.code.length == 0) {
            upgradeOptions.defender.salt = REGISTRY_SALT;
            registryAccess = IRegistryAccess(
                Upgrades.deployTransparentProxy(
                    "RegistryAccess.sol",
                    usualProxyAdmin,
                    abi.encodeCall(RegistryAccess.initialize, (address(usual))),
                    upgradeOptions
                )
            );
        }
        address computedRegContractAddress = _computeAddress(
            REGISTRY_SALT, type(RegistryContract).creationCode, address(registryAccess)
        );
        registryContract = RegistryContract(computedRegContractAddress);
        // RegistryContract
        if (computedRegContractAddress.code.length == 0) {
            upgradeOptions.defender.salt = REGISTRY_SALT;
            registryContract = IRegistryContract(
                Upgrades.deployTransparentProxy(
                    "RegistryContract.sol",
                    usualProxyAdmin,
                    abi.encodeCall(RegistryContract.initialize, (address(registryAccess))),
                    upgradeOptions
                )
            );
        }
        vm.stopBroadcast();
        vm.startBroadcast(usualPrivateKey);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));
        vm.stopBroadcast();

        vm.startBroadcast(usualPrivateKey);

        // TokenMapping
        tokenMapping = TokenMapping(
            Upgrades.deployTransparentProxy(
                "TokenMapping.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    TokenMapping.initialize, (address(registryAccess), address(registryContract))
                )
            )
        );
        registryContract.setContract(CONTRACT_TOKEN_MAPPING, address(tokenMapping));

        // BucketDistribution
        registryContract.setContract(CONTRACT_TREASURY, treasury);

        // Oracle
        dataPublisher = new DataPublisher(address(registryContract));
        registryContract.setContract(CONTRACT_DATA_PUBLISHER, address(dataPublisher));

        usualOracle = UsualOracle(
            Upgrades.deployTransparentProxy(
                "UsualOracle.sol",
                usualProxyAdmin,
                abi.encodeCall(UsualOracle.initialize, address(registryContract))
            )
        );
        registryContract.setContract(CONTRACT_ORACLE_USUAL, address(usualOracle));

        classicalOracle = ClassicalOracle(
            Upgrades.deployTransparentProxy(
                "ClassicalOracle.sol",
                usualProxyAdmin,
                abi.encodeCall(ClassicalOracle.initialize, address(registryContract))
            )
        );
        registryContract.setContract(CONTRACT_ORACLE, address(classicalOracle));

        // Usd0
        USD0 = IUsd0(
            Upgrades.deployTransparentProxy(
                "Usd0Harness.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    Usd0Harness.initialize, (address(registryContract), USD0Name, USD0Symbol)
                )
            )
        );
        vm.stopBroadcast();
        vm.startBroadcast(usualProxyAdminPrivateKey);
        // Upgrade using V2
        // Get ProxyAdmin
        address USD0ProxyAdmin = Upgrades.getAdminAddress(address(USD0));
        // Get deployed implementation
        address USD0Implementation = Upgrades.getImplementationAddress(address(USD0));
        // Upgrades as the ProxyAdmin contract
        ProxyAdmin(USD0ProxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(USD0)),
            USD0Implementation,
            abi.encodeCall(Usd0Harness.initializeV1, (registryContract))
        );
        ProxyAdmin(USD0ProxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(USD0)),
            USD0Implementation,
            // encode call data for initializeV2()
            abi.encodeWithSelector(Usd0.initializeV2.selector)
        );
        vm.stopBroadcast();
        vm.startBroadcast(usualPrivateKey);
        registryContract.setContract(CONTRACT_USD0, address(USD0));

        // Usual
        usualToken = Usual(
            Upgrades.deployTransparentProxy(
                "Usual.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    Usual.initialize, (address(registryContract), USUALName, USUALSymbol)
                )
            )
        );
        registryContract.setContract(CONTRACT_USUAL, address(usualToken));
        usualX = UsualX(
            Upgrades.deployTransparentProxy(
                "UsualX.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    UsualX.initialize,
                    (address(registryContract), USUALX_WITHDRAW_FEE, USUALXName, USUALXSymbol)
                )
            )
        );
        registryContract.setContract(CONTRACT_USUALX, address(usualX));
        // USDC

        registryContract.setContract(CONTRACT_USDC, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        // Swapper Engine

        swapperEngine = SwapperEngine(
            Upgrades.deployTransparentProxy(
                "SwapperEngine.sol",
                usualProxyAdmin,
                abi.encodeCall(SwapperEngine.initialize, (address(registryContract)))
            )
        );
        registryContract.setContract(CONTRACT_SWAPPER_ENGINE, address(swapperEngine));

        // DAOCollateral
        daoCollateral = DaoCollateral(
            Upgrades.deployTransparentProxy(
                "DaoCollateral.sol",
                usualProxyAdmin,
                abi.encodeCall(DaoCollateral.initialize, (address(registryContract), REDEEM_FEE))
            )
        );
        registryContract.setContract(CONTRACT_DAO_COLLATERAL, address(daoCollateral));

        // RwaFactoryMock
        rwaFactoryMock = new RwaFactoryMock(address(registryContract));
        registryContract.setContract(CONTRACT_RWA_FACTORY, address(rwaFactoryMock));

        // USD0PP
        uint256 bondStartTime = block.timestamp + 100;
        usd0PP = Usd0PPHarness(
            Upgrades.deployTransparentProxy(
                "Usd0PPHarness.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    Usd0PPHarness.initialize,
                    (address(registryContract), "Bond", "BND", bondStartTime)
                )
            )
        );

        vm.stopBroadcast();
        vm.startBroadcast(usualProxyAdminPrivateKey);
        // Upgrade using V2
        // Get ProxyAdmin
        address USD0PPProxyAdmin = Upgrades.getAdminAddress(address(usd0PP));
        // Get deployed implementation
        address USD0PPImplementation = Upgrades.getImplementationAddress(address(usd0PP));
        // Upgrades as the ProxyAdmin contract
        ProxyAdmin(USD0PPProxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usd0PP)),
            USD0PPImplementation,
            abi.encodeCall(Usd0PP.initializeV1, ())
        );

        vm.stopBroadcast();
        vm.startBroadcast(usualPrivateKey);
        registryContract.setContract(CONTRACT_USD0PP, address(usd0PP));

        // USUALS
        usualS = UsualS(
            Upgrades.deployTransparentProxy(
                "UsualS.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    UsualS.initialize,
                    (IRegistryContract(registryContract), USUALSName, USUALSSymbol)
                )
            )
        );
        registryContract.setContract(CONTRACT_USUALS, address(usualS));

        // USUALSP
        usualSP = UsualSP(
            Upgrades.deployTransparentProxy(
                "UsualSP.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    UsualSP.initialize,
                    (
                        address(registryContract),
                        USUALSP_VESTING_STARTING_DATE,
                        VESTING_DURATION_THREE_YEARS
                    )
                )
            )
        );
        registryContract.setContract(CONTRACT_USUALSP, address(usualSP));

        // AirdropTaxCollector
        airdropTaxCollector = AirdropTaxCollector(
            Upgrades.deployTransparentProxy(
                "AirdropTaxCollector.sol",
                usualProxyAdmin,
                abi.encodeCall(AirdropTaxCollector.initialize, (address(registryContract)))
            )
        );
        registryContract.setContract(CONTRACT_AIRDROP_TAX_COLLECTOR, address(airdropTaxCollector));

        // AirdropDistribution
        airdropDistribution = AirdropDistribution(
            Upgrades.deployTransparentProxy(
                "AirdropDistribution.sol",
                usualProxyAdmin,
                abi.encodeCall(AirdropDistribution.initialize, (address(registryContract)))
            )
        );
        registryContract.setContract(CONTRACT_AIRDROP_DISTRIBUTION, address(airdropDistribution));

        // DistributionModule
        distributionModule = DistributionModule(
            Upgrades.deployTransparentProxy(
                "DistributionModule.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    DistributionModule.initialize, (IRegistryContract(registryContract), RATE0)
                )
            )
        );
        registryContract.setContract(CONTRACT_DISTRIBUTION_MODULE, address(distributionModule));

        vm.stopBroadcast();
    }
}
