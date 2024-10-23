# YieldBearingVault.sol

# High-Level Overview

The YieldBearingVault contract is an abstract contract that extends the ERC4626Upgradeable contract and provides functionality for a vault where shares appreciate in value due to yield accrual. The contract tracks total assets deposited and accrues yield over time based on a configurable yield rate and distribution period.

## Contract Summary

The contract provides the following main functions:

- **totalAssets**: Calculates the total assets in the vault, including accrued yield.
- **_deposit**: Internal function to handle 4626 deposits and mints, updates yield, and tracks total deposits explicitly to avoid vault donation attacks.
- **_withdraw**: Internal function to handle 4626 withdrawals and mints, updates yield, and updates total deposits.
- **_calculateEarnedYield**: Calculates the amount of yield earned since the last update.
- **_updateYield**: Updates the yield state by calculating yield earned and adding it to total deposits.
- **_startYieldDistribution**: Starts a new yield distribution period.

The contract uses a separate internal storage structure (YieldDataStorage) to store yield-related state variables, including total deposits, yield rate, period start and finish times, last update time, and maximum period length.

## Inherited Contracts

- **[ERC4626Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v5.0/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol)** : The contract inherits from the ERC4626Upgradeable contract, which provides the standard implementation for tokenized vaults.

# Functionality Breakdown

The contract's main functionality is to provide a foundation for implementing yield-bearing vaults that follow the ERC4626 standard. The contract handles the calculation and distribution of yield, updating the total assets in the vault based on the accrued yield.

1. **Yield Calculation and Distribution**:

- The contract tracks the total assets deposited and accrues yield over time based on a configurable yield rate and distribution period.
- The _calculateEarnedYield function calculates the amount of yield earned since the last update, taking into account the active yield period and the yield rate.
- The _updateYield function updates the yield state by calculating the earned yield and adding it to the total deposits. It also updates the last update timestamp and deactivates the yield period if it has finished.
- The _startYieldDistribution function starts a new yield distribution period with a specified yield amount, start time, and end time.


2. **Deposits and Withdrawals**:

- The contract overrides the internal _deposit and _withdraw functions from the ERC4626Upgradeable contract to handle deposits and withdrawals while considering the yield accrual.
- The _deposit function updates the yield, takes the deposited assets, mints shares, and updates the total deposits.
- The _withdraw function updates the yield, burns shares, transfers the withdrawn assets, and updates the total deposits.


3. **Total Assets Calculation**:

- The totalAssets function calculates the total assets in the vault, including the accrued yield, by adding the total deposits and the earned yield.


## Security Analysis

### Method: totalAssets

Calculates the total assets in the vault, including accrued yield since the last time totalDeposits was updated. This effectively allows yield to accrue uniformly over time.

```solidity
 1  function totalAssets() public view override returns (uint256) {
 2      YieldDataStorage storage $ = _getYieldDataStorage();
 3      uint256 currentAssets = $.totalDeposits + _calculateEarnedYield();
 4      return currentAssets;
 5  }
```

1. Function is declared as `public view`, allowing external calls without state modifications.
2. Retrieves the YieldDataStorage struct from storage.
3. Calculates current assets by adding total deposits and earned yield since the last time total deposits was updated if there is an active yield period.
4. Returns the calculated current assets as the total assets in the vault.

### Method: _deposit

Internal function to handle deposits, update yield, and track total deposits explicitly to only count the yield that has accrued so far. Addresses the vault donation attack. Can be overridden in the concrete implementation to allow for fees.

```solidity
 1  function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
 2      internal
 3      virtual
 4      override
 5  {
 6      YieldDataStorage storage $ = _getYieldDataStorage();
 7      _updateYield();
 8      super._deposit(caller, receiver, assets, shares);
 9      $.totalDeposits += assets;
10  }
```

1-5. Function is internal, virtual, overrides the parent contract's _deposit function.

6. Retrieves the YieldDataStorage struct from storage.
7. Updates the yield accrued by the vault before processing the deposit.
8. Calls the ERC4626Upgradeable contract's _deposit function to take assets and mint.
9. Finally updates the totalDeposits by adding the deposited assets.

### Method: _withdraw

