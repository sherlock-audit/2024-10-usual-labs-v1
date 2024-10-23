// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IHashnoteOracle {
    /// @notice get data about a round
    /// @return roundId is the round ID for which data was retrieved
    /// @return answer is the answer for the given round
    /// @return startedAt is always equal to updatedAt
    /// @return updatedAt is the timestamp when the round last was updated (i.e. answer was last computed)
    /// @return answeredInRound is always equal to roundId
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /// @notice get data about the latest round
    /// @return roundId is the round ID for which data was retrieved
    /// @return answer is the answer for the given round
    /// @return startedAt is always equal to updatedAt
    /// @return updatedAt is the timestamp when the round last was updated (i.e. answer was last computed)
    /// @return answeredInRound is always equal to roundId
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /// @notice get detail data about a round
    /// @return roundId is the round ID for which data was retrieved
    /// @return balance the total balance USD (2 decimals)
    /// @return interest the total interest accrued USD (2 decimals)
    /// @return totalSupply is the total supply of shares
    /// @return updatedAt is the timestamp when the round last was updated (i.e. answer was last computed)
    function getRoundDetails(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            uint256 balance,
            uint256 interest,
            uint256 totalSupply,
            uint256 updatedAt
        );

    /// @notice get balance and interest from the latest round
    /// @return roundId is the round ID for which data was retrieved
    /// @return balance the total balance USD (2 decimals)
    /// @return interest the total interest accrued USD (2 decimals)
    /// @return totalSupply is the total supply of shares
    /// @return updatedAt is the timestamp when the round last was updated (i.e. answer was last computed)
    function latestRoundDetails()
        external
        view
        returns (
            uint80 roundId,
            uint256 balance,
            uint256 interest,
            uint256 totalSupply,
            uint256 updatedAt
        );

    /// @notice reports the balance of funds
    /// @dev only callable by the owner, process SDYC fees if interest accrued
    /// @param _principal is the balance with 2 decimals of precision
    /// @param _interest is the balance with 2 decimals of precision
    /// @param _totalSupply is the total supply of shares
    /// @return roundId of the new round data
    function reportBalance(uint256 _principal, uint256 _interest, uint256 _totalSupply)
        external
        returns (uint80 roundId);
}
