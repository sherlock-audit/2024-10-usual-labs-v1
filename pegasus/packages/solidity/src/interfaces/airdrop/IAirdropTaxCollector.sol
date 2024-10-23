// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IAirdropTaxCollector {
    /// @notice Returns whether the claimer has paid tax in USD0PP.
    /// @param claimer The claimer to check.
    /// @return Whether the claimer has paid tax.
    function hasPaidTax(address claimer) external view returns (bool);

    /// @notice Pays the tax amount for the sender.
    /// @dev This function can only be called when the contract is not paused.
    /// @dev This function can only be called during the claiming period.
    function payTaxAmount() external;

    /// @notice Calculates the tax amount for the given account.
    /// @param account The account to calculate the tax amount for.
    /// @return The tax amount.
    function calculateClaimTaxAmount(address account) external view returns (uint256);

    /// @notice Gets start and end date of the claiming period.
    /// @return startDate The start date of the claiming period.
    /// @return endDate The end date of the claiming period.
    function getClaimingPeriod() external view returns (uint256 startDate, uint256 endDate);

    /// @notice Gets the maximum chargeable tax that is reduced over time.
    /// @return The maximum chargeable tax.
    function getMaxChargeableTax() external view returns (uint256);

    /// @notice Sets the maximum chargeable tax.
    /// @param tax The new maximum chargeable tax.
    /// @dev This function can only be called by an airdrop operator.
    function setMaxChargeableTax(uint256 tax) external;

    /// @notice Sets the prelaunch USD0pp balances for potential tax payment calculations of the users
    /// @param addressesToAllocateTo The addresses to allocate to
    /// @param prelaunchBalances The balances to allocate to
    function setUsd0ppPrelaunchBalances(
        address[] calldata addressesToAllocateTo,
        uint256[] calldata prelaunchBalances
    ) external;
}
