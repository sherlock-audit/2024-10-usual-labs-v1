# Distribution 

## 1. High-Level Overview

This contract manages a **Distribution** process of the Usual token. The contract should be called daily to calculate how many new tokens are created, distributed to on-chain vaults (Usual+ and Usual*) and how many tokens are available to claim for the off-chain users with a valid merkle proof. 

The core features of this contract include:
- **Daily Distribution**: The contract should be called daily to calculate how many new tokens are created, distributed to On Chain vaults (Usual+ and Usual*) and how many tokens are available to claim for the off-chain users with a valid merkle proof.
- **Merkle Proof for Off-Chain Users**: Ensures that only eligible users, validated through Merkle proofs, can receive tokens from the distribution.
- **Challengeable Queue of Merkle Proofs**: The contract should have a queue of merkle proofs that can be challenged by a specific role (e.g. governance) to ensure that the off-chain distribution is fair and correct.
- **Access Control**: Each functionality should be controlled by a role with minimal required permissions.

## 2. Contract Summary

### 2.1 Inherited Contracts
- **Initializable**: For upgradeable contract initialization.
- **PausableUpgradeable**: Allows contract execution to be paused or unpaused by an authorized role.
- **ReentrancyGuardUpgradeable**: Provides protection against reentrancy attacks.
- **IDistributionModule**: Interface that defines all functions that can be called by anyone.
- **IDistributionAllocator**: Interface that defines the functions that can be only called by the `DISTRIBUTION_ALLOCATOR_ROLE`
- **IDistributionOperator**: Interface that defines the functions that can be only called by the `DISTRIBUTION_OPERATOR_ROLE`. Those functions are used to daily distribute the Usual tokens to on-chain and off-chain buckets.
- **IOffChainDistributionChallenger**: Interface that defines the functions that can be only called by the `OFF_CHAIN_DISTRIBUTION_CHALLENGER_ROLE`. Those functions are used to challenge the off-chain distribution in the queue.


## 3. Functionality Description

### 3.1 Public/External Functions
- **initialize**: Initializes the contract with the registry address and sets the initial `rate0` value
- **pause**: Admin function to pause the contract. Can be only called by `PAUSING_CONTRACTS_ROLE`
- **unpause**: Admin function to unpause the contract. Can be only called by `DEFAULT_ADMIN_ROLE`

### 3.2 IDistributionModule
- **getBucketsDistribution**: Returns the current buckets distribution percentages in basis points. Off-chain buckets are LBT, LYT, IYT, Bribe, Ecosystem, DAO, and Market Makers. On-Chain buckets are Usual+ and Usual*.
- **calculateUsualDist**: Helper view function that calculates a simulated Usual Distribution for the provided `ratet` and `p90Rate` values. It returns `st`, `rt` and `kappa` values that were used in the calculation.
- **calculateSt**: Helper view function that returns a calculated `st` value based on provided `supplyPpt` and `pt` values.
- **calculateRt**: Helper view function that returns a calculated `rt` value based on provided `ratet` and `p90Rate` values.
- **calculateMt**: Helper view function that returns a calculated `mt` value based on provided `st`, `rt` and `kappa` values.
- **getOffChainDistributionData**: Returns the currently approved off-chain distribution `timestamp` and `merkleRoot` values. That can be used to pre-validate the merkle proof before calling the `claimOffChainDistribution` function.
- **getOffChainDistributionQueue**: Returns the current off-chain distribution queue. The queue is a list of `timestamp`, `isChallenged` and `merkleRoot` values that are used to claim the off-chain distribution.
- **getOffChainDistributionMintCap**: Returns the current off-chain distribution mint cap value. This value is the maximum amount of tokens that can be minted by through the off-chain distribution. It is reduced with every successful claim.
- **approveUnchallengedOffChainDistribution**: Approves the latest unchallenged off-chain distribution from the queue that was in the queue for more than `USUAL_DISTRIBUTION_CHALLENGE_PERIOD`. All distributions that were in the queue for more than `USUAL_DISTRIBUTION_CHALLENGE_PERIOD` are removed from the queue. Even if anyone can call this function, usually it will be called by the `DISTRIBUTION_OPERATOR_ROLE`.
- **getOffChainTokensClaimed**: Returns the amount of the tokens claimed by the given `account` address in the off-chain distribution until now.
- **claimOffChainDistribution**: Allows to claim the Usual tokens from the latest approved off-chain distribution. Caller should provide a valid merkle proof for the provided `account` and `amount`. The `amount` is the total amount of tokens that were assigned for the given `account` address since the beginning of the distribution. The Usual tokens are minted when the proof is valid and the given `account` has any tokens to claim in the approved off-chain distribution. The given `account` will only receive the tokens that were not claimed by them before based on the value returned by the `getOffChainTokensClaimed` function. The mint cap should be reduced by the claimed amount. The `getOffChainTokensClaimed` should return increased value.

