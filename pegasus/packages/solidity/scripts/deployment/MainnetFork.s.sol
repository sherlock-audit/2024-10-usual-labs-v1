// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {DataPublisher} from "src/mock/dataPublisher.sol";
import {UsualOracle} from "src/oracles/UsualOracle.sol";
import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {TokenMapping} from "src/TokenMapping.sol";
import {Usd0} from "src/token/Usd0.sol";
import {AirdropTaxCollector} from "src/airdrop/AirdropTaxCollector.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Usual} from "src/token/Usual.sol";
import {UsualX} from "src/vaults/UsualX.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {UsualS} from "src/token/UsualS.sol";
import {UsualSP} from "src/token/UsualSP.sol";

import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";

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
    CONTRACT_USD0PP,
    CONTRACT_USD0,
    CONTRACT_USDC,
    VESTING_DURATION_THREE_YEARS,
    USUALSP_VESTING_STARTING_DATE,
    CONTRACT_USUALS,
    CONTRACT_USUALSP,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    AIRDROP_INITIAL_START_TIME,
    CONTRACT_USUAL,
    CONTRACT_USUALX,
    USUALS_BURN,
    USUAL_BURN,
    USUAL_MINT,
    USUALSName,
    USUALSSymbol,
    USUALName,
    USUALSymbol,
    AIRDROP_INITIAL_START_TIME,
    RATE0,
    USUALSSymbol,
    USUALX_WITHDRAW_FEE,
    USUALXName,
    USUALXSymbol,
    USUAL_MULTISIG_MAINNET,
    REGISTRY_CONTRACT_MAINNET,
    USUAL_PROXY_ADMIN_MAINNET
} from "src/constants.sol";
import {
    USD0Name,
    USD0Symbol,
    REGISTRY_SALT,
    REGISTRY_ACCESS_MAINNET,
    DETERMINISTIC_DEPLOYMENT_PROXY,
    REDEEM_FEE
} from "src/mock/constants.sol";
import {BaseScript} from "scripts/deployment/Base.s.sol";
import "forge-std/console.sol";

/// @title   MainnetForkScript contract
/// @notice  Used to deploy to mainnet fork so that we can keep the same addresses
///          we deploy all our contracts if they don't exist on mainnet or to use the deployed ones.

