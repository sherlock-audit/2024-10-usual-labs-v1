// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface ISwapperEngine {
    /// @notice Allows a user to deposit USDC tokens and create a new order.
    /// @dev This function transfers the specified amount of USDC tokens from the caller to the contract
    ///      and creates a new order with the deposited amount and the caller as the requester.
    /// @param amountToDeposit The amount of USDC tokens to deposit.
    function depositUSDC(uint256 amountToDeposit) external;

    /// @notice Allows a user to deposit USDC tokens with permit and create a new order.
    /// @dev This function transfers the specified amount of USDC tokens from the caller to the contract
    ///      and creates a new order with the deposited amount and the caller as the requester.
    /// @param amountToDeposit The amount of USDC tokens to deposit.
    /// @param deadline The deadline for the permit
    /// @param v The v value for the permit
    /// @param r The r value for the permit
    /// @param s The s value for the permit
    function depositUSDCWithPermit(
        uint256 amountToDeposit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Allows the requester of an order to withdraw their deposited USDC tokens and cancel the order.
    /// @dev This function deactivates the specified order, sets its token amount to zero, and transfers
    ///      the deposited USDC tokens back to the requester.
    /// @param orderToCancel The ID of the order to cancel and withdraw from.
    function withdrawUSDC(uint256 orderToCancel) external;

    /// @notice Allows a user to provide USD0 tokens and receive USDC tokens by matching against existing orders.
    /// @dev This function allows users to specify an amount of USDC tokens they want, calculating the corresponding
    ///      USD0 tokens they need and exchanging it against active orders.
    /// @param recipient The address to receive the USDC tokens.
    /// @param amountUsdcToTakeInNativeDecimals The amount of USDC tokens to take, in the token's native decimal representation.
    /// @param orderIdsToTake An array of order IDs to match against.
    /// @param partialMatchingAllowed A flag indicating whether partial matching is allowed.
    /// @return The unmatched amount of USDC tokens.
    function provideUsd0ReceiveUSDC(
        address recipient,
        uint256 amountUsdcToTakeInNativeDecimals,
        uint256[] memory orderIdsToTake,
        bool partialMatchingAllowed
    ) external returns (uint256);

    /// @notice provideUsd0ReceiveUSDC method with permit
    /// @dev This function allows users to to swap their USD0 for USDC with permit
    /// @param recipient The address to receive the USDC tokens.
    /// @param amountUsdcToTakeInNativeDecimals The amount of USDC tokens to take, in the token's native decimal representation.
    /// @param orderIdsToTake An array of order IDs to match against.
    /// @param partialMatchingAllowed A flag indicating whether partial matching is allowed.
    /// @param deadline The deadline for the permit
    /// @param usd0ToPermit The amount of USD0 tokens to permit, must be greater than the equivalent amount of USDC tokens to take.
    /// @param v The v value for the permit
    /// @param r The r value for the permit
    /// @param s The s value for the permit
    /// @return The unmatched amount of USDC tokens.
    function provideUsd0ReceiveUSDCWithPermit(
        address recipient,
        uint256 amountUsdcToTakeInNativeDecimals,
        uint256[] memory orderIdsToTake,
        bool partialMatchingAllowed,
        uint256 usd0ToPermit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256);

    /// @notice Allows users to specify an amount of USD0 tokens to swap and receive USDC tokens by matching against existing orders.
    /// @dev This function handles the precision differences between USD0 and USDC taking dust into account
    ///      to ensure accurate conversion. It returns the unmatched USD0 amount in WAD format, including the dust.
    /// @param recipient The address to receive the USDC tokens.
    /// @param amountUsd0ToProvideInWad The amount of USD0 to provide in WAD format.
    /// @param orderIdsToTake An array of order IDs to match against.
    /// @param partialMatchingAllowed A flag indicating whether partial matching is allowed.
    /// @return The unmatched amount of Usd0 tokens in WAD format.
    function swapUsd0(
        address recipient,
        uint256 amountUsd0ToProvideInWad,
        uint256[] memory orderIdsToTake,
        bool partialMatchingAllowed
    ) external returns (uint256);

    /// @notice Get the next order ID.
    /// @dev This function returns the next order ID, which is the total number of orders created.
    /// @return The next order ID.
    function getNextOrderId() external view returns (uint256);
}