### 3.3 IDistributionAllocator
- **setBucketsDistribution**: Allows to set the new buckets distribution percentages in basis points. The sum of all values should be equal to `BASIS_POINT_BASE`. The function can be only called by the `DISTRIBUTION_ALLOCATOR_ROLE`. Off-chain buckets are LBT, LYT, IYT, Bribe, Ecosystem, DAO, and Market Makers. On-Chain buckets are Usual+ and Usual*.
- **setD**: Set `D` parameter used it the emissions calculation formula. The function can be only called by the `DISTRIBUTION_ALLOCATOR_ROLE`.
- **getD**: Returns the current `D` parameter value.
- **setM0**: Set `m0` parameter used it the emissions calculation formula. The function can be only called by the `DISTRIBUTION_ALLOCATOR_ROLE`.
- **getM0**: Returns the current `m0` parameter value.
- **setRateMin**: Set `rateMin` parameter used it the emissions calculation formula. The function can be only called by the `DISTRIBUTION_ALLOCATOR_ROLE`.
- **getRateMin**: Returns the current `rateMin` parameter value.
- **setGamma**: Set `gamma` parameter used it the emissions calculation formula. The function can be only called by the `DISTRIBUTION_ALLOCATOR_ROLE`.
- **getGamma**: Returns the current `gamma` parameter value.

### 3.4 IDistributionOperator
- **distributeUsualToBuckets**: Calculates the Usual emissions based on the current state of parameters and provided `ratet` and `p90Rate` values. For on-chain buckets (Usual+ and Usual*) the tokens are minted directly to the bucket and a vault specific distribution is started. For off-chain buckets (LBT, LYT, IYT, Bribe, Ecosystem, DAO, and Market Makers) mint is delayed until the off-chain distribution is approved and tokens are claimed. The function can be only called by the `DISTRIBUTION_OPERATOR_ROLE`.
- **queueOffChainDistribution**: Queues the off-chain distribution for the given `merkleRoot`. The function can be only called by the `DISTRIBUTION_OPERATOR_ROLE`. This function cannot be called more than once per 24 hours.
- **resetOffChainDistributionQueue**: Removes all off-chain distributions from the queue. This is an emergency functionality is queue ever gets to big to be pruned during a `approveUnchallengedOffChainDistribution` call. The function can be only called by the `DISTRIBUTION_OPERATOR_ROLE`.

### 3.5 IOffChainDistributionChallenger
- **challengeOffChainDistribution**: Challenges all off-chain distributions in the queue that are older than specified timestamp. They are marked as challenged and cannot be approved. The function can be only called by the `DISTRIBUTION_CHALLENGER_ROLE`. 
- **challengeAndProposeOffChainDistribution**: Challenges all off-chain distributions in the queue that are older than specified timestamp. They are marked as challenged and cannot be approved. The new off-chain distribution is proposed with the given `merkleRoot` and it still has to wait in the queue for `USUAL_DISTRIBUTION_CHALLENGE_PERIOD` before it can be approved. The function can be only called by the `DISTRIBUTION_CHALLENGER_ROLE`.

## 4. Functionality Breakdown

