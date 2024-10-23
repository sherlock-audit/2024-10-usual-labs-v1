# Role & Permissions

## DEFAULT_ADMIN_ROLE

- Add USD0 RWA (TokenMapping)
- Unpause (AirdropDistribution, AirdropTaxCollector, DaoCollateral, DistributionModule, L2Usd0, L2Usd0PP, SwapperEngine, Usd0, USD0pp, Usual, UsualS, USUALSP, UsualX)
- Activate/Deactivate CBR (DaoCollateral)
- Set redeem fee (DaoCollateral)
- Redeem DAO (DaoCollateral)
- Unpause redeem/swap (DaoCollateral)
- Set max depeg threshold (AbstractContract)
- Initialize token oracle (ClassicalOracle, UsualOracle)
- Set role admin (RegistryAccess)
- Set contract (RegistryContract)
- Update minimum USDC amount provided (SwapperEngine)
- Emergency withdraw (USD0pp)

## AIRDROP_OPERATOR_ROLE

- Set merkle root (AirdropDistribution)
- Set max chargeable tax (AirdropTaxCollector)
- Set USD0pp prelaunch balances (AirdropTaxCollector)

## AIRDROP_PENALTY_OPERATOR_ROLE

- Set penalty percentages (AirdropDistribution)

## PAUSING_CONTRACTS_ROLE

- Pause (AirdropTaxCollector, DaoCollateral, DistributionModule, L2Usd0, L2Usd0PP, SwapperEngine, Usd0, USD0pp, Usual, UsualS, USUALSP, UsualX)

## NONCE_THRESHOLD_SETTER_ROLE

- Set nonce threshold (DaoCollateral)

## INTENT_MATCHING_ROLE

- Swap RWA to STBC intent (DaoCollateral)

## DISTRIBUTION_OPERATOR_ROLE

- Distribute USUAL to buckets (DistributionModule)
- Queue off-chain USUAL distribution (DistributionModule)
- Reset off-chain distribution queue (DistributionModule)

## DISTRIBUTION_ALLOCATOR_ROLE

- Set buckets distribution (DistributionModule)
- Set gamma (DistributionModule)
- Set rate min (DistributionModule)
- Set D (DistributionModule)
- Set M0 (DistributionModule)

## DISTRIBUTION_CHALLENGER_ROLE

- Challenge distribution (DistributionModule)

## BLACKLIST_ROLE

- Blacklist/Unblacklist (L2Usd0, L2Usd0PP, USD0pp, Usd0, Usual, UsualS, UsualX)

## USD0_MINT

- Mint (L2Usd0, L2Usd0PP, Usd0)

## USD0_BURN

- Burn (L2Usd0, L2Usd0PP, Usd0)
- Burn from (L2Usd0, L2Usd0PP, Usd0)

## EARLY_BOND_UNLOCK_ROLE

- Allocate early unlock balance (USD0pp)
- Setup early unlock period (USD0pp)

## PEG_MAINTAINER_ROLE

- Trigger PAR mechanism Curvepool (USD0pp)
- Unwrap peg maintainer (USD0pp)

## USUAL_MINT

- Mint (Usual)

## USUAL_BURN

- Burn (Usual)
- Burn from (Usual)

## USUALS_BURN

- Burn (UsualS)
- Burn from (UsualS)

## USUALSP_OPERATOR_ROLE

- Allocate (USUALSP)
- Remove original allocation (USUALSP)
- Stake UsualS (USUALSP)

## WHITELIST_ROLE

- Whitelist (UsualX)
- Unwhitelist (UsualX)

## WITHDRAW_FEE_UPDATER_ROLE

- Update withdraw fee (UsualX)

## FLOOR_PRICE_UPDATER_ROLE

- Update floor price (USD0pp)

## TokenMapping

- `DEFAULT_ADMIN_ROLE`
  - can call `addUsd0Rwa`

## AirdropDistribution.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `AIRDROP_OPERATOR_ROLE`
  - can call `setMerkleRoot`
- `AIRDROP_PENALTY_OPERATOR_ROLE`
  - can call `setPenaltyPercentages`
- `PAUSING_CONTRACTS_ROLE`

