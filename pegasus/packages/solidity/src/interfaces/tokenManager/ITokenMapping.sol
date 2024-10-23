// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface ITokenMapping {
    /// @notice Links an RWA token to USD0 token.
    /// @dev Only the admin can link the RWA token to USD0 token.
    /// @dev Ensures the RWA token is valid and not already linked to USD0 token.
    /// @param rwa The address of the RWA token.
    /// @return A boolean value indicating success.
    function addUsd0Rwa(address rwa) external returns (bool);

    /// @notice Retrieves the RWA token linked to USD0 token.
    /// @dev Returns the address of the Rwa token associated with USD0 token.
    /// @param rwaId The ID of the RWA token.
    /// @return The address of the associated Rwa token.
    function getUsd0RwaById(uint256 rwaId) external view returns (address);

    /// @notice Retrieves all RWA tokens linked to USD0 token.
    /// @dev Returns an array of addresses of all RWA tokens associated with USD0 token.
    /// @dev the maximum number of RWA tokens that can be associated with USD0 token is 10.
    /// @return An array of addresses of associated RWA tokens.
    function getAllUsd0Rwa() external view returns (address[] memory);

    /// @notice Retrieves the last RWA ID for USD0 token.
    /// @dev Returns the highest index used for the RWA tokens associated with the USD0 token.
    /// @return The last RWA ID used in the STBC to RWA mapping.
    function getLastUsd0RwaId() external view returns (uint256);

    /// @notice Checks if the RWA token is linked to USD0 token.
    /// @dev Returns a boolean value indicating if the RWA token is linked to USD0 token.
    /// @param rwa The address of the RWA token.
    /// @return A boolean value indicating if the RWA token is linked to USD0 token.
    function isUsd0Collateral(address rwa) external view returns (bool);
}
