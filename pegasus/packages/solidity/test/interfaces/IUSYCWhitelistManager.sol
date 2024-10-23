// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";

interface IUSYCWhitelistManager is IAccessControl {
    function owner() external returns (address);
    // solhint-disable-next-line
    function CLIENT_DOMESTIC_FEEDER() external returns (bytes32);
}