### Setting up calculations parameters
- `DISTRIBUTION_ALLOCATOR_ROLE` can change all the values that are used in the emissions calculations formula. There is no timelock for those changes.
- `DISTRIBUTION_ALLOCATOR_ROLE` can change the distribution buckets shares percentages. The sum of all values should be equal to 100% (in basis points). There is no timelock for those changes.

### Daily Emissions  
- `DISTRIBUTION_OPERATOR_ROLE` is required to call the `distributeUsualToBuckets` every 24 hours to calculate the new emissions and distribute them to the on-chain buckets and increase the off-chain buckets mint cap that can be claimed after successful approval of the off-chain distribution that is unchallenged and in the queue for more than `USUAL_DISTRIBUTION_CHALLENGE_PERIOD`.
- `DISTRIBUTION_OPERATOR_ROLE` is required to call the `queueOffChainDistribution` with a valid `merkleRoot` as soon as the off-chain distribution mint cap is increased.

### Off-Chain Distribution Queue, Approval and Challenges
- Once `DISTRIBUTOR_OPERATOR_ROLE` puts a new off-chain distribution in the queue, it has to wait for `USUAL_DISTRIBUTION_CHALLENGE_PERIOD` before it can be approved.
- Anyone can call the `approveUnchallengedOffChainDistribution` function to approve the latest unchallenged off-chain distribution from the queue that was in the queue for more than `USUAL_DISTRIBUTION_CHALLENGE_PERIOD`. This function will remove all distributions that were in the queue for more than `USUAL_DISTRIBUTION_CHALLENGE_PERIOD` which impacts the gas cost of the function. In normal circumstances, there should be only one distribution in the queue that is older than `USUAL_DISTRIBUTION_CHALLENGE_PERIOD` and has to be removed.
- `DISTRIBUTION_CHALLENGER_ROLE` can call the `challengeOffChainDistribution` function to challenge all off-chain distributions in the queue that are older than specified timestamp. They are marked as challenged and cannot be approved. In rare cases, a new off-chain distribution can be proposed and it is put in the queue.
- The queue should be treated as unordered.

### Merkle Tree Root
- The merkle tree root that are queued should be calculated off-chain and should include `account` and `amount` values for each user that is eligible for claiming the off-chain distribution. The `amount` value should be the total amount of tokens that were assigned for the given `account` address since the beginning of the distribution. The `amount` value for the given `account` should never decrease. The `account` address should be in the format `0x123...` and the `amount` should be in wei. 

### Merkle Proof Validation
All claims are validated against a Merkle tree using the `MerkleProof` library, ensuring that only eligible users can receive tokens.  Separate Merkle roots are set for the initial and vesting periods.

### Admin Control
Administrators have control over setting key contract parameters, such as the Merkle roots and penalty percentages, as well as pausing the contract in case of emergencies.

## 5. Constants
- **DEFAULT_ADMIN_ROLE**: Role required to unpause the contract
- **PAUSING_CONTRACTS_ROLE**: Role required to pause the contract
- **DISTRIBUTION_ALLOCATOR_ROLE**: Role required to set the distribution parameters and buckets distribution percentages
- **DISTRIBUTION_OPERATOR_ROLE**: Role required to distribute the Usual tokens to buckets and queue the off-chain distribution
- **DISTRIBUTION_CHALLENGER_ROLE**: Role required to challenge the off-chain distribution in the queue
- **USUAL_DISTRIBUTION_CHALLENGE_PERIOD**: The period in seconds that the off-chain distribution has to wait in the queue before it can be approved. It is 7 days by default.
- **CONTRACT_REGISTRY_ACCESS**:  This constant is used to define the address of the registry access contract.
- **CONTRACT_ORACLE**: This constant is used to define the address of the oracle contract.
- **CONTRACT_USD0**: This constant is used to define the address of the USD0 contract.
- **CONTRACT_USD0PP**: This constant is used to define the address of the USD0PP contract.
- **CONTRACT_USUAL**: This constant is used to define the address of the Usual contract.
- **CONTRACT_USUALSP**: This constant is used to define the address of the UsualSP contract.
- **CONTRACT_USUALX**: This constant is used to define the address of the UsualX contract.
- **CONTRACT_DAO_COLLATERAL**: This constant is used to define the address of the DAO collateral contract.
- **BASIS_POINT_BASE**: The base value for calculating percentages in basis points.
- **BPS_SCALAR**: The scalar value for calculating percentages in basis points.
- **SCALAR_ONE**: The scalar value for calculating percentages with 10^18 precision.

