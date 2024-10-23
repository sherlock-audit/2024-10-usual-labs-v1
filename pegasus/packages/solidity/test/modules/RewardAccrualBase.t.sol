// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "test/setup.t.sol";
import {RewardAccrualBase} from "src/modules/RewardAccrualBase.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {MyERC20} from "src/mock/myERC20.sol";

contract MyRewardAccrualBase is Initializable, RewardAccrualBase {
    mapping(address => uint256) _balances;
    uint256 _totalStaked;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _rewardToken) public initializer {
        __RewardAccrualBase_init_unchained(_rewardToken);
    }

    function startRewardDistribution(uint256 amount, uint256 startTime, uint256 endTime) public {
        _startRewardDistribution(amount, startTime, endTime);
    }

    function getRewardToken() public view returns (address) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        return address($.rewardToken);
    }

    function getRewardAmount() public view returns (uint256) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        return $.rewardAmount;
    }

    function getPeriodStart() public view returns (uint256) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        return $.periodStart;
    }

    function getPeriodFinish() public view returns (uint256) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        return $.periodFinish;
    }

    function getRewardRate() public view returns (uint256) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        return $.rewardRate;
    }

    function getRewardPerTokenStored() public view returns (uint256) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        return $.rewardPerTokenStored;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function totalStaked() public view override returns (uint256) {
        return _totalStaked;
    }

    function stake(uint256 amount) external {
        _balances[msg.sender] += amount;
        _totalStaked += amount;
        _updateReward(msg.sender);
    }

    function claimReward() external returns (uint256) {
        return _claimRewards();
    }
}

contract RewardAccrualBaseTest is SetupTest {
    MyERC20 rewardToken = new MyERC20("Reward Token", "RT", uint8(18));
    MyRewardAccrualBase rewardAccrualBase;

    event RewardPeriodStarted(uint256 rewardAmount, uint256 startTime, uint256 endTime);
    event RewardRateChanged(uint256 rewardRate);

    function setUp() public override {
        super.setUp();
        rewardAccrualBase = new MyRewardAccrualBase();
        _resetInitializerImplementation(address(rewardAccrualBase));
        rewardAccrualBase.initialize(address(rewardToken));
    }

    function testConstructor() public view {
        assertEq(rewardAccrualBase.getRewardToken(), address(rewardToken));
        assertEq(rewardAccrualBase.getRewardAmount(), 0);
    }

    function testStartRewardPeriod(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 1, type(uint256).max);

        rewardToken.mint(alice, rewardAmount);
        vm.startPrank(alice);
        rewardToken.approve(address(rewardAccrualBase), rewardAmount);
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 1000;
        uint256 rewardRate = rewardAmount / (endTime - startTime);
        uint256 adjustedAmount = rewardRate * (endTime - startTime);
        vm.expectEmit(true, true, true, true);
        emit RewardPeriodStarted(adjustedAmount, startTime, endTime);
        vm.expectEmit(true, true, true, true);
        emit RewardRateChanged(rewardRate);

        rewardAccrualBase.startRewardDistribution(rewardAmount, startTime, endTime);
        vm.stopPrank();
        assertEq(rewardAccrualBase.getRewardAmount(), adjustedAmount);
        assertEq(rewardAccrualBase.getPeriodStart(), startTime);
        assertEq(rewardAccrualBase.getPeriodFinish(), endTime);
        assertEq(rewardAccrualBase.getRewardRate(), rewardRate);
    }

    function testClaimRewards(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 1e18, type(uint256).max);
        testStartRewardPeriod(rewardAmount);
        uint256 rewardPerSecond = rewardAmount / 1000;
        rewardAccrualBase.stake(rewardAmount);
        skip(1);
        uint256 reward = rewardAccrualBase.claimReward();
        assertApproxEqRel(reward, rewardPerSecond, 0.0001 ether);

        assertApproxEqRel(rewardAccrualBase.getRewardPerTokenStored(), 1e24 / 1000, 0.0001 ether);
        skip(1);
        reward = rewardAccrualBase.claimReward();
        assertApproxEqRel(reward, rewardPerSecond, 0.0001 ether);
        skip(998);
        reward = rewardAccrualBase.claimReward();
        assertApproxEqRel(reward, rewardPerSecond * 998, 0.0001 ether);
        assertApproxEqRel(rewardToken.balanceOf(address(this)), rewardAmount, 0.0001 ether);
    }

    function testClaimRewardsAfterEndShouldWork() public {
        uint256 rewardAmount = 1e18;
        testClaimRewards(rewardAmount);
        uint256 balBefore = rewardToken.balanceOf(address(this));
        skip(1000);
        rewardAccrualBase.claimReward();
        assertEq(rewardToken.balanceOf(address(this)), balBefore);
    }

    function testClaimRewardsTwiceInSameBlockShouldOptimizeGas(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 1e18, type(uint256).max);
        testStartRewardPeriod(rewardAmount);
        rewardAccrualBase.stake(rewardAmount);

        // Test multiple iterations
        for (uint256 i = 0; i < 5; i++) {
            skip(1); // Move to next block for each iteration

            uint256 gasUsed1 = gasleft();
            rewardAccrualBase.claimReward();
            uint256 gasUsed2 = gasleft();
            uint256 firstClaimGas = gasUsed1 - gasUsed2;

            rewardAccrualBase.claimReward();
            uint256 gasUsed3 = gasleft();
            uint256 secondClaimGas = gasUsed2 - gasUsed3;

            assertGt(
                firstClaimGas, secondClaimGas, "First claim should use more gas than second claim"
            );
        }
    }
}
