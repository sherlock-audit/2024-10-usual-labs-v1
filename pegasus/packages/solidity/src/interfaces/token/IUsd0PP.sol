// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IUsd0PP is IERC20Metadata {
    /// @notice Sets the early unlock period for the bond.
    /// @param bondEarlyUnlockStart The start time of the early unlock period.
    /// @param bondEarlyUnlockEnd The end time of the early unlock period.
    function setupEarlyUnlockPeriod(uint256 bondEarlyUnlockStart, uint256 bondEarlyUnlockEnd)
        external;

    /// @notice Calculates the number of seconds from beginning to end of the bond period.
    /// @return The number of seconds.
    function totalBondTimes() external view returns (uint256);

    /// @notice get the start time
    /// @dev Used to determine if the bond can be minted.
    /// @return The block timestamp marking when the bond starts.
    function getStartTime() external view returns (uint256);

    /// @notice get the end time
    /// @dev Used to determine if the bond can be unwrapped.
    /// @return The block timestamp marking when the bond ends.
    function getEndTime() external view returns (uint256);

    /// @notice Mints Usd0PP tokens representing bonds.
    /// @dev Transfers collateral USD0 tokens and mints Usd0PP bonds.
    /// @param amountUsd0 The amount of USD0 to mint bonds for.
    function mint(uint256 amountUsd0) external;

    /// @notice Mints Usd0PP tokens representing bonds with permit.
    /// @dev    Transfers collateral Usd0 tokens and mints Usd0PP bonds.
    /// @param  amountUsd0 The amount of Usd0 to mint bonds for.
    /// @param  deadline The deadline for the permit.
    /// @param  v The v value for the permit.
    /// @param  r The r value for the permit.
    /// @param  s The s value for the permit.
    function mintWithPermit(uint256 amountUsd0, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /// @notice Unwraps the bond after maturity, returning the collateral token.
    /// @dev Only the balance of the caller is unwrapped.
    /// @dev Burns bond tokens and transfers collateral back to the user.
    function unwrap() external;

    /**
     * @notice Triggers the PAR mechanism to maintain the peg between USD0 and USD0++ via Curvepool exchange.
     * @dev This function performs a series of actions: it checks for sufficient USD0 balances, exchanges USD0 for USD0++,
     *      and unwraps USD0++ back to USD0, which is then burned and any excess sent to the treasury.
     *      The function reverts if the PAR mechanism does not result in more USD0++ gained overall than USD0 is exchanged for.
     * @param parUsd0Amount The amount of USD0 to be exchanged for USD0++.
     * @param minimumPARMechanismGainedAmount The minimum additional amount of USD0++ expected to gain on top of the exchanged amount to account for slippage.
     */
    function triggerPARMechanismCurvepool(
        uint256 parUsd0Amount,
        uint256 minimumPARMechanismGainedAmount
    ) external;

    /**
     * @notice Allows users to early exit and unwrap a specified amount of USD0pp during the temporary exit period.
     * @dev    Users must have been allocated an early unlock amount by the admin before calling this function.
     * @dev    The early exit period is defined by `bondEarlyUnlockStart` and `bondEarlyUnlockEnd`.
     * @dev    This is a one-time option; it consumes the entire allocated amount, even if only partially used.
     * @dev    Emits `BondUnwrappedDuringEarlyUnlock` and `BondUnwrapped` events.
     * @dev    Reverts if the current time is not within the early exit period.
     * @dev    Reverts if `amountToUnwrap` exceeds the user's allocated early unlock amount.
     * @dev    Reverts if the user does not have sufficient bond balance.
     * @param amountToUnwrap The amount of bonds the user wants to unwrap.
     */
    function temporaryOneToOneExitUnwrap(uint256 amountToUnwrap) external;

    /**
     * @notice Allocates early unlock amounts to specified addresses, allowing them to early exit bonds during the temporary exit period.
     * @dev    Only callable by accounts with the `EARLY_BOND_UNLOCK_ROLE`.
     * @dev    Updates `bondEarlyUnlockAllowedAmount` for each address.
     * @dev    The early unlock amounts determine the maximum amount each user can unwrap early.
     * @dev    Reverts if the lengths of `addressesToAllocateTo` and `balancesToAllocate` do not match.
     * @dev    Potential upper bound on redemption may be applied in future updates.
     * @param addressesToAllocateTo An array of addresses to allocate early unlock amounts to.
     * @param balancesToAllocate An array of amounts representing the early unlock amounts for each address.
     */
    function allocateEarlyUnlockBalance(
        address[] calldata addressesToAllocateTo,
        uint256[] calldata balancesToAllocate
    ) external;

    /**
     * @notice Retrieves the disabled status of a user's temporary redemptions.
     * @dev Returns `true` if the user's temporary redemptions are disabled, `false` otherwise.
     * @param user The address of the user to check.
     * @return A boolean indicating whether the user's temporary redemptions are disabled.
     */
    function getBondEarlyUnlockDisabled(address user) external view returns (bool);

    /**
     * @notice Set the disabled status of a user's temporary redemptions. Only callable by the airdrop tax collector contract.
     * @param user The address of the user to disable temporary redemptions for.
     */
    function setBondEarlyUnlockDisabled(address user) external;

    /// @notice Updates the floor price
    /// @param newFloorPrice The new floor price value (18 decimal places)
    function updateFloorPrice(uint256 newFloorPrice) external;

    /// @notice Unlocks USD0++ to USD0 at the current floor price
    /// @param usd0ppAmount The amount of USD0++ to unlock
    function unlockUsd0ppFloorPrice(uint256 usd0ppAmount) external;

    /// @notice Gets the current floor price
    /// @return The current floor price
    function getFloorPrice() external view returns (uint256);
}
