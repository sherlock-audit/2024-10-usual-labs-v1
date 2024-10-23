// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IUSYCAuthority {
    function owner() external returns (address);
    function authority() external returns (address);
    function setUserRole(address user, USYCRole role, bool value) external;
    function setRoleCapability(USYCRole role, address target, bytes4 functionSig, bool enabled)
        external;
    function getRolesWithCapability(address target, bytes4 functionSig)
        external
        view
        returns (bytes32);
    function canCall(address user, address target, bytes4 functionSig)
        external
        view
        returns (bool);
    function setPublicCapability(address target, bytes4 functionSig, bool enabled) external;
}

enum USYCRole {
    Investor_MFFeederDomestic,
    Investor_MFFeederInternational,
    Investor_SDYFDomestic,
    Investor_SDYFInternational,
    Investor_LOFDomestic,
    Investor_LOFInternational,
    Investor_Reserve1,
    Investor_Reserve2,
    Investor_Reserve3,
    Investor_Reserve4,
    Investor_Reserve5,
    Custodian_Centralized,
    Custodian_Decentralized,
    System_FundAdmin,
    System_Token,
    System_Vault,
    System_Auction,
    System_Teller,
    System_Oracle,
    System_MarginEngine,
    LiquidityProvider_Options,
    LiquidityProvider_Spot,
    System_Entitlements,
    System_Messenger
}
