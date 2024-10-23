# Airdrop Module

## High-level Overview

The Airdrop Module is designed to distribute USUAL tokens to eligible users, categorized into two groups based on a snapshot of their holdings, specifically in terms of "pills" (off-chain data). Users are divided as follows:

-   **Top 80%**: Users holding the most pills.
-   **Bottom 20%**: Users holding fewer pills.

This categorization allows for different airdrop claiming options tailored to each group’s status, ensuring flexibility. There are four primary options available for airdrop claims:

1.  **Standard Claim (Bottom 20%)**: These users do not follow a vesting schedule and can claim the total airdrop amount immediately on December 12th.
2.  **Tax Paid Early Claim (Top 80% - Tax paid)**: These users, while originally part of a vesting schedule, can pay a tax to skip the vesting. Once the tax is paid, they can claim the total amount directly without waiting for monthly releases.
3.  **Vested Claim (Top 80% - No Tax Paid)**: These users must follow the vesting schedule, which allows monthly claims between January 12th and June 12th.
4.  **Rage Quit (Pre-defined Users)**: Certain pre-defined users have the option to exit the airdrop early by unwrapping USD0PP to USD0 at a 1:1 ratio. This action is considered "rage quitting," and they forfeit any further rewards from the airdrop.

## Contract Summary

The AirdropDistribution contract manages the core functionality of the airdrop, including claiming, penalty calculations, and merkle root verifications.

### AirdropDistribution.sol

#### Inherited Contracts
-  **Initializable (OZ):** Utilized to provide a safe and controlled way to initialize the contract's state variables. It ensures that the contract's initializer function can only be called once, preventing accidental or malicious reinitialization.

-  **ReentrancyGuardUpgradeable (OZ):** Employed to protect against reentrancy attacks. It provides a modifier that can be applied to functions to prevent them from being called recursively or from being called from other functions that are also protected by the same guard.

-  **PausableUpgradeable (OZ):** The `PausableUpgradeable` contract allows the contract administrators to pause certain functionalities in case of emergencies or necessary maintenance. It provides functions to pause and unpause specific operations within the contract to ensure user protection and contract stability.

- **IAirdropDistribution:** The interface of the contract.

#### Functions Description

#### Public/External Functions
- `claim`: Allows users to claim their airdrop allocation.
- `setMerkleRoot`: Sets the merkle root for initial claims (`AIRDROP_OPERATOR_ROLE` only).
- `setPenaltyPercentages`: Sets penalty percentages for accounts (`AIRDROP_PENALTY_OPERATOR_ROLE` only).
- `pause`: Pauses the contract (`PAUSING_CONTRACTS_ROLE` only).
- `unpause`: Unpauses the contract (`DEFAULT_ADMIN_ROLE` only).
- `voidAnyOutstandingAirdrop`: Voids the airdrop for users who choose to exit early (`CONTRACT_USD0PP` contract only).

#### Functionality Breakdown

1. Claiming:
- Users not in the top 80% can claim their full allocation on Dec 12th.
- Top 80% users who paid a tax skip vesting and claim the full amount (with existing penalties for next month deducted).
- Top 80% users who didn't paid a tax can claim monthly during the vestig duration.
- Users with rage quit are no longer eligible for airdrop and cannot claim any rewards.
2. Penalty System: Implements an admin-only penalty system based on off-chain criteria.

#### Constants
- `BASIS_POINT_BASE`: 10_000 (100%)
- `PAUSING_CONTRACTS_ROLE`: Role that can pause the contract.
- `AIRDROP_OPERATOR_ROLE`: Role that can set the merkle root.
- `AIRDROP_PENALTY_OPERATOR_ROLE`: Role that can set the penalty percentages.
- `AIRDROP_VESTING_DURATION_IN_MONTHS`: 6 months
- `END_OF_EARLY_UNLOCK_PERIOD`: Timestamp for the end of the early unlock period.
- `FIRST_AIRDROP_CLAIMING_DATE` to `SIXTH_AIRDROP_CLAIMING_DATE`: Specific timestamps for claiming periods, each months between Jan 12th 12:00 GMT to Jun 12th 12:00 GMT.

### AirdropTaxCollector

The AirdropTaxCollector contract manages the tax collection process for users who want to skip the vesting schedule.

#### Inherited Contracts
- **Initializable (OZ)**
- **PausableUpgradeable (OZ)**
- **ReentrancyGuardUpgradeable (OZ)**
- **IAirdropTaxCollector:** The interface of the contract.

#### Functions Description

#### Public/External Functions
- `payTaxAmount`: Allows users to pay the tax to skip vesting.
- `calculateClaimTaxAmount`: Calculates the tax amount for a given account.
- `setMaxChargeableTax`: Sets the maximum chargeable tax (`AIRDROP_OPERATOR_ROLE` only).
- `setUsd0ppPrelaunchBalances`: Sets the prelaunch Usd0PP balance for potential tax payment calculations of the user (`AIRDROP_OPERATOR_ROLE` only).
- `pause`: Pauses the contract (`PAUSING_CONTRACTS_ROLE` only).
- `unpause`: Unpauses the contract (`DEFAULT_ADMIN_ROLE` only).

#### Functionality Breakdown

1. Tax Calculation: Computes the tax amount based on the user's allocation and time remaining in the vesting period.
2. Tax Payment: Processes tax payments and marks users as eligible for full claiming.

#### Constants
- `BASIS_POINT_BASE`: 10000 (100%)
- `PAUSING_CONTRACTS_ROLE`: Role that can pause the contract.
- `AIRDROP_OPERATOR_ROLE`: Role that can set max chargeable tax and set Usd0PP prelaunch balances.
- `AIRDROP_CLAIMING_PERIOD_LENGTH`: Length of the airdrop vesting period, 182 days.

### Usd0PP (`temporaryOneToOneExitUnwrap` function)

The `temporaryOneToOneExitUnwrap` function in the Usd0PP contract provides a "ragequit" option for pre-defined users to exit the airdrop by unwrapping USD0PP to USD0 at a 1:1 ratio.

#### Function Description

#### Functionality Breakdown

1. Checks if the user is eligible for early unlock.
2. Verifies the unlock is within the specified timeframe.
3. Burns the USD0PP tokens and transfers an equal amount of USD0 to the user.
4. Voids the user's airdrop allocation.

## Safeguard Implementation

### Possible Attack Vectors
- Merkle proof manipulation
- Reentrancy attacks
- Unauthorized access to admin functions

### Potential Risks
- Incorrect merkle root setup
- Miscalculation of penalties or tax amounts
- Centralization of Control: Heavy reliance on admin roles for critical functionality.
- Upgradeability: The contract is upgradeable, which introduces the risk of unintended behavior if future upgrades are not properly tested and implemented.

### Potential Manipulations
- Attempting to claim multiple times
- Trying to claim without paying required tax
- Exploiting the penalty system

### Remediation Strategies
- Use of merkle proofs for efficient and secure verification of claim eligibility
- Implementation of ReentrancyGuard to prevent reentrancy attacks
- Role-based access control for admin functions
- Pausable functionality for emergency situations
- Thorough testing of smart contracts
- Use of SafeERC20 for token transfers
- Usage of a multisignature wallet to avoid reliance on only one admin.
- Upgrades are well tested before implementation.

By implementing these safeguards and following best practices in smart contract development, the Airdrop Module aims to provide a secure and fair distribution mechanism for token holders.