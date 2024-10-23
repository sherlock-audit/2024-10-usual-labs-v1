# High-Level Overview

The **SwapperEngine** contract is a smart contract designed to facilitate the swapping of _USDC_ tokens for _USD0_ tokens using an order matching mechanism. The contract allows users to create orders specifying the amount of _USDC_ they wish to swap, and other users can fill these orders by providing _USD0_ tokens in return. The contract aims to provide a direct token swapping solution without the need for intermediary liquidity pools.

The main objective of the **SwapperEngine** contract is to enable efficient and low-slippage token swaps between users. The contract relies on oracle-based pricing to determine swap prices, which helps minimize slippage. However, liquidity within the contract depends on the availability of active orders, and users may need to wait for new orders to be created if no matching orders are available.

It is important to note that the contract's mechanism can be utilized to facilitate a vampire attack, **RWA → USD0 → USDC → $$$ → RWA →** to churn _USDC_ into USD0 by transparently staking treasury bonds to mint _USD0_ swapping that _USD0_ for _USDC_ and cycling back into RWA ready to mint more _USD0_ limited only by _USDC_ order book depth.

## Contract Summary

The contract provides the following main functions:

- **depositUSDC**: Allows users to create a new order by depositing _USDC_.
- **withdrawUSDC**: Allows users to cancel an order and withdraw their deposited _USDC_.
- **provideUsd0ReceiveUSDC**: Allows users to fill orders by providing _USD0_ and receiving _USDC_ in return.

The contract also includes utility functions such as getOrder, getUsd0WadEquivalent, and getUsdcWadPrice to retrieve order details and perform price calculations. The swapperEngine has no option to define a maxUSDCPrice for buyers and seller's don't have the option to define a minimumUSDCPrice, instead the prices are provided by an USDC oracle, which also has measures against a potential USDC depeg. USD0's price is considered to be $1 == 1USD0 due to the numerous mechanisms in place to prevent a depeg, like reserves, CBR mechanism, arbitrage etc.

## Inherited Contracts

- **Initializable** (OZ): Used to provide a safe and controlled way to initialize the contract's state variables. It ensures that the contract's initializer function can only be called once, preventing accidental or malicious reinitialization.
- **ReentrancyGuardUpgradeable** (OZ): Used to protect against reentrancy attacks. It provides a modifier that can be applied to functions to prevent them from being called recursively or from being called from other functions that are also protected by the same guard.

# Functionality Breakdown

The SwapperEngine contract's primary purpose is to facilitate the swapping of _USDC_ tokens for _USD0_ tokens using an order matching mechanism. The contract's functionality can be broken down into the following key components:

1. **Order Creation**:
   - Users can create new orders by calling the **depositUSDC** function and specifying the amount of _USDC_ they wish to swap.
   - The contract transfers the specified amount of _USDC_ tokens from the user to itself and creates a new order with the deposited amount and the user's address as the requester.
   - The order is assigned a unique order ID and stored in the contract's orders mapping.
2. **Order Cancellation**:
   - Users who have created an order can cancel it by calling the **withdrawUSDC** function and specifying the order ID.
   - The contract verifies that the caller is the requester of the order and that the order is active.
   - If the conditions are met, the contract deactivates the order, sets its token amount to zero, and transfers the deposited _USDC_ tokens back to the requester.
3. **Order Matching**:
   - Users can fill existing orders specifying the recipient address, the amount of _USDC_ to take (or the amount of USD0 to give), an array of order IDs to match against, and whether partial matching is allowed.
   - The contract verifies that the caller has sufficient _USD0_ balance and allowance to cover the required amount based on the current _USDC_ Price Calculation obtained from the oracle.
   - The contract iterates through the provided order IDs and attempts to match the requested _USDC_ amount against active orders.
   - If partial matching is allowed and there is not enough _USDC_ in the orders to fulfill the entire request, the contract will partially fill orders until the requested amount is met or all orders are exhausted.
   - For each matched order, the contract transfers the corresponding _USD0_ tokens from the caller to the order requester and transfers the _USDC_ tokens from itself to the specified recipient.
   - If partial matching is not allowed and the requested _USDC_ amount cannot be fully matched, the contract reverts the transaction.
4. **Price Calculation**:
   - The contract relies on an external oracle contract to obtain the current price of _USDC_ tokens in WAD format (18 decimals).
   - The getUsdcWadPrice function is used to retrieve the current _USDC_ price from the oracle.
   - The getUsd0WadEquivalent function is used to calculate the equivalent amount of _USD0_ tokens for a given amount of _USDC_ tokens based on the current price.

## Security Analysis

### Method: provideUsd0ReceiveUSDC

This method allows users to provide _USD0_ tokens and receive _USDC_ tokens by matching against existing orders. It matches the requested _USDC_ amount to the provided _USD0_ tokens against the specified orders, transfers the corresponding _USDC_ tokens to the recipient, and updates the order states accordingly.

