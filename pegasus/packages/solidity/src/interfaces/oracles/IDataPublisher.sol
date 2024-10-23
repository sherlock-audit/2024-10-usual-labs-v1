// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IDataPublisher {
    /// @notice Retrieves the latest round data for a specific token.
    /// @param token The address of the token for which the latest round data is being retrieved.
    /// @return roundId The round ID of the latest data.
    /// @return answer The answer (price) of the latest data.
    /// @return timestamp The timestamp of the latest data.
    function latestRoundData(address token)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 timestamp, uint8 decimals);

    /// @notice Retrieves round data for a specific token and round ID.
    /// @param token The address of the token for which the round data is being retrieved.
    /// @param roundId The specific round ID for which the round data is being retrieved.
    /// @return id The round ID of the data.
    /// @return answer The answer (price) of the data.
    /// @return timestamp The timestamp of the data.
    function getRoundData(address token, uint80 roundId)
        external
        view
        returns (uint80 id, int256 answer, uint256 timestamp, uint8 decimals);

    /// @notice  Function to publish a new price for a token
    /// @dev     Only the publisher whitelisted for the token can call this function
    /// @dev     Check if the token is block or not, if it is only Usual Tech publish data
    /// @param   token  address of the token
    /// @param   newData  new price for the token
    function publishData(address token, int256 newData) external;
}
