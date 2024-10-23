// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAggregator} from "src/interfaces/oracles/IAggregator.sol";

contract MockAggregator is IAggregator {
    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint80 answeredInRound;
    }

    IERC20Metadata private _token;
    uint80 private _latestRoundId;
    mapping(uint80 => RoundData) private _roundsData;

    constructor(address token, int256 answer, uint80 answeredInRound) {
        _token = IERC20Metadata(token);
        _roundsData[0] = RoundData(answer, block.timestamp, answeredInRound);
    }

    function decimals() external view override returns (uint8) {
        return _token.decimals();
    }

    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function pushData(int256 answer, uint80 answeredInRound) external {
        uint80 roundId = _latestRoundId + 1;

        _roundsData[roundId] = RoundData(answer, block.timestamp, answeredInRound);
        _latestRoundId = roundId;
    }

    function getRoundData(uint80 roundId)
        public
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        RoundData memory data = _roundsData[roundId];
        uint256 updatedAt = _roundsData[roundId + 1].startedAt;

        if (updatedAt == 0) updatedAt = block.timestamp;

        return (roundId, data.answer, data.startedAt, updatedAt, data.answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return getRoundData(_latestRoundId);
    }
}