Internal function to handle withdrawals, update yield, and adjust total deposits explicitly. Can be overriden in the concrete implementation to allow for withdraw fees.
```solidity
 1  function _withdraw(
 2      address caller,
 3      address receiver,
 4      address owner,
 5      uint256 assets,
 6      uint256 shares
 7  ) internal virtual override {
 8      YieldDataStorage storage $ = _getYieldDataStorage();
 9      _updateYield();
10      super._withdraw(caller, receiver, owner, assets, shares);
11      $.totalDeposits -= assets;
12  }
```

1-7. Function is internal, virtual, overrides the parent contract's deposit function.

8. Retrieves the YieldDataStorage struct from storage.
9. Updates the yield before processing the withdrawal.
10. Calls the parent contract's _withdraw function to burn shares then transfer assets.
11. Updates the totalDeposits by subtracting the withdrawn assets.

### Method: _calculateEarnedYield

Calculates the amount of yield earned since the last update without updating state.

```solidity
 1  function _calculateEarnedYield() internal view virtual returns (uint256) {
 2      YieldDataStorage storage $ = _getYieldDataStorage();
 3      if (!$.isActive) return 0;
 4      uint256 endTime = Math.min(block.timestamp, $.periodFinish);
 5      uint256 duration = endTime - $.lastUpdateTime;
 6      return Math.mulDiv(duration, $.yieldRate, YIELD_PRECISION, Math.Rounding.Floor);
 7  }
```

1. Function is declared as internal view, allowing only internal calls without state modifications.
2. Retrieves the YieldDataStorage struct from storage.
3. Returns 0 if there's no active yield period.
5. Calculates the end time as the minimum of current time and period finish time.
6. Calculates the duration since the last update capped at the current yield period finish time.
7. Calculates and returns the earned yield by multiplying by yield rate as tokens/second allowing for high decimal precision and rounding down.

## Method: _updateYield

Updates the yield storage by calculating earned yield at the current time stamp and adding it to total deposits, then updates the last update time capped at the end of the current yield period. No-op if there is active yield period because the contract was just deployed or the previous yield period has finished.

```solidity
 1  function _updateYield() internal virtual {
 2      YieldDataStorage storage $ = _getYieldDataStorage();
 3      if (!$.isActive) return;
 4  
 5      uint256 newYield = _calculateEarnedYield();
 6      $.totalDeposits += newYield;
 7  
 8      $.lastUpdateTime = Math.min(block.timestamp, $.periodFinish);
 9  
10      if (block.timestamp >= $.periodFinish) {
11          $.isActive = false;
12      }
13  }
```

1. Function is declared as internal virtual, allowing internal calls and potential overrides.
2. Retrieves the YieldDataStorage struct from storage.
3. Returns early if there's no active yield period.
5. Calculates the new yield earned since the lastUpdateTime.
6. Adds the new yield to total deposits.
8. Updates the last update time, capped at the period finish time.
10-12. Deactivates the yield period if it has finished.

### Method: _startYieldDistribution

This method is left abstract and needs to be implemented in the derived contract. It's crucial for setting up the variables needed for calculating and updating yield. When implementing this method, consider the following:

- Set the `yieldRate` based on the `yieldAmount` and the duration (`endTime - startTime`) times the YIELD_PRECISION.
- Update `periodStart`, `periodFinish`, and `lastUpdateTime`.
- Set `isActive` to true to enable yield calculations.
- Implement proper access control to prevent unauthorized yield distributions.
- Ensure that the new distribution period doesn't overlap with an existing active period.
```solidity
 1  function _startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime) internal virtual;
```
# UsualX.sol

## High-Level Overview

The UsualX contract is an upgradeable ERC4626-compliant yield-bearing vault. It extends the YieldBearingVault contract, incorporating features such as whitelisting, blacklisting, withdrawal fees, and yield distribution linearly over a predefined yield period. The contract leverages OpenZeppelin's upgradeable contracts for enhanced security and flexibility, including pausability and reentrancy protection. It also implements EIP712 for secure off-chain signing capabilities.

The primary objective of UsualX is to provide a secure, controllable environment for yield generation and distribution, while maintaining strict control over who can interact with the contract. This design allows for potential regulatory compliance and risk management in decentralized finance applications.

## Contract Summary

