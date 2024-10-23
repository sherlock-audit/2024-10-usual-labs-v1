// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IAirdropDistribution {
    /// @notice Claims the airdrop for the given account.
    /// @param account The account to claim for.
    /// @param isTop80 Whether the account is in the top 80% of the distribution.
    /// @param amount Total amount claimable by the user.
    /// @param proof Merkle proof.
    function claim(address account, bool isTop80, uint256 amount, bytes32[] calldata proof)
        external;

    /// @notice If a user early unlocks any USD0PP tokens via the temporaryOneToOneExitUnwrap function,
    /// @notice the USD0PP contract disables any claiming of outstanding tokens on the airdrop module
    /// @dev    Can only be called by the CONTRACT_USD0PP role.
    /// @param  addressToVoidAirdrop The address to disable the airdrop for.
    function voidAnyOutstandingAirdrop(address addressToVoidAirdrop) external;

    /// @notice Returns the status of ragequitting from airdrop for the given account.
    /// @param account Address of the account.
    /// @return The ragequit status.
    function getRagequitStatus(address account) external returns (bool);
}
