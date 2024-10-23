# USD0

## High-Level Overview

This section provides an overview of the USD0 smart contract. The USD0 contract is designed to manage a USD0 ERC20 Token, implementing functionalities for minting, burning, and transfer operations while incorporating blacklist checks to restrict these operations to authorized addresses.

## Contract Summary

USD0 is an ERC-20 compliant token that integrates additional security and access control features to enhance its governance and usability. It inherits functionalities from ERC20PausableUpgradable and ERC20PermitUpgradeable to support permit-based approvals and pausability.

### Inherited Contracts

- **ERC20PausableUpgradeable**: Extends ERC20 to support pausability
- **ERC20PermitUpgradeable**: Extends ERC20 to support gasless transactions through signed approvals.

### ERC20PausableUpgradeable

Standard OpenZeppelin Implementation.

### ERC20PermitUpgradeable

Standard OpenZeppelin Implementation.

## Functionality Breakdown

### Key Functionalities

- **Minting**: Tokens can be minted to an address, subject to role checks.
- **Burning**: Tokens can be burned from an address, also subject to role checks.
- **Transfers**: Only not blacklisted addresses can send or receive tokens.

## Functions Description

### Public/External Functions

- **pause()**: Pauses all token transfer operations; callable only by the [PAUSING_CONTRACTS_ROLE](#constants).
- **unpause()**: Resumes all token transfer operations; callable only by the [DEFAULT_ADMIN_ROLE](#constants).
- **transfer(address to, uint256 amount)**: Transfers tokens to a non-blacklisted address.
- **transferFrom(address sender, address to, uint256 amount)**: Transfers tokens from one non-blacklisted address to another.
- **mint(address to, uint256 amount)**: Mints tokens to a non-blacklisted address if the caller has the [USD0_MINT](#constants) role.
- **burn(uint256 amount)** and **burnFrom(address account, uint256 amount)**: Burns tokens from an address, requiring the [USD0_BURN](#constants) role.

## Constants

- **CONTRACT_REGISTRY_ACCESS**: This constant is used to define the address of the registry access contract
- **DEFAULT_ADMIN_ROLE**: This constant is used to define the default admin role for the contract.
- **PAUSING_CONTRACTS_ROLE**: Role required to pause the contract.
- **BLACKLIST_ROLE**: Role required to blacklist an address.
- **USD0_MINT**: Role required to mint new tokens.
- **USD0_BURN**: Role required to burn tokens.

## Safeguards Implementation

- **Pausability**: Ensures that token transfers can be halted in case of emergency.
- **Role-Based Access Control**: Restricts sensitive actions to addresses with appropriate roles.
- **Blacklist Enforcement**: Ensures that only non-malicious addresses can participate in the token economy.

## Possible Attack Vectors

- **Reentrancy on minting and burning**: Although not directly vulnerable, external calls should be monitored.
- **Denial of Service by blocking blacklist management**: If the admin key is compromised.

## Potential Risks

- **Centralization of Control**: Heavy reliance on admin roles for critical functionality.
- **Smart Contract Bugs**: In complex interactions with inherited contracts and role management.

## Potential Manipulations

- **Blacklist Manipulation**: An admin with the [BLACKLIST_ROLE](#constants) could potentially manipulate the blacklist to exclude legitimate users or include malicious users.

## Conclusion

The USD0 contract is structured with security features for role management and blacklisting. However, centralization risks and potential administrative overreach should be mitigated through additional safeguards and decentralization of control where possible.

# USD0PP

## **High-Level Overview**

This smart contract is designed to manage bond-like financial instruments for the UsualDAO ecosystem. It provides functionality for minting, transferring, and unwrapping bonds. The contract is built to comply with ERC20 standards and includes security features to prevent common vulnerabilities.

## **Contract Summary**

The contract provides a robust bond management system. It inherits from ERC20PermitUpgradeable for token permit functionality, ReentrancyGuardUpgradeable for reentrancy attack protection, and IUsd0PP for bond-specific functionalities.

## **Inherited Contracts**

- **ERC20PausableUpgradeable**: Allows authorized addresses to pause all contract functionalities in case of an emergency.
- **ERC20PermitUpgradeable**: This contract provides token permit functionality, allowing users to permit other addresses to spend their tokens.
- **ReentrancyGuardUpgradeable**: This contract provides protection against reentrancy attacks, ensuring that functions cannot be called recursively in an unintended way.
- **IUsd0PP**: This is the interface contract that defines the bond-specific functionalities.

## **Functionality Breakdown**

The contract flow begins with the initialization of the bond parameters and related registry and token information. Bonds can be minted, transferred, and unwrapped. The contract also allows for emergency withdrawals of the underlying token.

## **Functions Description**

### **Public/External Functions (non-view / non-pure)**

- **initialize(address registryContract, string memory name_, string memory symbol_, uint256 startTime)**: This function initializes the contract with bond parameters and related registry and token information.
- **pause()**: Pauses all token transfer operations; callable only by the [PAUSING_CONTRACTS_ROLE](#constants).
- **unpause()**: Resumes all token transfer operations; also callable only by the [DEFAULT_ADMIN_ROLE](#constants).
- **mint(uint256 amountUsd0)**: This function mints new bonds. It takes one parameter, the amount of collateral token to be locked in the bond. 
- **mintWithPermit(uint256 amountUsd0, uint256 deadline, uint8 v, bytes32 r, bytes32 s)**: This function mints new bonds with a permit signature.
- **unwrap()**: This function unwraps the bonds and transfers the underlying collateral token to the user.
- **transfer(address recipient, uint256 amount)**: This function transfers bonds from the sender to the recipient.
- **transferFrom(address sender, address recipient, uint256 amount)**: This function transfers bonds from the sender to the recipient on behalf of the sender.
- **emergencyWithdraw(address safeAccount)**: This function allows for the emergency withdrawal of the underlying collateral token.

## **Constants **

- **DEFAULT_ADMIN_ROLE**: This constant is used to define the default admin role for the contract.
- **PAUSING_CONTRACTS_ROLE**: Role required to pause the contract.
- **CONTRACT_USD0**: This constant is used to define the address of the USD0 contract.
- **CONTRACT_REGISTRY_ACCESS**: This constant is used to define the address of the registry access contract.
- **BOND_DURATION_FOUR_YEAR**: This constant is used to define the duration of the bond period.

## **Safeguards Implementation**

- **ReentrancyGuardUpgradeable**: This contract provides protection against reentrancy attacks.
- **SafeERC20**: This library is used for safe token transfers, preventing loss of tokens due to incorrect contract behavior.
- **Check-Effects-Interactions Pattern**: This pattern is implemented to prevent reentrancy attacks. State changes are made before external calls, ensuring that the contract's state is updated before any external interaction.

## **Possible Attack Vectors**

- **Reentrancy on mint function**: There is a potential for attackers to re-enter the mint function before it completes, leading to unauthorized bond minting.
- **Unauthorized emergency withdrawal**: If the access control for the emergency withdrawal function is not properly implemented, unauthorized users could withdraw the underlying collateral token.

## **Potential Risks**

- **Risk of Loss**: If the emergency withdrawal function is called, the underlying collateral token could be lost if the recipient address is incorrect or malicious.
- **Bond Not Finished**: If the unwrap function is called before the bond period is finished, the function will revert.


# USUAL

## High-Level Overview

This section provides an overview of the USUAL smart contract. The USUAL contract is designed to manage the USUAL ERC20 Token, implementing functionalities for minting, burning, and transfer operations while incorporating blacklist checks to restrict these operations from sanctioned addresses.

## Contract Summary

USUAL is an ERC-20 compliant token that integrates additional security and access control features to enhance its governance and usability. It inherits functionalities from ERC20PausableUpgradable and ERC20PermitUpgradeable to support permit-based approvals and pausability.

### Inherited Contracts

- **ERC20PausableUpgradeable**: Extends ERC20 to support pausability
- **ERC20PermitUpgradeable**: Extends ERC20 to support gasless transactions through signed approvals.

### ERC20PausableUpgradeable

Standard OpenZeppelin Implementation.

### ERC20PermitUpgradeable

Standard OpenZeppelin Implementation.

## Functionality Breakdown

### Key Functionalities

- **Minting**: Tokens can be minted to an address, subject to role checks.
- **Burning**: Tokens can be burned from an address, also subject to role checks.
- **Transfers**: Only not sanctioned addresses can send or receive tokens.

## Functions Description

### Public/External Functions

- **pause()**: Pauses all token transfer operations; callable only by the [PAUSING_CONTRACTS_ROLE](#constants).
- **unpause()**: Resumes all token transfer operations; callable only by the [DEFAULT_ADMIN_ROLE](#constants).
- **transfer(address to, uint256 amount)**: Transfers tokens to a non-sanctioned address.
- **transferFrom(address sender, address to, uint256 amount)**: Transfers tokens from one non-sanctioned address to another.
- **mint(address to, uint256 amount)**: Mints tokens to a non-sanctioned address if the caller has the [USUAL_MINT](#constants) role.
- **burn(uint256 amount)** and **burnFrom(address account, uint256 amount)**: Burns tokens from an address, requiring the [USUAL_BURN](#constants) role.
- **blacklist(address account)** and **unBlacklist(address account)**: Those functions allows the admin to blacklist or remove from blacklist malicious users from using this token. Only callable by the [BLACKLIST_ROLE](#constants).

## Constants

- **CONTRACT_REGISTRY_ACCESS**: This constant is used to define the address of the registry access contract
- **DEFAULT_ADMIN_ROLE**: This constant is used to define the default admin role for the contract.
- **PAUSING_CONTRACTS_ROLE**: Role required to pause the contract.
- **BLACKLIST_ROLE**: Role required to blacklist an address.
- **USUAL_MINT**: Role required to mint new tokens.
- **USUAL_BURN**: Role required to burn tokens.

## Safeguards Implementation

- **Pausability**: Ensures that token transfers can be halted in case of emergency.
- **Role-Based Access Control**: Restricts sensitive actions to addresses with appropriate roles.
- **Blacklist Enforcement**: Ensures that only non-malicious addresses can participate in the token economy.

## Possible Attack Vectors

- **Reentrancy on minting and burning**: Although not directly vulnerable, external calls should be monitored.
- **Denial of Service by blocking blacklist management**: If the admin key is compromised.

## Potential Risks

- **Centralization of Control**: Heavy reliance on admin roles for critical functionality.
- **Smart Contract Bugs**: In complex interactions with inherited contracts and role management.

## Potential Manipulations

- **Blacklist Manipulation**: An admin could potentially manipulate the blacklist to exclude legitimate users.

## Conclusion

The USUAL contract is structured with security features for role management and blacklisting. However, centralization risks and potential administrative overreach should be mitigated through additional safeguards and decentralization of control where possible.



# USUALS

## High-Level Overview
This section provides an overview of the UsualS smart contract. The UsualS contract is designed to manage the USUALS ERC20 token, implementing essential functionalities for minting, burning, and transferring tokens, along with additional layers of control and security. The contract integrates role-based access control through a registry system, ensuring that only authorized entities can perform sensitive operations such as pausing the contract or blacklisting addresses

## Contract Summary
### Inherited Contracts
-  **ERC20PausableUpgradeable**: Extends ERC20 to support pausability
-  **ERC20PermitUpgradeable**: Extends ERC20 to support gasless transactions through signed approvals.

### ERC20PausableUpgradeable
Standard OpenZeppelin Implementation.

### ERC20PermitUpgradeable
Standard OpenZeppelin Implementation.

## Functionality Breakdown
### Key Functionalities
-  **Minting**: Tokens can be minted to an address, subject to role checks.
-  **Burning**: Tokens can be burned from an address, also subject to role checks.
-  **Transfers**: Tokens can be sent or receive. Will revert if blacklisted.

## Functions Description
### Public/External Functions
-  **pause()**: Pauses all token transfer operations; callable only by the [PAUSING_CONTRACTS_ROLE](#constants).
-  **unpause()**: Resumes all token transfer operations; callable only by the [DEFAULT_ADMIN_ROLE](#constants).
-  **transfer(address to, uint256 amount)**: Transfers tokens to a non-blacklisted address.
-  **transferFrom(address sender, address to, uint256 amount)**: Transfers tokens from one non-blacklisted address to another.
-  **burn(uint256 amount)** and **burnFrom(address account, uint256 amount)**: Burns tokens from an address, requiring the [USUALS_BURN](#constants) role.
-  **blacklist(address account)** and **unBlacklist(address account)**: Those functions allows the admin to blacklist or remove from blacklist malicious users from using this token. Only callable by the [BLACKLIST_ROLE](#constants).
-  **stakeAll()** : Sends the total supply of **USUALS** to the staking contract. Only callable by the `USUALSP` contract.
-  **isBlacklisted()**: Returns true if the account is blacklisted.
  
## Constants
-  **CONTRACT_REGISTRY_ACCESS**: Registry access contract address.
-  **DEFAULT_ADMIN_ROLE**: Default admin role. Can unpause the contract.
-  **PAUSING_CONTRACTS_ROLE**: Role required to pause the contract.
-  **BLACKLIST_ROLE**: Role required to blacklist and remove from blacklist an address.
-  **USUALS_BURN**: Role required to burn tokens.

## Safeguards Implementation
-  **Pausability**: Ensures that token transfers can be halted in case of emergency.
-  **Role-Based Access Control**: Restricts sensitive actions to addresses with appropriate roles.
-  **Blacklist Enforcement**: Ensures that unauthorized addresses can't participate in the token economy.

## Possible Attack Vectors
-  **Denial of Service by blocking blacklist management**: If the admin key is compromised.
-  **Denial of Service by pausing contract**: If the admin key is compromised.
-  **Frontrunning of the `stakeAll` function**: If the USUALSP role is compromised.

## Potential Risks
-  **Centralization of Control**: Heavy reliance on admin roles for critical functionality.

## Potential Manipulations
-  **Blacklist Manipulation**: An admin could potentially manipulate the blacklist to exclude legitimate users or includes malicious users.

## Conclusion
The **UsualS** contract is structured with security features for role management and blacklisting. However, centralization risks and potential administrative overreach should be mitigated through additional safeguards and decentralization of control where possible.


# USUALSP (USUALS Allocation)

## High-Level Overview
The **UsualSP** contract is a smart contract designed for managing the vesting and staking of **USUALS** token allocations. It allows insiders to vest and claim their **USUALS** allocations over a pre-defined vesting period and provides users (both insiders and outsiders) the ability to stake **USUALS** tokens to receive yield in the form of liquid allocations and rewards in **USUAL** tokens. Insiders can claim their vested **USUALS** allocations after a user-specific cliff period, and these tokens are distributed in monthly increments.

## Contract Summary
### Inherited Contracts

- **RewardAccrualBase**: Base contract that handles the reward accrual mechanism for staked tokens.
- **PausableUpgradeable**: Allows contract functionality to be paused by authorized accounts (OZ implementation).
- **ReentrancyGuardUpgradeable**: Prevents reentrant attacks on sensitive functions (OZ implementation).
- **IUsualSP**: Interface defining the required methods for the **UsualSP** contract.
  
## Functionality Breakdown
### Key Functionalities

- **Vesting**: Insiders receive an initial **USUALS allocation** that is vested over a defined period. This allocation is released gradually, with insiders able to claim it monthly after the cliff period has passed.
- **Claiming USUALS Allocations**: Insiders can claim their vested **USUALS** after the cliff period is over. The claimable amount is calculated based on the duration passed since the vesting started.
- **Staking**: Users (including insiders) can stake their **USUALS** tokens to receive liquid allocations and rewards in **USUAL** tokens. These rewards accrue over time and can be claimed.
- **Reward Accrual**: Users who stake **USUALS** tokens are eligible for rewards in **USUAL** tokens based on the staking duration and amount.
- **Pause and Unpause**: Authorized roles have the ability to pause and unpause the contract to safeguard against attacks or during upgrades.

## Functions Description
### Public/External Functions

- **initialize**: Initializes the contract by setting the registry contract, vesting start date, and duration.
- **claimOriginalAllocation**: Allows insiders to claim their vested **USUALS** allocations.
- **stake**: Users can stake their **USUALS** tokens to receive liquid allocations.
- **stakeWithPermit**: Users can stake their **USUALS** tokens to receive liquid allocations with a permit signature.
- **unstake**: Users can withdraw a portion of their staked **USUALS** tokens.
- **claimReward**: Users can claim their accrued rewards in **USUAL** tokens based on their allocation.
- **pause**: Pauses all token transfer operations; callable only by the [PAUSING_CONTRACTS_ROLE](#constants).
- **unpause**: Resumes all token transfer operations; also callable only by the [DEFAULT_ADMIN_ROLE](#constants).
- **allocate**: Function to allocate original **USUALS** allocations and set the cliff durations for insiders. Only callable by the [USUALSP_OPERATOR_ROLE](#constants).
- **stakeUsualS**: Sends the total supply of **USUALS** to the staking contract. Only callable by the USUALS contract.
- **removeOriginalAllocation**: Function to remove the original allocation and claimed amounts for a list of recipients. Only callable by the [USUALSP_OPERATOR_ROLE](#constants).
- **startRewardDistribution**: Initiates the reward distribution process. Only callable by the Distribution Module contract.

## Constants and Roles

- **CONTRACT_REGISTRY_ACCESS**: Registry access contract address.
- **DEFAULT_ADMIN_ROLE**: Default admin role. Can unpause the contract.
- **PAUSING_CONTRACTS_ROLE**: Role required to pause the contract.
- **USUALSP_OPERATOR_ROLE**: Role required for allocation management and staking operations.
- **CONTRACT_USUALS**: The address of the **USUALS** token contract.
- **CONTRACT_USUAL**: The address of the **USUAL** token contract.
- **CONTRACT_DISTRIBUTION_MODULE**: The address of the Distribution Module contract.
- **ONE_MONTH**: Represents the duration of one month in seconds, used to calculate the vesting schedule.
- **NUMBER_OF_MONTHS_IN_THREE_YEARS**: Used to calculate the total vesting duration over three years.

## Safeguards Implementation

- **Pausability**: Ensures that contract operations can be halted in case of emergency.
- **Role-Based Access Control**: Restricts sensitive actions to addresses with appropriate roles.
- **ReentrancyGuard**: All external-facing functions that handle transfers or state changes are protected from reentrancy attacks.

## Potential Risks

- **Centralization of Control**: Reliance on specific roles for critical functionality.
- **Upgradeability**: The contract is upgradeable, which introduces the risk of unintended behavior if future upgrades are not properly tested and implemented.

## Conclusion

The **UsualSP** contract provides a robust mechanism for vesting and staking **USUALS** allocations, ensuring that insiders receive their allocations gradually over time, while users can earn rewards through staking. With safeguards like pausing, reentrancy protection, and role-based access control, the contract minimizes attack vectors and ensures secure token management. However, careful consideration must be given to smart contract upgrades and the management of privileged roles.