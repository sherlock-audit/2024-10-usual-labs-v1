
# Usual Labs V1 contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
As part of the V1 competition, we are integrating only our own new token contracts that are also part of this competition.
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
DistributionModule.sol::queueOffChainUsualDistribution(bytes32 _merkleRoot) 
- the merkle trees claimable accumulated balances can only add up to in total to the offChainDistributionMintCap

DistributionModule.sol::distributeUsualToBuckets(uint256 ratet, uint256 p90Rate)
- ratet & p90Rate = between 1 and 10_000




___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No
___

### Q: For permissioned functions, please list all checks and requirements that will be made before calling the function.
N/A
___

### Q: Is the codebase expected to comply with any EIPs? Can there be/are there any deviations from the specification?
N/A
___

### Q: Are there any off-chain mechanisms for the protocol (keeper bots, arbitrage bots, etc.)? We assume they won't misbehave, delay, or go offline unless specified otherwise.
Yes, the DISTRIBUTION_OPERATOR_ROLE. 

The operator  will, on a recurring schedule(DISTRIBUTION_FREQUENCY_SCALAR minimum), trigger DistributionModule.sol::distributeUsualToBuckets(uint256 ratet, uint256 p90Rate), with the appropiate values.

The operator will also, on a recurring schedule(DISTRIBUTION_FREQUENCY_SCALAR)  call DistributionModule.sol::queueOffChainUsualDistribution(bytes32 _merkleRoot) to post a merkle tree to distribute the offchain allocations assigned by distributeUsualToBuckets above.
___

### Q: If the codebase is to be deployed on an L2, what should be the behavior of the protocol in case of sequencer issues (if applicable)? Should Sherlock assume that the Sequencer won't misbehave, including going offline?
N/A
___

### Q: What properties/invariants do you want to hold even if breaking them has a low/unknown impact?
N/A
___

### Q: Please discuss any design choices you made.
We are choosing to not be able to withdraw fees on UsualX for the time being.  At the moment, the fees wouldn't be withdrawable. `This is a deliberate choice to be implemented in a later contract upgrade, when the protocol governance decides on how the unstaking fees should be dealt with (i.e. burned, redistributed).

The distribution to all the buckets, even if a bucket at that time wouldn't have any recipients eligible, is intended. An applicable scenario would be if nobody  is staking in UsualX or UsualSP, therefore any rewards accrued would be essentially unredeemable. This is intentional until the protocol decides on how to proceed with unclaimed rewards later on.

Rounding does not necessarily need to be in the favor of the protocol, unless it would lead to breaking behaviour ( i.e. underflows)

Bucket Distribution Changes being applicable retroactively to distributions is intended.


___

### Q: Please list any known issues and explicitly state the acceptable risks for each known issue.
Any risk regarding the DaoCollateral & USD0 contract, that are not related to the role management changes,  is acceptable unless its High Severity.




___

### Q: We will report issues where the core protocol functionality is inaccessible for at least 7 days. Would you like to override this value?
We would like to override this value to 14 days. The reason for this is that as part of our challenge-mechanic on the offchain distribution merkle trees challengers can, via their privileged role, render an offchain distribution inaccessible for up to 14 days. This requires a malicious privileged actor challenging legitimate distributions at the maximum possible impact, which is 14 days.
___

### Q: Please provide links to previous audits (if any).
https://usual.gitbook.io/usual-technical-documentation/Aw3jUdIChYIRnEPcqUqK/security-and-audits/audits
___

### Q: Please list any relevant protocol resources.
Our tech gitbook, which is currently work in progress:

https://usual.gitbook.io/usual-technical-documentation/Aw3jUdIChYIRnEPcqUqK/

Overview Diagrams for this competition:

Miro board link: https://miro.com/app/board/uXjVLNEXyS0=/ Password: sherlock
___

### Q: Additional audit information.
The main focus on this audit is:

1. The DistributionModule, which is responsible for distributing $USUAL to the distribution buckets.

These consist of our UsualX Vault, UsualSP Staking & the distribution system based on an offchain merkle tree  done inside the distribution module contract itself. This also includes the new Tokens $USUAL & $USUALS.

2. The Airdrop Contracts & the USD0PP contracts interactions with the airdrop.

The diffs to our previous audited version can be found here ( diffs appear larger than they are because the contracts have been cleaned up formatting wise, i.e. sorting functions):

https://github.com/usual-dao/pegasus/pull/1544/files
___



# Audit scope


[pegasus @ ea088fa77aac69e91ea6a191d5c11c912cd34446](https://github.com/usual-dao/pegasus/tree/ea088fa77aac69e91ea6a191d5c11c912cd34446)
- [pegasus/packages/solidity/src/airdrop/AirdropDistribution.sol](pegasus/packages/solidity/src/airdrop/AirdropDistribution.sol)
- [pegasus/packages/solidity/src/airdrop/AirdropTaxCollector.sol](pegasus/packages/solidity/src/airdrop/AirdropTaxCollector.sol)
- [pegasus/packages/solidity/src/constants.sol](pegasus/packages/solidity/src/constants.sol)
- [pegasus/packages/solidity/src/daoCollateral/DaoCollateral.sol](pegasus/packages/solidity/src/daoCollateral/DaoCollateral.sol)
- [pegasus/packages/solidity/src/distribution/DistributionModule.sol](pegasus/packages/solidity/src/distribution/DistributionModule.sol)
- [pegasus/packages/solidity/src/errors.sol](pegasus/packages/solidity/src/errors.sol)
- [pegasus/packages/solidity/src/modules/RewardAccrualBase.sol](pegasus/packages/solidity/src/modules/RewardAccrualBase.sol)
- [pegasus/packages/solidity/src/token/Usd0.sol](pegasus/packages/solidity/src/token/Usd0.sol)
- [pegasus/packages/solidity/src/token/Usd0PP.sol](pegasus/packages/solidity/src/token/Usd0PP.sol)
- [pegasus/packages/solidity/src/token/Usual.sol](pegasus/packages/solidity/src/token/Usual.sol)
- [pegasus/packages/solidity/src/token/UsualS.sol](pegasus/packages/solidity/src/token/UsualS.sol)
- [pegasus/packages/solidity/src/token/UsualSP.sol](pegasus/packages/solidity/src/token/UsualSP.sol)
- [pegasus/packages/solidity/src/utils/CheckAccessControl.sol](pegasus/packages/solidity/src/utils/CheckAccessControl.sol)
- [pegasus/packages/solidity/src/utils/NoncesUpgradeable.sol](pegasus/packages/solidity/src/utils/NoncesUpgradeable.sol)
- [pegasus/packages/solidity/src/utils/normalize.sol](pegasus/packages/solidity/src/utils/normalize.sol)
- [pegasus/packages/solidity/src/vaults/UsualX.sol](pegasus/packages/solidity/src/vaults/UsualX.sol)
- [pegasus/packages/solidity/src/vaults/YieldBearingVault.sol](pegasus/packages/solidity/src/vaults/YieldBearingVault.sol)