contract MainnetForkScript is BaseScript {
    TokenMapping public tokenMapping;
    DaoCollateral public daoCollateral;
    Usual public usualToken;
    UsualX public usualX;
    Usd0PP public usd0PP;
    UsualS public usualS;
    UsualSP public usualSP;
    SwapperEngine public swapperEngine;
    ClassicalOracle public classicalOracle;
    AirdropDistribution public airdropDistribution;
    DistributionModule public distributionModule;
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
        // Check that the script is running on the correct chain
        if (block.chainid != 1) {
            console.log("Invalid chain");
            return;
        }
        // we need to fund the USUAL_PROXY_ADMIN_MAINNET account with some ether
        vm.startBroadcast(deployerPrivateKey);
        registryAccess = IRegistryAccess(REGISTRY_ACCESS_MAINNET);
        // RegistryAccess
        registryContract = RegistryContract(REGISTRY_CONTRACT_MAINNET);

        // RegistryContract
        console.log("RegistryContract: ", address(registryContract));
        vm.stopBroadcast();
        vm.startBroadcast(USUAL_MULTISIG_MAINNET);

        console.log("RegistryAccess: ", address(registryAccess));

        tokenMapping = TokenMapping(registryContract.getContract(CONTRACT_TOKEN_MAPPING));
        console.log("TokenMapping: ", address(tokenMapping));

        // Oracle
        classicalOracle = ClassicalOracle(registryContract.getContract(CONTRACT_ORACLE));
        console.log("ClassicalOracle: ", address(classicalOracle));

        USD0 = IUsd0(registryContract.getContract(CONTRACT_USD0));

        address USD0Implementation = Upgrades.getImplementationAddress(address(USD0));
        console.log("USD0Implementation: ", USD0Implementation);
        vm.stopBroadcast();

        address USD0ProxyAdmin = Upgrades.getAdminAddress(address(USD0));
        console.log("USD0ProxyAdmin: ", USD0ProxyAdmin);
        Ownable proxy = Ownable(USD0ProxyAdmin);
        address usualProxyAdminMainnet = proxy.owner();

        vm.startBroadcast(usualProxyAdminMainnet);

        // Upgrade using V2
        USD0Implementation = address(new Usd0());
        // Upgrades as the ProxyAdmin contract
        ProxyAdmin(USD0ProxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(USD0)),
            USD0Implementation,
            // encode call data for initializeV2()
            abi.encodeWithSelector(Usd0.initializeV2.selector)
        );
        vm.stopBroadcast();
        vm.startBroadcast(USUAL_MULTISIG_MAINNET);
        registryContract.setContract(CONTRACT_USD0, address(USD0));
        console.log("USD0: ", address(USD0));
        USD0Implementation = Upgrades.getImplementationAddress(address(USD0));
        console.log("USD0Implementation after upgrade: ", USD0Implementation);
        try registryContract.getContract(CONTRACT_USUAL) {
            usualToken = Usual(registryContract.getContract(CONTRACT_USUAL));
        } catch {
            // Usual
            usualToken = Usual(
                Upgrades.deployTransparentProxy(
                    "Usual.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
                    abi.encodeCall(
                        Usual.initialize, (address(registryContract), USUALName, USUALSymbol)
                    )
                )
            );
            registryContract.setContract(CONTRACT_USUAL, address(usualToken));
        }

        console.log(
            "usualToken: ",
            address(usualToken),
            " implementation: ",
            Upgrades.getImplementationAddress(address(usualToken))
        );
        try registryContract.getContract(CONTRACT_USUALX) {
            usualX = UsualX(registryContract.getContract(CONTRACT_USUALX));
        } catch {
            usualX = UsualX(
                Upgrades.deployTransparentProxy(
                    "UsualX.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
                    abi.encodeCall(
                        UsualX.initialize,
                        (address(registryContract), USUALX_WITHDRAW_FEE, USUALXName, USUALXSymbol)
                    )
                )
            );
            registryContract.setContract(CONTRACT_USUALX, address(usualX));
        }

        console.log(
            "usualX: ",
            address(usualX),
            " implementation: ",
            Upgrades.getImplementationAddress(address(usualX))
        );
        swapperEngine = SwapperEngine(registryContract.getContract(CONTRACT_SWAPPER_ENGINE));

        console.log("swapperEngine: ", address(swapperEngine));

        daoCollateral = DaoCollateral(registryContract.getContract(CONTRACT_DAO_COLLATERAL));

        console.log("daoCollateral: ", address(daoCollateral));

        usd0PP = Usd0PP(registryContract.getContract(CONTRACT_USD0PP));
        address USD0ppImplementation = Upgrades.getImplementationAddress(address(usd0PP));
        console.log("USD0ppImplementation: ", USD0ppImplementation);
        vm.stopBroadcast();
        vm.startBroadcast(usualProxyAdminMainnet);
        address USD0ppProxyAdmin = Upgrades.getAdminAddress(address(usd0PP));
        // Upgrade using V2
        address usd0PPImplementation = address(new Usd0PP());
        // Upgrades as the ProxyAdmin contract
        ProxyAdmin(USD0ppProxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usd0PP)),
            usd0PPImplementation,
            abi.encodeCall(Usd0PP.initializeV1, ())
        );
        USD0ppImplementation = Upgrades.getImplementationAddress(address(usd0PP));
        console.log("USD0ppImplementation after upgrade: ", USD0ppImplementation);
        vm.stopBroadcast();
        vm.startBroadcast(USUAL_MULTISIG_MAINNET);
        try registryContract.getContract(CONTRACT_USUALS) {
            usualS = UsualS(registryContract.getContract(CONTRACT_USUALS));
        } catch {
            usualS = UsualS(
                Upgrades.deployTransparentProxy(
                    "UsualS.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
                    abi.encodeCall(
                        UsualS.initialize,
                        (IRegistryContract(registryContract), USUALSName, USUALSSymbol)
                    )
                )
            );
            registryContract.setContract(CONTRACT_USUALS, address(usualS));
        }
        console.log(
            "usualS: ",
            address(usualS),
            " implementation: ",
            Upgrades.getImplementationAddress(address(usualS))
        );

        try registryContract.getContract(CONTRACT_USUALSP) {
            usualSP = UsualSP(registryContract.getContract(CONTRACT_USUALSP));
        } catch {
            usualSP = UsualSP(
                Upgrades.deployTransparentProxy(
                    "UsualSP.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
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
        }
        console.log(
            "usualSP: ",
            address(usualSP),
            " implementation: ",
            Upgrades.getImplementationAddress(address(usualSP))
        );
        try registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR) {
            airdropTaxCollector =
                AirdropTaxCollector(registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR));
        } catch {
            airdropTaxCollector = AirdropTaxCollector(
                Upgrades.deployTransparentProxy(
                    "AirdropTaxCollector.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
                    abi.encodeCall(AirdropTaxCollector.initialize, (address(registryContract)))
                )
            );
            registryContract.setContract(
                CONTRACT_AIRDROP_TAX_COLLECTOR, address(airdropTaxCollector)
            );
        }
        console.log(
            "airdropTaxCollector: ",
            address(airdropTaxCollector),
            " implementation: ",
            Upgrades.getImplementationAddress(address(airdropTaxCollector))
        );
        try registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION) {
            airdropDistribution =
                AirdropDistribution(registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION));
        } catch {
            airdropDistribution = AirdropDistribution(
                Upgrades.deployTransparentProxy(
                    "AirdropDistribution.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
                    abi.encodeCall(AirdropDistribution.initialize, (address(registryContract)))
                )
            );
            registryContract.setContract(
                CONTRACT_AIRDROP_DISTRIBUTION, address(airdropDistribution)
            );
        }
        console.log(
            "airdropDistribution: ",
            address(airdropDistribution),
            " implementation: ",
            Upgrades.getImplementationAddress(address(airdropDistribution))
        );
        try registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE) {
            distributionModule =
                DistributionModule(registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE));
        } catch {
            distributionModule = DistributionModule(
                Upgrades.deployTransparentProxy(
                    "DistributionModule.sol",
                    USUAL_PROXY_ADMIN_MAINNET,
                    abi.encodeCall(
                        DistributionModule.initialize, (IRegistryContract(registryContract), RATE0)
                    )
                )
            );
            registryContract.setContract(CONTRACT_DISTRIBUTION_MODULE, address(distributionModule));
        }
        console.log(
            "distributionModule: ",
            address(distributionModule),
            " implementation: ",
            Upgrades.getImplementationAddress(address(distributionModule))
        );
        // set roles
        registryAccess.grantRole(USUALS_BURN, USUAL_MULTISIG_MAINNET);
        registryAccess.grantRole(USUAL_MINT, USUAL_MULTISIG_MAINNET);
        registryAccess.grantRole(USUAL_BURN, USUAL_MULTISIG_MAINNET);
        vm.stopBroadcast();
    }
}