The contract provides the following main functions:
- `initialize`: Sets up the contract with customizable parameters.
- `pause` / `unpause`: Controls the operational state of the contract.
- `blacklist` / `unBlacklist`: Manages addresses prohibited from interacting with the contract.
- `whitelist` / `unWhitelist`: Controls addresses permitted to transfer tokens.
- `transfer` / `transferFrom`: Overridden to enforce whitelist restrictions.
- `startYieldDistribution`: Initiates a new yield accrual period with specified parameters.
- `depositWithPermit`: Allows users to deposit tokens using a permit signature.
- `withdraw` / `redeem`: Handles asset withdrawals and share redemptions, incorporating withdrawal fees.
- `previewWithdraw` / `previewRedeem`: Simulates withdrawal and redemption operations for users.
The contract uses a separate storage structure (UsualXStorageV0) to store state variables for UsualX implementation.

## Inherited Contracts

- YieldBearingVault: Provides core yield accrual and distribution mechanisms.
- PausableUpgradeable: Enables emergency halt of contract operations.
- ReentrancyGuardUpgradeable: Prevents reentrancy attacks in critical functions.
- EIP712Upgradeable: Implements EIP712 for secure off-chain message signing.

## Functionality Breakdown

1. Access Control and Security:
   - Utilizes a registry contract for role-based access control.
   - Implements blacklist to prevent specific addresses from interacting with the contract.
  - Enforces whitelist for token transfers, allowing only approved addresses to transfer tokens at launch but anyone not blacklisted to mint or interact with the vault.
2. Yield Management:
   - Allows admin-controlled yield distribution periods.
   - Accrues yield over time based on configurable parameters.
   - Integrates yield accrual with deposit and withdrawal operations.

3. Asset Management:
   - Implements ERC4626 standard for standardized vault interactions.
   - Handles deposits, deposits with permit, withdrawals, and redemptions with consideration for accrued yield.
   - Applies withdrawal fees, potentially for protocol revenue or discouraging rapid withdrawals.

4. Upgradability and Pause Mechanism:
   - Utilizes OpenZeppelin's upgradeable contract pattern for future improvements.
   - Includes pause functionality for emergency situations.

## Security Analysis

### Method: initialize

Initializes the vault, token, yield module, EIP712 domain, registry contract and access control, setting up the vault's initial state.

```solidity
 1  function initialize(
 2      address _registryContract,
 3      uint256 _withdrawFeeBps,
 4      string memory _name,
 5      string memory _symbol,
 6      IERC20 _underlying,
 7      uint256 _maxPeriodLength
 8  ) external initializer {
 9      __YieldBearingVault_init(_maxPeriodLength);
10      __ERC4626_init(_underlying);
11      __ERC20_init(_name, _symbol);
12      __Pausable_init_unchained();
13      __ReentrancyGuard_init();
14      __EIP712_init_unchained(_name, "1");
15  
16      if (_withdrawFeeBps > MAX_WITHDRAW_FEE) {
17          revert AmountTooBig();
18      }
19  
20      if (_registryContract == address(0)) {
21          revert NullContract();
22      }
23  
24      UsualXStorageV0 storage $ = _usualXStorageV0();
25      $.withdrawFeeBps = _withdrawFeeBps;
26      $.registryContract = IRegistryContract(_registryContract);
27      $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
28  }
```

1-8. Set the registry contract, withdrawal fee in BPS, token name and symbol for the vault, underlying asset, and the max yield period length.

9-14. Initializes inherited contracts, with initializer parameters.

16-18. Validates withdrawal fee is below 25% preventing excessive fees that could harm users.

20-22. Ensures a valid registry contract, reverts if zero address.

24-26. Sets up contract storage with validated parameter.

27. Points at the access control registry in the registry contract.

### Method: blacklist

Adds an address to the blacklist, preventing it from interacting with the contract.

```solidity
 1  function blacklist(address account) external {
 2      if (account == address(0)) {
 3          revert NullAddress();
 4      }
 5      UsualXStorageV0 storage $ = _usualXStorageV0();
 6      $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
 7      if ($.isBlacklisted[account]) {
 8          revert SameValue();
 9      }
10      $.isBlacklisted[account] = true;
11  
12      emit Blacklist(account);
13  }
```

1. Mark function as external to save gas.
2-4. Prevents blacklisting of zero address, and reverts if trying to pass zero address.

5-6. Utilizes the registry for role-based access control, restricting to admin.

7-9. Reverts if the account is already blacklisted.

10. Adds the account to the blacklist in UsualXStorageV0.
12. Emits an event to log the blacklisting action.

### Method: _update

Internal hook ensuring that both sender and receiver are not blacklisted before updating the token balances.