```rust
1 function _provideUsd0ReceiveUSDC( ... ) internal returns (uint256 unmatchedUsdcAmount, uint256 totalUsd0Provided) {
2    if (amountUsdcToTakeInNativeDecimals == 0) { revert AmountIsZero() }
3    if (orderIdsToTake.length == 0) { revert NoOrdersIdsProvided() }
4    SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
5    uint256 usdcWadPrice = _getUsdcWadPrice();
6    uint256 totalUsdcTaken = 0;

```

1. The function is protected against reentrancy attacks by using the nonReentrant modifier, ensuring that the function cannot be called recursively or from other functions that are also protected by the same guard.
2. Validates that the amount of _USDC_ to take is greater than zero.
3. Validates that at least one order ID is provided for matching.
4. Retrieves the contract's storage using the correct storage pattern.
5. Retrieves the current price of _USDC_ in WAD format (18 decimals) from an oracle, ensuring that the price used for calculations is up-to-date and accurate.
6. Initializes the total amount of _USDC_ taken to zero.

```rust
 8  for (uint256 i; i < orderIdsToTake.length && totalUsdcTaken < amountUsdcToTakeInNativeDecimals;) {
 9      uint256 orderId = orderIdsToTake[i];
10      UsdcOrder storage order = $.orders[orderId];
11      if (order.active) {
12          uint256 remainingAmountToTake = amountUsdcToTakeInNativeDecimals - totalUsdcTaken;
13          uint256 amountOfUsdcFromOrder = order.tokenAmount > remainingAmountToTake ? remainingAmountToTake : order.tokenAmount;
14          order.tokenAmount -= amountOfUsdcFromOrder;
15          totalUsdcTaken += amountOfUsdcFromOrder;
16          if (order.tokenAmount == 0) { order.active = false };
17          uint256 usd0Amount = _getUsd0WadEquivalent(amountOfUsdcFromOrder, usdcWadPrice);
18          totalUsd0Provided += usd0Amount;
19          $.usd0.safeTransferFrom(msg.sender, order.requester, usd0Amount);
20          $.usdcToken.safeTransfer(recipient, amountOfUsdcFromOrder);
21          emit OrderMatched(order.requester, msg.sender, orderId, amountOfUsdcFromOrder);
22      }
23      unchecked { ++i }
24  }
25  if (!partialMatchingAllowed && totalUsdcTaken != amountUsdcToTakeInNativeDecimals || totalUsdcTaken == 0) { revert AmountTooLow() }
26  return ((amountUsdcToTakeInNativeDecimals - totalUsdcTaken), totalUsd0Provided);
...
```

10. Retrieves the order details for the current order ID.
11. Checks if the order is active before processing.
    12-13. If the order is active, calculates the amount of USDC to take from the current order based on the remaining amount to take and the order's available balance.
    14-15. Updates the order's token amount and the total USDC taken.
12. Marks the order as inactive if its token amount reaches zero.
13. Calculates the equivalent USD0 amount for the USDC taken from the order using the \_getUsd0WadEquivalent function and the current USDC price.
14. Updates the total USD0 provided with the calculated amount.
15. Transfers the USD0 tokens from the sender to the order requester.
16. Transfers the USDC tokens from the contract to the recipient.
17. Emits an OrderMatched event with the relevant details.
18. Increments the loop counter using an unchecked block for gas optimization.
19. Reverts the transaction if partial matching is not allowed and the total USDC taken does not match the requested amount or if no USDC was taken.
20. Returns the remaining amount of USDC that was not taken and the total USD0 provided.

### Method: getUsd0WadEquivalent

This method calculates the USD0 equivalent amount in WAD format (18 decimals) for a given USDC token amount. It converts the USDC token amount from its native decimal representation (6 decimals) to WAD format and then calculates the equivalent USD0 amount based on the provided USDC price in WAD format.

```rust
1  function _getUsd0WadEquivalent(uint256 usdcTokenAmountInNativeDecimals, uint256 usdcWadPrice) private view returns (uint256 usd0WadEquivalent) {
2      SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
3      uint8 decimals = IERC20Metadata(address($.usdcToken)).decimals();
4      uint256 usdcWad = usdcTokenAmountInNativeDecimals.tokenAmountToWad(decimals);
5      usd0WadEquivalent = usdcWad.wadAmountByPrice(usdcWadPrice);
6  }
```

2. Retrieves the contract's storage using the correct storage pattern.
3. Retrieves the decimal places of the USDC token using the decimals() function from the IERC20Metadata interface.
4. Converts the usdcTokenAmountInNativeDecimals to WAD format (18 decimals) using the tokenAmountToWad function, which takes into account the token's native decimals.
5. Calculates the equivalent amount of USD0 tokens in WAD format by multiplying the usdcWad amount with the usdcWadPrice using the wadAmountByPrice function.

### Method: depositUSDC

This method allows users to deposit USDC tokens and create a new order. It transfers the specified amount of USDC tokens from the caller to the contract and creates a new order with the deposited amount and the caller as the requester.

