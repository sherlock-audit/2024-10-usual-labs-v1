// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
// Import script utils
import {FinalConfigScript} from "scripts/deployment/FinalConfig.s.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {USDC, USYC} from "src/mock/constants.sol";
import {IUSYCAuthority, USYCRole} from "test/interfaces/IUSYCAuthority.sol";
import {IUSYC} from "test/interfaces/IUSYC.sol";

import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IUSDC} from "test/interfaces/IUSDC.sol";

import {DataPublisher} from "src/mock/dataPublisher.sol";
import {TokenMapping} from "src/TokenMapping.sol";
import {UsualOracle} from "src/oracles/UsualOracle.sol";

import {ClassicalOracle} from "src/oracles/ClassicalOracle.sol";
/// @author  Usual Tech Team
/// @title   Curve Deployment Script
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

contract BaseDeploymentTest is Test {
    FinalConfigScript public deploy;
    IRegistryContract registryContract;
    IRegistryAccess registryAccess;
    IUsd0 USD0;
    DataPublisher dataPublisher;
    TokenMapping tokenMapping;
    UsualOracle usualOracle;
    ClassicalOracle classicalOracle;
    ERC20 rwa = ERC20(USYC);
    address usual;
    address alice;
    address bob;
    address usualDAO;
    DaoCollateral daoCollateral;
    address treasury;
    // curve Stableswap-NG Factory contract is deployed to the Ethereum mainnet
    // more at https://docs.curve.fi/factory/stableswapNG/overview/
    address curvePool;
    address gauge;
    address constant STABLESWAP_NG_FACTORY = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;

    function setUp() public virtual {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        require(vm.activeFork() == forkId, "Fork not found");
        deploy = new FinalConfigScript();
        deploy.run();
        USD0 = deploy.USD0();

        vm.label(address(USD0), "USD0");
        vm.label(address(rwa), "USYC");
        registryContract = deploy.registryContract();
        registryAccess = deploy.registryAccess();
        usualOracle = deploy.usualOracle();
        classicalOracle = deploy.classicalOracle();
        vm.label(address(usualOracle), "usualOracle");
        curvePool = deploy.curvePool();
        dataPublisher = deploy.dataPublisher();
        tokenMapping = deploy.tokenMapping();
        treasury = deploy.treasury();
        vm.label(treasury, "treasury");
        usualDAO = deploy.usual();
        vm.label(address(usualDAO), "usualDAO");
        daoCollateral = deploy.daoCollateral();
        vm.label(address(daoCollateral), "daoCollateral");
        alice = deploy.alice();
        vm.label(alice, "alice");
        bob = deploy.bob();
        vm.label(bob, "bob");
        _setupHashnote();
    }

    function _dealUSDC(address to, uint256 amount) internal {
        vm.prank(IUSDC(USDC).masterMinter());
        IUSDC(USDC).configureMinter(address(this), amount);
        IUSDC(USDC).mint(address(to), amount);
    }

    function _setupHashnote() internal {
        address authority = IUSYC(USYC).authority();
        address authOwner = IUSYCAuthority(authority).owner();

        vm.startPrank(authOwner);
        // give authority System_FundAdmin role
        IUSYCAuthority(authority).setRoleCapability(
            USYCRole.System_FundAdmin, authority, IUSYCAuthority.setUserRole.selector, true
        );
        IUSYCAuthority(authority).setRoleCapability(
            USYCRole.System_FundAdmin, authority, IUSYCAuthority.setRoleCapability.selector, true
        );
        IUSYCAuthority(authority).setRoleCapability(
            USYCRole.System_FundAdmin, authority, IUSYCAuthority.setPublicCapability.selector, true
        );
        IUSYCAuthority(authority).setUserRole(authOwner, USYCRole.System_FundAdmin, true);
        IUSYCAuthority(authority).setRoleCapability(
            USYCRole.Custodian_Decentralized, USYC, ERC20.transferFrom.selector, true
        );
        IUSYCAuthority(authority).setPublicCapability(USYC, ERC20.transfer.selector, true);
        IUSYCAuthority(authority).setUserRole(
            address(daoCollateral), USYCRole.Custodian_Decentralized, true
        );

        bool canTransferFrom = IUSYCAuthority(authority).canCall(
            address(daoCollateral), USYC, ERC20.transferFrom.selector
        );
        assertTrue(canTransferFrom, "daoCollateral can't transfer from");
        bool canTransfer =
            IUSYCAuthority(authority).canCall(address(daoCollateral), USYC, ERC20.transfer.selector);
        assertTrue(canTransfer, "daoCollateral can't transfer");

        IUSYC(USYC).setMinterAllowance(authOwner, type(uint256).max);
        vm.stopPrank();
    }

    function _mintUSYC(uint256 amount) internal {
        address authority = IUSYC(USYC).authority();
        address authOwner = IUSYCAuthority(authority).owner();

        vm.startPrank(authOwner);
        IUSYC(USYC).mint(alice, amount);

        IUSYC(USYC).mint(bob, amount);
        vm.stopPrank();
    }

    function _whitelistPublisher() internal {
        vm.startPrank(usualDAO);
        if (!dataPublisher.isWhitelistPublisher(address(USD0), usualDAO)) {
            dataPublisher.addWhitelistPublisher(address(USD0), usualDAO);
        }
        require(dataPublisher.isWhitelistPublisher(address(USD0), usualDAO), "not whitelisted");
        vm.stopPrank();
    }
}
