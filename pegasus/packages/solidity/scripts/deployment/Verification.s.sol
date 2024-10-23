// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_DAO_COLLATERAL,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_TOKEN_MAPPING,
    CONTRACT_ORACLE,
    CONTRACT_USD0,
    CONTRACT_USD0PP,
    CONTRACT_USUALX,
    CONTRACT_USUALSP,
    CONTRACT_USUALS,
    CONTRACT_USUAL,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    CONTRACT_AIRDROP_DISTRIBUTION,
    CONTRACT_DISTRIBUTION_MODULE,
    USD0_BURN,
    USD0_MINT,
    USUAL_BURN,
    DEFAULT_ADMIN_ROLE,
    INTENT_MATCHING_ROLE,
    USUAL_MINT,
    USUALS_BURN,
    USUAL_BURN,
    USUAL_PROXY_ADMIN_MAINNET,
    USUAL_MULTISIG_MAINNET
} from "src/constants.sol";

contract VerifyScript is Script {
    IRegistryContract public registryContract;
    IRegistryAccess public registryAccess;
    address public usd0;
    address public tokenMapping;
    address public daoCollateral;
    address public classicalOracle;
    address public usd0PP;
    address public swapperEngine;
    address public airdropTaxCollector;
    address public airdropDistribution;
    address public distributionModule;
    address public usual;
    address public usualS;
    address public usualSP;
    address public usualX;

    address public constant CONTRACT_REGISTRY_MAINNET = 0x0594cb5ca47eFE1Ff25C7B8B43E221683B4Db34c;
    address public constant CONTRACT_REGISTRY_SEPOLIA = 0x23aaD68FF5fb2FeA01eb83E27583396892d41046;

    address public constant TREASURY_MAINNET = 0xdd82875f0840AAD58a455A70B88eEd9F59ceC7c7;
    address public constant TREASURY_SEPOLIA = 0xCA764828708a6d6dD36220DF36EED2E8DeFD9554;

    address public constant USUAL_SEPOLIA = 0x91a8a1495291e8aBf5B7580F0044437d2709C5E0;

    //TODO: Add the correct addresses once they are deployed

    address public constant USUALX_SEPOLIA = 0x91a8a1495291e8aBf5B7580F0044437d2709C5E0;

    address public constant USUAL_PROXY_ADMIN_SEPOLIA = 0x9509Bb36F2D3122933942033c7594C7Df1361751;

    address usd0Sepolia = 0x3160BD57F4c47cd142aa1F1643D38621FB1537C4;
    address usualXSepolia = 0x91a8a1495291e8aBf5B7580F0044437d2709C5E0;
    address tokenMappingSepolia = 0xe9430377b4fbeaE89ce2709094FBF832CAe7DA6E;
    address daoCollateralSepolia = 0xd20Be556DD4799A93e901124238BC15c8252bFE9;
    address registryAccessSepolia = 0xf3FF8F4619057b8B8eAA2e4828E1C0746a48E454;
    address registryContractSepolia = 0x23aaD68FF5fb2FeA01eb83E27583396892d41046;
    address classicalOracleSepolia = 0xF80e6f6bC3bAAC3C46c085c90D01AA3FEce3a6EE;

    address usd0Mainnet = 0x73A15FeD60Bf67631dC6cd7Bc5B6e8da8190aCF5;
    address tokenMappingMainnet = 0x43882C864a406D55411b8C166bCA604709fDF624;
    address daoCollateralMainnet = 0xde6e1F680C4816446C8D515989E2358636A38b04;
    address registryAccessMainnet = 0x0D374775E962c3608B8F0A4b8B10567DF739bb56;
    address registryContractMainnet = 0x0594cb5ca47eFE1Ff25C7B8B43E221683B4Db34c;
    address classicalOracleMainnet = 0xb97e163cE6A8296F36112b042891CFe1E23C35BF;
    address usd0PPMainnet = 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0;
    address swapperEngineMainnet = 0xB969B0d14F7682bAF37ba7c364b351B830a812B2;
    address airdropTaxCollectorMainnet = 0xA8471e82B8080211A173d76573193fb77E329bbc;
    address airdropDistributionMainnet = 0x6fdb38C02dCa46dD38Ddc46289a33cE308c49944;
    address distributionModuleMainnet = 0xD0cB6c7C09e4D62c85d384428d7CE53D92340881;
    address usualMainnet = 0xc89904631f38A167458acdAc501753f35780E236;
    address usualSMainnet = 0xA758De757587a032bC3f0C30A24013C18c2659E1;
    address usualSPMainnet = 0xe607Ca5697229B8d9840a271C5235355D728FF7E;
    address usualXMainnet = 0x337144d7387E94D37372EE383a89608fc908B233;

    address intentMatcherMainnet = 0x422565b76e5C2E633C8456F106988F4Ec2cFb4EB;

    address usd0MainnetImplementation = 0x1859f8a5702D88Fb894C740db1c519305C9d2280;
    address tokenMappingMainnetImplementation = 0x334b18E5e81657efA2057F80e19b8E81F0e5783C;
    address daoCollateralMainnetImplementation = 0xdFBeF524f172dF7e37cCbE56e97ec5f8cE3c0c92;
    address registryAccessMainnetImplementation = 0x7D355D14b8dE1210ac69EbE3aEbCc5e002cDf63B;
    address registryContractMainnetImplementation = 0x81221180B4B2fc01975817d4B7E1F4ADADcf8388;
    address classicalOracleMainnetImplementation = 0xdec568b8b19ba18af4F48863eF096a383C0eD8FD;
    address usd0PPMainnetImplementation = 0x06fAB42BcF6298aa9aC4dF802141f438609193a9;
    address swapperEngineMainnetImplementation = 0x9A46646c3974aa0004f4844B5fcD9C41B2337A7f;
    address airdropTaxCollectorMainnetImplementation = 0x56187364dB6F22ba3048Bb234211c2207731eeea;
    address airdropDistributionMainnetImplementation = 0x79aCeCc9f937F484b72B3C5FeD6e08703e2A707f;
    address distributionModuleMainnetImplementation = 0x1EE76094870F11Af7a93f01E41670C9325C1d061;
    address usualXMainnetImplementation = 0x2A2e83F5B1D6FC66e87F6f3946d201Fb92357abB;
    address usualMainnetImplementation = 0xC91b9B6232FEFC111ed4c1Bea1373b1d089EaBAC;
    address usualSMainnetImplementation = 0xEe9bA50C204952fF7adDa4609850Cb8ea1Ede1de;
    address usualSPMainnetImplementation = 0xDa0Bb96aAd78845A933E7Da2541C8310Dd9a0a06;

    ProxyAdmin usd0ProxyAdmin;
    ProxyAdmin usd0PPProxyAdmin;
    ProxyAdmin registryAccessProxyAdmin;
    ProxyAdmin registryContractProxyAdmin;
    ProxyAdmin tokenMappingProxyAdmin;
    ProxyAdmin daoCollateralProxyAdmin;
    ProxyAdmin classicalOracleProxyAdmin;
    ProxyAdmin swapperEngineProxyAdmin;
    ProxyAdmin airdropTaxCollectorProxyAdmin;
    ProxyAdmin airdropDistributionProxyAdmin;
    ProxyAdmin distributionModuleProxyAdmin;
    ProxyAdmin usualXProxyAdmin;
    ProxyAdmin usualProxyAdmin;
    ProxyAdmin usualSProxyAdmin;
    ProxyAdmin usualSPProxyAdmin;

    function run() public {
        if (block.chainid == 1) {
            // Mainnet
            registryContract = IRegistryContract(CONTRACT_REGISTRY_MAINNET);
        } else if (block.chainid == 11_155_111) {
            // Sepolia
            registryContract = IRegistryContract(CONTRACT_REGISTRY_SEPOLIA);
        } else {
            revert("Unsupported network");
        }
        registryAccess = IRegistryAccess(registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        daoCollateral = registryContract.getContract(CONTRACT_DAO_COLLATERAL);
        usd0 = registryContract.getContract(CONTRACT_USD0);
        tokenMapping = registryContract.getContract(CONTRACT_TOKEN_MAPPING);
        classicalOracle = registryContract.getContract(CONTRACT_ORACLE);
        usd0PP = registryContract.getContract(CONTRACT_USD0PP);
        swapperEngine = registryContract.getContract(CONTRACT_SWAPPER_ENGINE);
        airdropTaxCollector = registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR);
        airdropDistribution = registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION);
        distributionModule = registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE);
        usualX = registryContract.getContract(CONTRACT_USUALX);
        usual = registryContract.getContract(CONTRACT_USUAL);
        usualS = registryContract.getContract(CONTRACT_USUALS);
        usualSP = registryContract.getContract(CONTRACT_USUALSP);

        console.log("usualMainnet: ", usualMainnet);
        verifyExpectedAddress(usualMainnet, usual);
        // Set the RegistryAccess contract address and expected addresses based on the network
        if (block.chainid == 1) {
            console.log("####################################################");
            console.log("# Fetching addresses from Mainnet ContractRegistry #");
            console.log("####################################################");
            // Mainnet
            verifyExpectedAddress(usd0Mainnet, usd0);
            verifyExpectedAddress(tokenMappingMainnet, tokenMapping);
            verifyExpectedAddress(daoCollateralMainnet, daoCollateral);
            verifyExpectedAddress(registryAccessMainnet, address(registryAccess));
            verifyExpectedAddress(usd0PPMainnet, usd0PP);
            verifyExpectedAddress(swapperEngineMainnet, swapperEngine);
            verifyExpectedAddress(airdropTaxCollector, airdropTaxCollectorMainnet);
            verifyExpectedAddress(airdropDistribution, airdropDistributionMainnet);
            verifyExpectedAddress(distributionModule, distributionModuleMainnet);
            verifyExpectedAddress(usualXMainnet, usualX);
            verifyExpectedAddress(usualMainnet, usual);
            verifyExpectedAddress(usualSMainnet, usualS);
            verifyExpectedAddress(usualSPMainnet, usualSP);

            usd0ProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usd0Mainnet));
            registryAccessProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(registryAccessMainnet));
            registryContractProxyAdmin =
                ProxyAdmin(Upgrades.getAdminAddress(registryContractMainnet));
            tokenMappingProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(tokenMappingMainnet));
            daoCollateralProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(daoCollateralMainnet));
            classicalOracleProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(classicalOracleMainnet));
            swapperEngineProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(swapperEngineMainnet));
            usd0PPProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usd0PPMainnet));
            airdropTaxCollectorProxyAdmin =
                ProxyAdmin(Upgrades.getAdminAddress(airdropTaxCollectorMainnet));
            airdropDistributionProxyAdmin =
                ProxyAdmin(Upgrades.getAdminAddress(airdropDistributionMainnet));
            distributionModuleProxyAdmin =
                ProxyAdmin(Upgrades.getAdminAddress(distributionModuleMainnet));
            usualXProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usualXMainnet));
            usualProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usualMainnet));
            usualSProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usualSMainnet));
            usualSPProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usualSPMainnet));

            console.log("Verifying Accounts Assigned the role: USD0_MINT");
            verifyRole(USD0_MINT, daoCollateral);
            console.log("Verifying Accounts Assigned the role: USD0_BURN");
            verifyRole(USD0_BURN, daoCollateral);
            console.log("Verifying Accounts Assigned the role: DEFAULT_ADMIN_ROLE");
            verifyRole(DEFAULT_ADMIN_ROLE, USUAL_MULTISIG_MAINNET);
            console.log("Verifying Accounts Assigned the role: INTENT_MATCHING_ROLE");
            verifyRole(INTENT_MATCHING_ROLE, intentMatcherMainnet);
            console.log("Verifying Accounts Assigned the role: USUAL_BURN");
            verifyRole(USUAL_BURN, USUAL_MULTISIG_MAINNET);
            console.log("Verifying Accounts Assigned the role: USUAL_MINT");
            verifyRole(USUAL_MINT, USUAL_MULTISIG_MAINNET);
            console.log("Verifying Accounts Assigned the role: USUALS_BURN");
            verifyRole(USUALS_BURN, USUAL_MULTISIG_MAINNET);

            console.log("###################################################################");
            console.log("# Verifying the owner of the admin contracts for proxy is correct #");
            console.log("###################################################################");

            verifyOwner(usd0ProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("USD0 ProxyAdmin OK");
            verifyOwner(registryAccessProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("RegistryAccess ProxyAdmin OK");
            verifyOwner(registryContractProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("RegistryContract ProxyAdmin OK");
            verifyOwner(tokenMappingProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("TokenMappingProxyAdmin OK");
            verifyOwner(daoCollateralProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("DaoCollateral ProxyAdmin OK");
            verifyOwner(classicalOracleProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("ClassicalOracle ProxyAdmin OK");
            verifyOwner(swapperEngineProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("SwapperEngine ProxyAdmin OK");
            verifyOwner(usd0PPProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("USD0++ ProxyAdmin OK");
            verifyOwner(airdropTaxCollectorProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("AirdropTaxCollector ProxyAdmin OK");
            verifyOwner(airdropDistributionProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("AirdropDistribution ProxyAdmin OK");
            verifyOwner(distributionModuleProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("DistributionModule ProxyAdmin OK");
            verifyOwner(usualXProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("UsualX ProxyAdmin OK");
            verifyOwner(usualProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("Usual ProxyAdmin OK");
            verifyOwner(usualSProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("UsualS ProxyAdmin OK");
            verifyOwner(usualSPProxyAdmin, USUAL_PROXY_ADMIN_MAINNET);
            console.log("UsualSP ProxyAdmin OK");

            console.log("######################################################");
            console.log("# Verifying the implementation addresses are what we expect #");
            console.log("######################################################");

            verifyImplementation(usd0Mainnet, usd0MainnetImplementation);
            console.log("USD0 implementation OK");
            verifyImplementation(registryAccessMainnet, registryAccessMainnetImplementation);
            console.log("RegistryAccess implementation OK");
            verifyImplementation(registryContractMainnet, registryContractMainnetImplementation);
            console.log("RegistryContract implementation OK");
            verifyImplementation(tokenMappingMainnet, tokenMappingMainnetImplementation);
            console.log("TokenMapping implementation OK");
            verifyImplementation(daoCollateralMainnet, daoCollateralMainnetImplementation);
            console.log("DaoCollateral implementation OK");
            verifyImplementation(classicalOracleMainnet, classicalOracleMainnetImplementation);
            console.log("ClassicalOracle implementation OK");
            verifyImplementation(swapperEngineMainnet, swapperEngineMainnetImplementation);
            console.log("SwapperEngine implementation OK");
            verifyImplementation(usd0PPMainnet, usd0PPMainnetImplementation);
            console.log("USD0++ implementation OK");
            verifyImplementation(airdropTaxCollector, airdropTaxCollectorMainnetImplementation);
            console.log("AirdropTaxCollector implementation OK");
            verifyImplementation(airdropDistribution, airdropDistributionMainnetImplementation);
            console.log("AirdropDistribution implementation OK");
            verifyImplementation(distributionModule, distributionModuleMainnetImplementation);
            console.log("DistributionModule implementation OK");
            verifyImplementation(usualXMainnet, usualXMainnetImplementation);
            console.log("UsualX implementation OK");
            verifyImplementation(usualMainnet, usualMainnetImplementation);
            console.log("Usual implementation OK");
            verifyImplementation(usualSMainnet, usualSMainnetImplementation);
            console.log("UsualS implementation OK");
            verifyImplementation(usualSPMainnet, usualSPMainnetImplementation);
            console.log("UsualSP implementation OK");
        } else if (block.chainid == 11_155_111) {
            console.log("Fetching addresses from Sepolia ContractRegistry");
            // Sepolia testnet
            verifyExpectedAddress(usd0Sepolia, usd0);
            verifyExpectedAddress(tokenMappingSepolia, tokenMapping);
            verifyExpectedAddress(daoCollateralSepolia, daoCollateral);
            verifyExpectedAddress(registryAccessSepolia, address(registryAccess));
            usd0ProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usd0Sepolia));
            registryAccessProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(registryAccessSepolia));
            registryContractProxyAdmin =
                ProxyAdmin(Upgrades.getAdminAddress(registryContractSepolia));
            tokenMappingProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(tokenMappingSepolia));
            daoCollateralProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(daoCollateralSepolia));
            classicalOracleProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(classicalOracleSepolia));

            console.log("Verifying Accounts Assigned the role: DEFAULT_ADMIN_ROLE");
            verifyRole(DEFAULT_ADMIN_ROLE, USUAL_SEPOLIA);

            console.log("Verifying Accounts Assigned the role: USD0_MINT");
            verifyRole(USD0_MINT, daoCollateral);

            console.log("Verifying Accounts Assigned the role: USD0_BURN");
            verifyRole(USD0_BURN, daoCollateral);

            console.log("Verifying the owner of the admin contracts for proxy is correct");
            verifyOwner(usd0ProxyAdmin, USUAL_PROXY_ADMIN_SEPOLIA);
            console.log("USD0 ProxyAdmin OK");
            verifyOwner(registryAccessProxyAdmin, USUAL_PROXY_ADMIN_SEPOLIA);
            console.log("RegistryAccess ProxyAdmin OK");
            verifyOwner(registryContractProxyAdmin, USUAL_PROXY_ADMIN_SEPOLIA);
            console.log("RegistryContract ProxyAdmin OK");
            verifyOwner(tokenMappingProxyAdmin, USUAL_PROXY_ADMIN_SEPOLIA);
            console.log("TokenMappingProxyAdmin OK");
            verifyOwner(daoCollateralProxyAdmin, USUAL_PROXY_ADMIN_SEPOLIA);
            console.log("DaoCollateral ProxyAdmin OK");
            verifyOwner(classicalOracleProxyAdmin, USUAL_PROXY_ADMIN_SEPOLIA);
            console.log("ClassicalOracle ProxyAdmin OK");
        } else {
            revert("Unsupported network");
        }
        DisplayProxyAdminAddresses();
    }

    function verifyRole(bytes32 role, address roleAddress) internal view {
        bool hasRole = registryAccess.hasRole(role, roleAddress);
        require(hasRole, "Role not set correctly");
        console.log("Role verified for address", roleAddress);
    }

    function verifyOwner(ProxyAdmin proxyAdmin, address owner) internal view {
        require(proxyAdmin.owner() == owner);
    }

    function verifyImplementation(address proxy, address implementation) internal view {
        require(
            Upgrades.getImplementationAddress(proxy) == implementation,
            "Implementation address for proxy is not correct"
        );
    }

    function verifyExpectedAddress(address expected, address actual) internal pure {
        require(expected == actual, "Address does not match expected on current network");
    }

    function DisplayProxyAdminAddresses() public view {
        IRegistryContract RegistryContractProxy;
        // Check that the script is running on the correct chain
        if (block.chainid == 1) {
            RegistryContractProxy = IRegistryContract(CONTRACT_REGISTRY_MAINNET);
        } else if (block.chainid == 11_155_111) {
            RegistryContractProxy = IRegistryContract(CONTRACT_REGISTRY_SEPOLIA);
        } else {
            console.log("Invalid chain");
            return;
        }
        address usd0_ = RegistryContractProxy.getContract(CONTRACT_USD0);
        address usualToken_ = RegistryContractProxy.getContract(CONTRACT_USUAL);
        address usd0pp_ = RegistryContractProxy.getContract(CONTRACT_USD0PP);
        address usualS_ = RegistryContractProxy.getContract(CONTRACT_USUALS);
        address usualSP_ = RegistryContractProxy.getContract(CONTRACT_USUALSP);
        address registryAccess_ = RegistryContractProxy.getContract(CONTRACT_REGISTRY_ACCESS);
        address tokenMapping_ = RegistryContractProxy.getContract(CONTRACT_TOKEN_MAPPING);
        address daoCollateral_ = RegistryContractProxy.getContract(CONTRACT_DAO_COLLATERAL);
        address classicalOracle_ = RegistryContractProxy.getContract(CONTRACT_ORACLE);
        address swapperEngine_ = RegistryContractProxy.getContract(CONTRACT_SWAPPER_ENGINE);
        address airdropTaxCollector_ =
            RegistryContractProxy.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR);
        address airdropDistribution_ =
            RegistryContractProxy.getContract(CONTRACT_AIRDROP_DISTRIBUTION);
        address distributionModule_ =
            RegistryContractProxy.getContract(CONTRACT_DISTRIBUTION_MODULE);

        ProxyAdmin proxyAdmin;
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usd0_));
        console.log("USD0 ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usualToken_));
        console.log("USUAL ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usd0pp_));
        console.log("USD0++ ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usualS_));
        console.log("UsualS ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usualSP_));
        console.log("UsualSP ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(registryAccess_));
        console.log("RegistryAccess ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(address(RegistryContractProxy)));
        console.log(
            "RegistryContract ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner()
        );
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(tokenMapping_));
        console.log("TokenMapping ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(daoCollateral_));
        console.log("DaoCollateral ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(swapperEngine_));
        console.log("SwapperEngine ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(classicalOracle_));
        console.log("ClassicalOracle ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner());
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(airdropTaxCollector_));
        console.log(
            "AirdropTaxCollector ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner()
        );
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(airdropDistribution_));
        console.log(
            "AirdropDistribution ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner()
        );
        proxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(distributionModule_));
        console.log(
            "DistributionModule ProxyAdmin", address(proxyAdmin), "owner:", proxyAdmin.owner()
        );
    }
}