```rust
1  function depositUSDC(uint256 amountToDeposit) external nonReentrant {
2      SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
3      if (amountToDeposit < $.minimumUSDCAmountProvided) { revert AmountTooLow();}
4      uint256 orderId = $.nextOrderId++;
5      $.orders[orderId] = UsdcOrder({requester: msg.sender, tokenAmount: amountToDeposit, active: true});
6      $.usdcToken.safeTransferFrom(msg.sender, address(this), amountToDeposit);
7      emit Deposit(msg.sender, orderId, amountToDeposit);
8  }
```

1. The function is protected against reentrancy attacks by using the nonReentrant modifier, ensuring that the function cannot be called recursively or from other functions that are also protected by the same guard.
2. Retrieves the contract's storage using the correct storage pattern.
3. Validates that the amount of USDC to deposit is greater than or equal to the minimum required amount specified in the contract's storage. This prevents any attempts to deposit amounts below the minimum threshold.
4. Sets the value of orderId to the current value of $.nextOrderId then increments by 1. Since it is initialized as 1, the first orderId will be one and so on.
5. Creates a new UsdcOrder struct in storage using the order ID as key. The struct is set up correctly to contain: the requester's address (msg.sender), the deposited token amount (amountToDeposit), and sets the active flag to true.
6. Transfers the specified amount of USDC tokens from the caller (msg.sender) to the contract (address(this)) using the safeTransferFrom function to ensure that the transfer is successful and the contract receives the deposited tokens. If the transfer fails, the function will revert.
7. Emits a Deposit event, providing the order ID and the deposited amount for the subgraph.

### Method: withdrawUSDC

This method allows the requester of an order to withdraw their deposited USDC tokens and cancel the order. It deactivates the specified order, sets its token amount to zero, and transfers the deposited USDC tokens back to the requester.

```rust
 1  function withdrawUSDC(uint256 orderToCancel) external nonReentrant {
 2      SwapperEngineStorageV0 storage $ = _swapperEngineStorageV0();
 3      UsdcOrder storage order = $.orders[orderToCancel];
 4      if (!order.active) { revert OrderNotActive() }
 5      if (order.requester != msg.sender) { revert NotRequester() }
 6      uint256 amountToWithdraw = order.tokenAmount;
 7      order.active = false;
 8      order.tokenAmount = 0;
 9      $.usdcToken.safeTransfer(msg.sender, amountToWithdraw);
10      emit Withdraw(msg.sender, orderToCancel, amountToWithdraw);
11  }
```

1. The function is protected against reentrancy attacks by using the nonReentrant modifier, ensuring that the function cannot be called recursively or from other functions that are also protected by the same guard.
2. Retrieves the contract's storage using the correct storage pattern.
3. Retrieves the UsdcOrder struct as storage so it will be modified.
4. Checks if the order is active using the active flag. If the order is not active or does not exist, the function will revert with an appropriate error message. This prevents any attempts to withdraw from invalid or canceled orders.
5. Verifies that the caller (msg.sender) is the requester of the order. This ensures that only the original requester can cancel their own order and withdraw the deposited tokens.
6. Retrieves the token amount associated with the order and assigns it to the amountToWithdraw variable.
7. Sets the active flag of the order to false in storage.
8. Sets the tokenAmount of the order to zero in storage.
9. Transfers the amountToWithdraw of USDC tokens from the contract back to the requester (msg.sender) using the safeTransfer function. This ensures that the transfer is successful and the requester receives their tokens. If the transfer fails, the function will revert.
10. Emits a Withdraw event, providing the orderToCancel ID and the amountToWithdraw for the subgraph

## Method swapUsd0

This method allows users to provide _USD0_ tokens and receive _USDC_ tokens by matching against existing orders. It matches the specified amount of _USD0_ tokens against the specified orders, transfers the corresponding _USDC_ tokens to the recipient, and updates the order states accordingly.

```rust
 1  function swapUsd0(address recipient, uint256 amountUsd0ToProvideInWad, uint256[] memory orderIdsToTake, bool partialMatchingAllowed) external nonReentrant returns (uint256) {
 2      uint256 usdcWadPrice = _getUsdcWadPrice();
 3      (, uint256 totalUsd0Provided) = _provideUsd0ReceiveUSDC(
 4        recipient, _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideInWad, usdcWadPrice), orderIdsToTake, partialMatchingAllowed
 5      );
 6      return amountUsd0ToProvideInWad - totalUsd0Provided;
 7  }
```

1. The function is protected against reentrancy attacks by using the nonReentrant modifier, ensuring that the function cannot be called recursively or from other functions that are also protected by the same guard.
2. Retrieves the current USDC price in WAD format using the getUsdcWadPrice() function.
   3-5. Calculates the equivalent amount of USDC to take in native decimals based on the provided amountUsd0ToProvideInWad and the current usdcWadPrice using the \_getUsdcAmountFromUsd0WadEquivalent function. Then calls the \_provideUsd0ReceiveUSDC function to perform the actual swap, passing the recipient, amountUsdcToTakeInNativeDecimals, orderIdsToTake, and partialMatchingAllowed parameters. The function returns the total amount of usd0 provided.
3. Returns the sum of unmatchedUsd0 in wad format including dust, representing the total amount of USD0 that was not matched or was left as dust.
