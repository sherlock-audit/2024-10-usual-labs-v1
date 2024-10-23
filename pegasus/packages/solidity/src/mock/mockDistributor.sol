// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IDistributor} from "src/interfaces/IDistributor.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract MockDistributor is IDistributor {
    using SafeERC20 for IERC20;

    address public immutable TREASURY;
    address public immutable BUCKETS;
    uint256 public returnedProfitBalance;
    uint256 public stolenAmount;

    constructor(address _buckets, address _treasury) {
        TREASURY = _treasury;
        BUCKETS = _buckets;
    }

    // solhint-disable-next-line no-unused-vars
    function distribute(bytes32, address token, uint256 profitBalance, address)
        external
        returns (uint256 profitDistributed)
    {
        uint256 profitToBeDistributed = profitBalance - returnedProfitBalance;
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(token).safeTransferFrom(BUCKETS, TREASURY, profitToBeDistributed + stolenAmount);
        return profitToBeDistributed;
    }

    // returnedProfitBalance is the profit to be distributed minus profit  that was actually distributed
    function setReturnedProfitBalance(uint256 _returnedProfitBalance) external {
        returnedProfitBalance = _returnedProfitBalance;
    }
    // set steal on

    function setStolenAmount(uint256 _stolenAmount) external {
        stolenAmount = _stolenAmount;
    }
}
