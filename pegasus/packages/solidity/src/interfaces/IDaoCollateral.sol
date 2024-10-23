// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

struct Approval {
    uint256 deadline;
    uint8 v; // Changes at each new signature because of ERC20 Permit nonce
    bytes32 r;
    bytes32 s;
}

struct Intent {
    address recipient;
    address rwaToken;
    uint256 amountInTokenDecimals;
    uint256 deadline;
    bytes signature;
}

interface IDaoCollateral {
    /// @notice  swap method
    /// @dev     Function that enable you to swap your rwaToken for stablecoin
    /// @dev     Will exchange RWA (rwaToken) for USD0 (stableToken)
    /// @param   rwaToken  address of the token to swap
    /// @param   amount  amount of rwaToken to swap
    /// @param   minAmountOut minimum amount of stableToken to receive
    function swap(address rwaToken, uint256 amount, uint256 minAmountOut) external;

    /// @notice  swap method with permit
    /// @dev     Function that enable you to swap your rwaToken for stablecoin with permit
    /// @dev     Will exchange RWA (rwaToken) for USD0 (stableToken)
    /// @param   rwaToken  address of the token to swap
    /// @param   amount  amount of rwaToken to swap
    /// @param   deadline The deadline for the permit
    /// @param   v The v value for the permit
    /// @param   r The r value for the permit
    /// @param   s The s value for the permit
    function swapWithPermit(
        address rwaToken,
        uint256 amount,
        uint256 minAmountOut,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice  redeem method
    /// @dev     Function that enable you to redeem your stable token for rwaToken
    /// @dev     Will exchange USD0 (stableToken) for RWA (rwaToken)
    /// @param   rwaToken address of the token that will be sent to the you
    /// @param   amount  amount of stableToken to redeem
    /// @param   minAmountOut minimum amount of rwaToken to receive
    function redeem(address rwaToken, uint256 amount, uint256 minAmountOut) external;

    /// @notice Swap RWA for USDC through offers on the SwapperContract
    /// @dev Takes USYC, mints USD0 and provides it to the Swapper Contract directly
    /// Sends USD0 to the offer's creator and sends USDC to the recipient
    /// @dev the recipient Address to receive the USDC is msg.sender
    /// @param rwaToken Address of the RWA to swap for USDC
    /// @param amountInTokenDecimals Address of the RWA to swap for USDC
    /// @param orderIdsToTake orderIds to be taken
    /// @param approval ERC20Permit approval data and signature of data
    /// @param partialMatching flag to allow partial matching
    function swapRWAtoStbc(
        address rwaToken,
        uint256 amountInTokenDecimals,
        bool partialMatching,
        uint256[] calldata orderIdsToTake,
        Approval calldata approval
    ) external;

    /// @notice Swap RWA for USDC through offers on the SwapperContract
    /// @dev Takes USYC, mints USD0 and provides it to the Swapper Contract directly
    /// Sends USD0 to the offer's creator and sends USDC to the recipient
    /// @dev the recipient Address to receive the USDC is the offer's creator
    /// @param orderIdsToTake orderIds to be taken
    /// @param approval ERC20Permit approval data and signature of data
    /// @param intent Intent data and signature of data
    /// @param partialMatching flag to allow partial matching
    function swapRWAtoStbcIntent(
        uint256[] calldata orderIdsToTake,
        Approval calldata approval,
        Intent calldata intent,
        bool partialMatching
    ) external;

    // * Getter functions

    /// @notice get the redeem fee percentage
    /// @return the fee value
    function redeemFee() external view returns (uint256);

    /// @notice check if the CBR (Counter Bank Run) is activated
    /// @dev flag indicate the status of the CBR (see documentation for more details)
    /// @return the status of the CBR
    function isCBROn() external view returns (bool);

    /// @notice Returns the cbrCoef value.
    function cbrCoef() external view returns (uint256);

    /// @notice get the status of pause for the redeem function
    /// @return the status of the pause
    function isRedeemPaused() external view returns (bool);

    /// @notice get the status of pause for the swap function
    /// @return the status of the pause
    function isSwapPaused() external view returns (bool);

    // * Restricted functions

    /// @notice  redeem method for DAO
    /// @dev     Function that enables DAO to redeem stableToken for rwaToken
    /// @dev     Will exchange USD0 (stableToken) for RWA (rwaToken)
    /// @param   rwaToken address of the token that will be sent to the you
    /// @param   amount  amount of stableToken to redeem
    function redeemDao(address rwaToken, uint256 amount) external;

    /// @notice Invalidates the current nonce for the message sender
    /// @dev This function increments the nonce counter for the msg.sender and emits a NonceInvalidated event
    function invalidateNonce() external;

    /// @notice Invalidates all nonces up to a certain value for the message sender
    /// @dev This function increments the nonce counter for the msg.sender and emits a NonceInvalidated event
    function invalidateUpToNonce(uint256 newNonce) external;

    /// @notice Set the lower bound for the intent nonce to be considered consumed
    /// @dev An intent with an amount less than this threshold after a partial match will be invalidated by incrementing the nonce
    /// @dev emits a NonceThresholdSet event
    /// @param threshold The new threshold value
    function setNonceThreshold(uint256 threshold) external;

    /// @notice Check the current threshold for the intent nonce to be considered consumed
    /// @return The current threshold value
    function nonceThreshold() external view returns (uint256);
}