## AirdropTaxCollector.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `AIRDROP_OPERATOR_ROLE`
  - can call `setMaxChargeableTax`
  - can call `setUsd0ppPrelaunchBalances`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`

## DaoCollateral.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `activateCBR`
  - can call `deactivateCBR`
  - can call `setRedeemFee`
  - can call `redeemDao`
  - can call `unpause`
  - can call `unpauseRedeem`
  - can call `unpauseSwap`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `NONCE_THRESHOLD_SETTER_ROLE`
  - can call `setNonceThreshold`
- `INTENT_MATCHING_ROLE`
  - can call `swapRWAtoStbcIntent`

## DistributionModule.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `DISTRIBUTION_OPERATOR_ROLE`
  - can call `distributeUsualToBuckets`
  - can call `queueOffChainUsualDistribution`
  - can call `resetOffChainDistributionQueue`
- `DISTRIBUTION_ALLOCATOR_ROLE`
  - can call `setBucketsDistribution`
  - can call `setGamma`
  - can call `setRateMin`
  - can call `setD`
  - can call `setM0`
- `DISTRIBUTION_CHALLENGER_ROLE`
  - can call `challengeDistribution`

## DistributionModule.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `DISTRIBUTION_OPERATOR_ROLE`
  - can call `distributeUsualToBuckets`
  - can call `queueOffChainUsualDistribution`
  - can call `resetOffChainDistributionQueue`
- `DISTRIBUTION_ALLOCATOR_ROLE`
  - can call `setBucketsDistribution`
  - can call `setGamma`
  - can call `setRateMin`
  - can call `setD`
  - can call `setM0`
- `DISTRIBUTION_CHALLENGER_ROLE`

  - can call `challengeDistribution`

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `BLACKLIST_ROLE`
  - can call `blacklist`
  - can call `unBlacklist`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `USD0_MINT`
  - can call `mint`
- `USD0_BURN`
  - can call `burn`
  - can call `burnFrom`

## L2Usd0PP.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `USD0_MINT`
  - can call `mint`
- `USD0_BURN`
  - can call `burn`
  - can call `burnFrom`

## AbstractContract.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `setMaxDepegThreshold`

## ClassicalOracle.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `initializeTokenOracle`

## UsualOracle.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `initializeTokenOracle`

## RegistryAccess.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `setRoleAdmin`

## RegistryContract.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `setContract`

## SwapperEngine.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
  - can call `updateMinimumUSDCAmountProvided`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `DEFAULT_ADMIN_ROLE`
  - can call `blacklist`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `USD0_BURN`
  - can call `burn`
  - can call `burnFrom`
- `USD0_MINT`
  - can call `mint`
- `BLACKLIST_ROLE`
  - can call `blacklist`
  - can call `unBlacklist`

## USD0pp.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
  - can call `emergencyWithdraw`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `EARLY_BOND_UNLOCK_ROLE`
  - can call `allocateEarlyUnlockBalance`
  - can call `setupEarlyUnlockPeriod`
- `PEG_MAINTAINER_ROLE`
  - can call `triggerPARMechanismCurvepool`
  - can call `unwrapPegMaintainer`
- `FLOOR_PRICE_UPDATER_ROLE`
  - can call `updateFloorPrice`

## Usual.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `BLACKLIST_ROLE`
  - can call `blacklist`
  - can call `unBlacklist`
- `USUAL_MINT`
  - can call `mint`
- `USUAL_BURN`
  - can call `burn`
  - can call `burnFrom`

## UsualS.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `BLACKLIST_ROLE`
  - can call `blacklist`
  - can call `unBlacklist`
- `USUALS_BURN`
  - can call `burn`
  - can call `burnFrom`

## USUALSP.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `USUALSP_OPERATOR_ROLE`
  - can call `allocate`
  - can call `removeOriginalAllocation`
  - can call `stakeUsualS`

## UsualX.sol

- `DEFAULT_ADMIN_ROLE`
  - can call `unpause`
- `PAUSING_CONTRACTS_ROLE`
  - can call `pause`
- `BLACKLIST_ROLE`
  - can call `blacklist`
  - can call `unBlacklist`
- `WHITELIST_ROLE`
  - can call `whitelist`
  - can call `unWhitelist`
- `WITHDRAW_FEE_UPDATER_ROLE`
  - can call `updateWithdrawFee`
