// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {DEFAULT_ADMIN_ROLE} from "src/constants.sol";

import {IAccessControlDefaultAdminRules} from
    "openzeppelin-contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {NullAddress, NotAuthorized} from "src/errors.sol";

contract RegistryAccessTest is Test {
    RegistryAccess public registry;
    bytes32 private constant _ADMIN = keccak256("ADMIN");
    bytes32 private constant _TREASURY_TRANSFER = keccak256("TREASURY_TRANSFER");
    bytes32 private constant _STBC_FACTORY = keccak256("STBC_FACTORY");
    bytes32 private constant _USLP_FACTORY = keccak256("USLP_FACTORY");
    bytes32 private constant _WRAP_FACTORY = keccak256("WRAP_FACTORY");
    bytes32 private constant _SUS_FACTORY = keccak256("SUS_FACTORY");
    bytes32 private constant _DAO_COLLATERAL = keccak256("DAO_COLLATERAL_CONTRACT");
    bytes32 private constant _SAVING_ACCOUNT = keccak256("SAVING_ACCOUNT");
    bytes32 private constant _WRAPPER = keccak256("WRAPPER");

    address public user = address(0x1);
    address public alice = address(0x2);
    address public admin = address(0x3);

    function setUp() public {
        registry = new RegistryAccess();
        _resetInitializerImplementation(address(registry));
        registry.initialize(address(admin));
    }

    function testInitialize() public {
        registry = new RegistryAccess();
        _resetInitializerImplementation(address(registry));
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        registry.initialize(address(0));
    }

    function testNotAdminCantAddRole() public {
        // user cant add role
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, DEFAULT_ADMIN_ROLE
            )
        );
        registry.grantRole(_ADMIN, user);
    }

    function testNotAdminCantSetAdminRole() public {
        // user cant add role
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        registry.setRoleAdmin(_ADMIN, DEFAULT_ADMIN_ROLE);
    }

    function testAdminCanSetAdminRole() public {
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector
            )
        );
        registry.setRoleAdmin(bytes32(DEFAULT_ADMIN_ROLE), bytes32(DEFAULT_ADMIN_ROLE));

        registry.setRoleAdmin(bytes32(_ADMIN), bytes32(DEFAULT_ADMIN_ROLE));
        registry.grantRole(bytes32(_ADMIN), alice);
        assertTrue(registry.hasRole(bytes32(_ADMIN), alice));
    }

    function testNotAdminCantRevokeRole() public {
        // user cant add role
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, DEFAULT_ADMIN_ROLE
            )
        );
        registry.revokeRole(_ADMIN, user);
    }

    function testAdminCantAddAnotherAdmin() public {
        // user cant add role
        vm.prank(admin);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector
            )
        );
        registry.grantRole(DEFAULT_ADMIN_ROLE, user);
    }

    function testTransferAdminRole() public {
        // admin can add role
        vm.prank(admin);
        registry.grantRole(_ADMIN, user);

        vm.prank(admin);
        registry.beginDefaultAdminTransfer(user);
        // 3 days and 1 sec later
        skip(3 days + 1);
        vm.prank(user);
        registry.acceptDefaultAdminTransfer();
        assertTrue(registry.owner() == user);
    }

    function testTransferAdminRoleShouldFailIfTooEarly() public {
        vm.prank(admin);
        registry.beginDefaultAdminTransfer(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector,
                259_201
            )
        );
        vm.prank(user);
        registry.acceptDefaultAdminTransfer();
        assertTrue(registry.owner() == admin);
    }

    function testAddTreasuryTransferRole() public {
        vm.prank(admin);
        registry.grantRole(_TREASURY_TRANSFER, user);
        assertTrue(registry.hasRole(_TREASURY_TRANSFER, user));
    }

    function testRemoveTreasuryTransferRole() public {
        vm.prank(admin);
        registry.grantRole(_TREASURY_TRANSFER, user);
        assertTrue(registry.hasRole(_TREASURY_TRANSFER, user));
        vm.prank(admin);
        registry.revokeRole(_TREASURY_TRANSFER, user);
        assertFalse(registry.hasRole(_TREASURY_TRANSFER, user));
    }

    function testAddDaoCollateralRole() public {
        vm.prank(admin);
        registry.grantRole(_DAO_COLLATERAL, user);
        assertTrue(registry.hasRole(_DAO_COLLATERAL, user));
    }

    function testRemoveDaoCollateralRole() public {
        vm.prank(admin);
        registry.grantRole(_DAO_COLLATERAL, user);
        assertTrue(registry.hasRole(_DAO_COLLATERAL, user));
        vm.prank(admin);
        registry.revokeRole(_DAO_COLLATERAL, user);
        assertFalse(registry.hasRole(_DAO_COLLATERAL, user));
    }

    function testAddSavingAccountRole() public {
        vm.prank(admin);
        registry.grantRole(_SAVING_ACCOUNT, user);
        assertTrue(registry.hasRole(_SAVING_ACCOUNT, user));
    }

    function testRemoveSavingAccountRole() public {
        vm.prank(admin);
        registry.grantRole(_SAVING_ACCOUNT, user);
        assertTrue(registry.hasRole(_SAVING_ACCOUNT, user));
        vm.prank(admin);
        registry.revokeRole(_SAVING_ACCOUNT, user);
        assertFalse(registry.hasRole(_SAVING_ACCOUNT, user));
    }

    function testAddWrapperRole() public {
        vm.prank(admin);
        registry.grantRole(_WRAPPER, user);
        assertTrue(registry.hasRole(_WRAPPER, user));
    }

    function testRemoveWrapperRole() public {
        vm.prank(admin);
        registry.grantRole(_WRAPPER, user);
        assertTrue(registry.hasRole(_WRAPPER, user));
        vm.prank(admin);
        registry.revokeRole(_WRAPPER, user);
        assertFalse(registry.hasRole(_WRAPPER, user));
    }

    function testAddUsLpFactoryRole() public {
        vm.prank(admin);
        registry.grantRole(_USLP_FACTORY, user);
        assertTrue(registry.hasRole(_USLP_FACTORY, user));
    }

    function testRemoveUsLpFactoryRole() public {
        vm.prank(admin);
        registry.grantRole(_USLP_FACTORY, user);
        assertTrue(registry.hasRole(_USLP_FACTORY, user));
        vm.prank(admin);
        registry.revokeRole(_USLP_FACTORY, user);
        assertFalse(registry.hasRole(_USLP_FACTORY, user));
    }

    function testAddWrapFactoryRole() public {
        vm.prank(admin);
        registry.grantRole(_WRAP_FACTORY, user);
        assertTrue(registry.hasRole(_WRAP_FACTORY, user));
    }

    function testRemoveWrapFactoryRole() public {
        vm.prank(admin);
        registry.grantRole(_WRAP_FACTORY, user);
        assertTrue(registry.hasRole(_WRAP_FACTORY, user));

        vm.prank(admin);

        registry.revokeRole(_WRAP_FACTORY, user);
        assertFalse(registry.hasRole(_WRAP_FACTORY, user));
    }

    function testAddSusFactoryRole() public {
        vm.prank(admin);
        registry.grantRole(_SUS_FACTORY, user);
        assertTrue(registry.hasRole(_SUS_FACTORY, user));
    }

    function testRemoveSusFactoryRole() public {
        vm.prank(admin);
        registry.grantRole(_SUS_FACTORY, user);
        assertTrue(registry.hasRole(_SUS_FACTORY, user));
        vm.prank(admin);
        registry.revokeRole(_SUS_FACTORY, user);
        assertFalse(registry.hasRole(_SUS_FACTORY, user));
    }

    function testGetOwner() public view {
        assertTrue(registry.owner() == admin);
    }

    function testRegistryInitializeRevertIfZeroAddress() public {
        _resetInitializerImplementation(address(registry));
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        registry.initialize(address(0));
    }

    function _resetInitializerImplementation(address implementation) internal {
        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 INITIALIZABLE_STORAGE =
            0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        // Set the storage slot to uninitialized
        vm.store(address(implementation), INITIALIZABLE_STORAGE, 0);
    }
}
