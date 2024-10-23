// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";

import {IUSYCAuthority, USYCRole} from "test/interfaces/IUSYCAuthority.sol";
import {IUSYC} from "test/interfaces/IUSYC.sol";
import {IUSDC} from "test/interfaces/IUSDC.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IUSDCMasterMinter} from "test/interfaces/IUSDCMasterMinter.sol";
import {BaseScript} from "scripts/deployment/Base.s.sol";

import {IDaoCollateral} from "src/interfaces/IDaoCollateral.sol";
import {CONTRACT_DAO_COLLATERAL, USD0_MINT} from "src/constants.sol";
import {USDC, USYC} from "src/mock/constants.sol";

contract TestScript is BaseScript {
    address public constant USDC_CONTROLLER = 0x79E0946e1C186E745f1352d7C21AB04700C99F71;
    address public constant WHALE = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8; // Binance 7 with 2M ETH

    IDaoCollateral public daoCollateral;

    function run() public virtual override {
        super.run();

        daoCollateral = IDaoCollateral(registryContract.getContract(CONTRACT_DAO_COLLATERAL));

        vm.label(address(daoCollateral), "daoCollateral");
    }

    function _dealETH(address _to) internal {
        if (_to.balance >= 1e18) return;

        vm.broadcast(WHALE);
        payable(_to).transfer(10e18);
    }

    function _dealUsd0(address _to, uint256 _amount) internal {
        _dealETH(usual);

        vm.startBroadcast(usual);
        if (!registryAccess.hasRole(USD0_MINT, usual)) {
            registryAccess.grantRole(USD0_MINT, usual);
        }

        USD0.mint(_to, _amount);
        vm.stopBroadcast();
    }

    function _dealUSDC(address _to, uint256 _amount) internal {
        IUSDCMasterMinter masterMinter = IUSDCMasterMinter(IUSDC(USDC).masterMinter());
        address worker = masterMinter.getWorker(USDC_CONTROLLER);

        _dealETH(USDC_CONTROLLER);

        vm.broadcast(USDC_CONTROLLER);
        masterMinter.incrementMinterAllowance(_amount);

        _dealETH(worker);

        vm.broadcast(worker);
        IUSDC(USDC).mint(_to, _amount);
    }

    function _dealUSYC(address _to, uint256 _amount) internal {
        _whitelistUSYC(_to);

        address authority = IUSYC(USYC).authority();
        address authOwner = IUSYCAuthority(authority).owner();

        _dealETH(authOwner);

        vm.startBroadcast(authOwner);
        IUSYCAuthority(authority).setUserRole(authOwner, USYCRole.System_FundAdmin, true);
        IUSYCAuthority(authority).setRoleCapability(
            USYCRole.Custodian_Decentralized, USYC, ERC20.transferFrom.selector, true
        );
        IUSYCAuthority(authority).setUserRole(
            address(daoCollateral), USYCRole.Custodian_Decentralized, true
        );

        IUSYC(USYC).setMinterAllowance(authOwner, _amount);
        IUSYC(USYC).mint(_to, _amount);
        vm.stopBroadcast();
    }

    function _whitelistUSYC(address _to) internal {
        address authority = IUSYC(USYC).authority();
        address authOwner = IUSYCAuthority(authority).owner();

        _dealETH(authOwner);

        vm.broadcast(authOwner);
        IUSYCAuthority(authority).setUserRole(_to, USYCRole.Investor_MFFeederDomestic, true);
    }
}
