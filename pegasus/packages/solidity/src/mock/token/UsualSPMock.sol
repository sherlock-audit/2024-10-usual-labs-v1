// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUsualSP} from "src/interfaces/token/IUsualSP.sol";
import {IUsual} from "src/interfaces/token/IUsual.sol";

contract UsualSPMock is IUsualSP {
    using SafeERC20 for IUsual;

    IUsual public usual;

    bool public wasStartRewardDistributionCalled;
    uint256 public calledWithAmount;
    uint256 public calledWithStartTime;
    uint256 public calledWithEndTime;

    constructor(IUsual _usual) {
        usual = _usual;
    }

    // slither-disable-line no-empty-blocks
    // solhint-disable-next-line no-empty-blocks
    function claimOriginalAllocation() external {}

    // slither-disable-line no-empty-blocks
    // solhint-disable-next-line no-empty-blocks
    function stake(uint256 amount) external {}

    // slither-disable-line no-empty-blocks
    // solhint-disable-next-line no-empty-blocks
    function stakeWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {}

    // slither-disable-line no-empty-blocks
    // solhint-disable-next-line no-empty-blocks
    function unstake(uint256 amount) external {}

    function claimReward() external pure returns (uint256) {
        return 0;
    }

    // slither-disable-line no-empty-blocks
    // solhint-disable no-empty-blocks
    function allocate(
        address[] calldata recipients,
        uint256[] calldata allocations,
        uint256[] calldata cliffDurations
    ) external override {}
    // solhint-enable no-empty-blocks

    // slither-disable-line no-empty-blocks
    // solhint-disable-next-line no-empty-blocks
    function removeOriginalAllocation(address[] calldata recipients) external override {}

    // slither-disable-line no-empty-blocks
    // solhint-disable-next-line no-empty-blocks
    function stakeUsualS() external override {}

    function startRewardDistribution(uint256 amount, uint256 startTime, uint256 endTime)
        external
        override
    {
        wasStartRewardDistributionCalled = true;
        calledWithAmount = amount;
        calledWithStartTime = startTime;
        calledWithEndTime = endTime;

        usual.safeTransferFrom(msg.sender, address(this), amount);
    }
}