```solidity
 1  function _update(address from, address to, uint256 amount)
 2      internal
 3      override(ERC20Upgradeable)
 4  {
 5      UsualXStorageV0 storage $ = _usualXStorageV0();
 6      if ($.isBlacklisted[from] || $.isBlacklisted[to]) {
 7          revert Blacklisted();
 8      }
 9      super._update(from, to, amount);
10  }
```

1-4. Internal function overriding the base ERC20Upgradeable implementation.

5. Retrieves storage pointer for UsualXStorageV0.
6-8. Checks both sender and receiver against blacklist, reverting if either is blacklisted.

9. Passes through to parent implementation if checks pass.

### Method: transfer

Overrides the standard ERC20 transfer function to enforce whitelist restrictions on token transfers when the contract is deployed. This can later be removed via smart contract upgrade.

```solidity
 1  function transfer(address to, uint256 value)
 2      public
 3      override(ERC20Upgradeable, IERC20)
 4      returns (bool)
 5  {
 6      address owner = _msgSender();
 7      UsualXStorageV0 storage $ = _usualXStorageV0();
 8      if ($.isWhitelisted[owner]) {
 9          _transfer(owner, to, value);
10          return true;
11      }
12      revert NotWhitelisted();
13  }
```

1-5. Public function overriding ERC20 transfer base implementation.

6-7. Uses `_msgSender()` for potential meta-transaction support, and retrieve storage pointer.

8-11. Allows whitelisted senders to transfer tokens, otherwise reverts.

12. Reverts if sender is not whitelisted.

Security considerations:
- Correctly enforces whitelist for senders, but doesn't check recipient's whitelist status.
- Consider adding a check for the contract's paused state.
- The function doesn't emit a custom event for whitelisted transfers, which could aid in monitoring.

### Method: startYieldDistribution

Initiates a new yield distribution period with specified parameters wrapping the internal call to add proper access control.

```solidity
 1  function startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime)
 2      external
 3  {
 4      _requireOnlyAdmin();
 5      _startYieldDistribution(yieldAmount, startTime, endTime);
 6  }
```

1-3. External function for starting a new yield period.

4. Ensures only admin set on registry access can call this function.
5. Delegates to internal function for yield distribution logic.

### Method: depositWithPermit

Allows users to deposit tokens using a permit signature.

```solidity
 1   function depositWithPermit(
 2      uint256 assets,
 3      address receiver,
 4      uint256 deadline,
 5      uint8 v,
 6      bytes32 r,
 7      bytes32 s
 8   ) external whenNotPaused nonReentrant returns (uint256 shares) {
 9      try IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s) {}
 10         catch {} // solhint-disable-line no-empty-blocks
 11     return deposit(assets, receiver);
 12  }
```

1-8. External function for depositing with permit.

9-10. Attempts to call permit on the asset contract, catching any revert and ignoring them.
11. Calls the parent deposit function with the specified assets and receiver.

### Method: withdraw

Overrides the ERC4626 withdraw function to include withdrawal fees and enforce withdrawal limits, calcualtes shares internally to avoid another storage fetch from calling previewWithdraw.

```solidity
 1  function withdraw(uint256 assets, address receiver, address owner)
 2      public
 3      override
 4      returns (uint256 shares)
 5  {
 6      UsualXStorageV0 storage $ = _usualXStorageV0();
 7      YieldDataStorage storage yieldStorage = _getYieldDataStorage();
 8  
 9      uint256 maxAssets = maxWithdraw(owner);
10      if (assets > maxAssets) {
11          revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
12      }
13  
14      uint256 fee = Math.mulDiv(assets, $.withdrawFeeBps, BPS_DENOMINATOR, Math.Rounding.Floor);
15      uint256 assetsWithFee = assets + fee;
16  
17      shares = convertToShares(assetsWithFee);
18  
19      yieldStorage.totalDeposits -= fee;
20  
21      super._withdraw(_msgSender(), receiver, owner, assets, shares);
22  }
```

1-5. Public function overriding the ERC4626 withdraw function.

6-7. Retrieves storage pointers for UsualXStorageV0 and YieldDataStorage.

9-12. Checks if the withdrawal amount exceeds the maximum allowed, and reverts if so.

14-15. Calculates the withdrawal fee based on the number of assets user wants to withdraw taking the precision into account.

17. Converts assets to shares, considering the fee.

19. Deducts the fee from the total deposits in the yield storage.
21. Calls parent withdrawal function with calculated values.


