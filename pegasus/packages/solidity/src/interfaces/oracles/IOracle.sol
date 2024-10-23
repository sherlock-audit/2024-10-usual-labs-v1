// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IOracle {
    /// @notice Get the latest price of a token from the underlying oracle.
    /// @dev    View function which fetches the latest available oracle price from a Chainlink-compatible feed.
    /// @dev    The result is scaled to 18 decimals.
    /// @param  token The address of the token.
    /// @return The price of the token in USD with 18 decimals.
    function getPrice(address token) external view returns (uint256);

    /// @notice Compute a quote for the specified token and amount.
    /// @dev    This function fetches the latest available price from a Chainlink-compatible feed for the token and computes the quote based on the given amount.
    /// @dev    The quote is computed by multiplying the amount of tokens by the token price.
    /// @dev    The result is returned with as many decimals as the input amount.
    /// @param  token  The address of the token to calculate the quote for.
    /// @param  amount The amount of tokens for which to compute the quote.
    /// @return The computed quote in USD with as many decimals as the input.
    function getQuote(address token, uint256 amount) external returns (uint256);

    /// @notice Set the maximum allowed depeg threshold for stablecoins.
    /// @dev    The provided value should be in basis points relative to 1 USD.
    /// @dev    Valid values are from 0 (exact 1:1 peg required) to 10_000 ($0.00-$2.00 allowed).
    /// @dev    getPrice will revert if the price falls outside of this range.
    /// @param  maxAuthorizedDepegPrice The new maximum allowed depeg threshold.
    function setMaxDepegThreshold(uint256 maxAuthorizedDepegPrice) external;
}
