// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IPayable {
    function unExistingFunc() external payable returns (bool);
}
