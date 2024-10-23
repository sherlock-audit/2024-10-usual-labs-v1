// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IUsualX {
    function startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime)
        external;
}
