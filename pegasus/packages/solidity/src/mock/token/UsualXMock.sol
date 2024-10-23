// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IUsualX} from "src/interfaces/vaults/IUsualX.sol";

contract UsualXMock is IUsualX {
    bool public wasStartYieldDistributionCalled;
    uint256 public calledWithYieldAmount;
    uint256 public calledWithStartTime;
    uint256 public calledWithEndTime;

    function startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime)
        external
    {
        wasStartYieldDistributionCalled = true;
        calledWithYieldAmount = yieldAmount;
        calledWithStartTime = startTime;
        calledWithEndTime = endTime;
    }
}