## 6. Safeguard Implementation

### Reentrancy Guard
All external function handling token mints and transfer are protected with `ReentrancyGuard` to prevent reentrancy attacks.

### Access Control
The contract uses `CheckAccessControl` to enforce role-based access control, ensuring only authorized addresses can perform actions that require specific permissions. Each role has minimal required permissions.

### Pausability
The contract is pausable by `PAUSING_CONTRACTS_ROLE`, enabling the ability to pause all operations in case of an emergency. The contract can be resumed only by `DEFAULT_ADMIN_ROLE`.

### Off-chain distribution queue and challenge mechanism
The off-chain distribution can be validated for `USUAL_DISTRIBUTION_CHALLENGE_PERIOD` before it can be approved. If an invalid distribution is proposed, it can be challenged by the `DISTRIBUTION_CHALLENGER_ROLE` making it impossible to be approved. 

If the queue ever gets too big, the `resetOffChainDistributionQueue` function can be called by the `DISTRIBUTION_OPERATOR_ROLE` to remove all off-chain distributions from the queue.

### Restrictions how often certain functions can be called
There is a 24 hours limit for the `calculateUsualDist` function to be called. To prevent unwanted emissions and distribution.

## 7. Possible Attack Vectors

### Reentrancy Attack 
If reentrancy protection wasn’t in place, malicious users could exploit the `claimOffChainDistribution` function to withdraw more tokens than intended. The contract uses `ReentrancyGuard` to mitigate this risk.

### Incorrect Merkle Proofs
An attacker could attempt to submit invalid Merkle proofs. The contract validates the Merkle proof during each claim to prevent unauthorized claims.

### Minting tokens before the new off-chain distribution is approved
An attacker could claim the tokens before the new off-chain distribution is approved. It would result in minting more tokens than intended. The contract assumes that `amount` assigned to the `account` in merkle tree is the maximum amount that can be claimed by the `account` and it should never decrease. The contract tracks how many tokens were claimed by the `account` and only uncloaked amount are minted.

### Denial of Service attack on the off-chain distribution queue
If a private key for the `DISTRIBUTION_OPERATOR_ROLE` is compromised, an attacker could fill the off-chain distribution queue with invalid distributions. It would prevent the valid distributions from being approved. The contract has a mechanism to wipe the queue in case of an emergency.

### Incorrect off-chain distribution queued
If a private key for the `DISTRIBUTION_OPERATOR_ROLE` is compromised, an attacker could queue an invalid off-chain distribution. The contract has a mechanism to challenge the invalid distribution and prevent it from being approved.

## 8. Potential Risks

-  **Operator outage**: If ever operator is not able to call the `distributeUsualToBuckets` function every 24 hours, the emissions will be halted. The off-chain distribution will not be increased and the on-chain buckets will not receive the new emissions.

-  **Centralization of Control**: Heavy reliance on admin roles for critical functionality.
    
-  **Upgradeability**: The contract is upgradeable, which introduces the risk of unintended behavior if future upgrades are not properly tested and implemented.

-  **Out of gas**: The contract may run out of gas during `approveUnchallengedOffChainDistribution`, `challengeAndProposeOffChainDistribution` and `challengeOffChainDistribution` functions if the number of distributions in the queue is too high.


## 9. Remediation Strategies
- Usage of a multi signature wallet to avoid reliance on only one admin. 
- Assigning roles to multiple addresses to avoid single point of failure.
- Upgrades are well tested before implementation.
