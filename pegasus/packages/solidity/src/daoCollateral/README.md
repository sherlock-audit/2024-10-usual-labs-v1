# High-Level Overview

`daoCollateral.sol` is a smart contract designed to facilitate the swapping of Real World Assets (RWAs) for stablecoins (i.e USYC=>USD0) and other external assets within our DAO. This contract enables users to swap their Real World Assets (currently available with USYC) either for our stablecoin (USD0) or for USDC. Additionally, it provides the functionality to redeem USD0 tokens for Real World Assets (i.e USD0=>USYC).

## Contract Summary
The contract provides the following main functions:
- **Swap:** Facilitates the conversion of Real World Assets (RWAs), represented as USYC tokens, into the DAO's stablecoin (USD0). Upon initiating this function, users exchange their USYC tokens for USD0 stablecoins directly.

- **Redeem:** Allows users to redeem their USD0 stablecoins. By invoking this function, users exchange their USD0 stablecoins for RWAs, represented as USYC tokens, at the current exchange rate.

- **SwapRWAtoStbc:** Enables users to swap their RWAs (USYC) for USDC. Additionally, this function mints the equivalent amount of USD0 stablecoins and transfers them to the SwapperContract for further processing.

The contract also includes utility functions:
- **redeemFee:** This function retrieves the current redemption fee set by the DAO. Users can query this function to understand the fee percentage applied when redeeming USD0 stablecoins for RWAs.

- **isCBROn:** Returns a boolean value indicating whether the Counter Bank Run (CBR) mechanism is activated. The CBR mechanism is designed to manage potential bank runs by users and can be toggled on or off by the DAO administrators.

- **isRedeemPaused:** Indicates whether the redeem functionality is currently paused. When this function returns true, users are unable to redeem USD0 stablecoins for RWAs, typically due to maintenance or other operational reasons.

- **isSwapPaused:** Returns a boolean value indicating whether the swap functionality is currently paused. When this function returns true, users are unable to convert RWAs into USD0 stablecoins, usually due to maintenance or other operational reasons.

## Inherited Contracts

- **Initializable (OZ):** Utilized to provide a safe and controlled way to initialize the contract's state variables. It ensures that the contract's initializer function can only be called once, preventing accidental or malicious reinitialization.

- **ReentrancyGuardUpgradeable (OZ):** Employed to protect against reentrancy attacks. It provides a modifier that can be applied to functions to prevent them from being called recursively or from being called from other functions that are also protected by the same guard.

- **PausableUpgradeable (OZ):** The `PausableUpgradeable` contract allows the contract administrators to pause certain functionalities in case of emergencies or necessary maintenance. It provides functions to pause and unpause specific operations within the contract to ensure user protection and contract stability.

- **NoncesUpgradeable (OZ):** This contract provides functionality for managing nonces, which are used to prevent replay attacks in certain operations. Nonces are incremented with each transaction to ensure uniqueness and prevent unauthorized reuse of transactions.

- **EIP712Upgradeable (OZ):** Implements the Ethereum Improvement Proposal (EIP) 712 standard, defining a domain-specific message signing scheme. It enables contracts to produce and verify typed data signatures, enhancing the security of contract interactions.

## Functionality Breakdown

The DaoCollateral contract facilitates various operations related to swapping and redeeming Real-World Asset (USYC) tokens, USD0 stablecoins, and USDC. The contract’s functionality can be broken down into the following key components:

1. **Swap RWA to USD0**
   - **Sanity Check:**
     - Validates the RWA token and the amount to ensure they are supported and non-zero or too high.
   - **Price Quotation:**
     - Retrieves the USD price quote for the specified amount of RWA tokens using the oracle.
   - **Token Transfer:**
     - Transfers the specified amount of RWA tokens from the user to the treasury.
   - **Stablecoin Minting:**
     - Mints the equivalent amount of USD0 stablecoins based on the quoted price and transfers them to the user.

2. **Swap RWA to USDC**
   - **Sanity Check:**
     - Validates the RWA token and the amount to ensure they are supported and non-zero or too high.
   - **Price Quotation:**
     - Retrieves the USD price quote for the specified amount of RWA tokens using the oracle.
   - **Token Transfer:**
     - Transfers the specified amount of RWA tokens from the user to the treasury.
   - **Intent-Based Swapping:**
     - Facilitates the swap of RWA tokens for USDC using the SwapperEngine order matching system.
   - **Order Matching Process:**
     - Uses the SwapperEngine contract to match the USD0 amount equivalent of the RWA tokens against existing orders and swap for USDC.
     - Verifies that the caller has sufficient USD0 balance and allowance to cover the required amount.
     - Iterates through provided order IDs and matches the requested amount against active orders, with options for partial matching.

3. **Redeem**
   - **Sanity Check:**
     - Validates the USD0 amount to ensure it is supported and non-zero.
   - **Price Quotation:**
     - Retrieves the equivalent amount of RWA tokens for the specified amount of USD0 stablecoins using the oracle.
   - **Stablecoin Burning:**
     - Burns the specified amount of USD0 stablecoins from the user.
   - **Token Transfer:**
     - Transfers the equivalent amount of RWA tokens from the treasury to the user.
   - **Fee Calculation:**
     - Calculates the transaction fee as a percentage of the USD0 amount.
   - **Fee Transfer:**
     - Mints the calculated fee amount in USD0 stablecoins and transfers it to the treasury.

## Security Analysis
### Method: swap
Exemple Tx : [0x8fa19cb9012411cbd46cb27dead90a428e3dce14e9b2199f7ad565ce5daea33c](https://etherscan.io/tx/0x8fa19cb9012411cbd46cb27dead90a428e3dce14e9b2199f7ad565ce5daea33c)
```rust
1 function swap(...) public nonReentrant 
2	 whenSwapNotPaused 
3	 whenNotPaused
  {
4	uint256 wadQuoteInUSD = _swapCheckAndGetUSDQuote(rwaToken, amount);
5	if (wadQuoteInUSD < minAmountOut) {
6		revert AmountTooLow();
	}
7	_transferRWATokenAndMintStable(rwaToken, amount, wadQuoteInUSD);
8	emit Swap(msg.sender, rwaToken, amount, wadQuoteInUSD);
    }
```
1. The function is defined as `public`, allowing it to be called externally. The `nonReentrant` modifier ensures protection against reentrancy attacks, preventing recursive calls.
2. The `whenSwapNotPaused` modifier ensures that the function can only be executed when the swap functionality is not paused, adding a layer of administrative control.
3. The `whenNotPaused` modifier ensures that the function can only be executed when the entire contract is not paused, providing an additional safety mechanism.
6. Calls the `_swapCheckAndGetUSDQuote` function to get the USD equivalent quote of the RWA token amount in WAD format (18 decimals), and stores the result in `wadQuoteInUSD`.
7. Evaluates whether the USD equivalent amount (`wadQuoteInUSD`) is less than the minimum acceptable amount (`minAmountOut`).
8. If the condition is true, the function reverts the transaction with an `AmountTooLow` error, stopping the swap from proceeding.
9. Calls the `_transferRWATokenAndMintStable` internal function to manage the transfer of RWA tokens and the minting of stablecoins based on the USD equivalent amount.
10. Emits a `Swap` event, logging details of the swap including the caller’s address (`msg.sender`), the RWA token address, the amount of RWA tokens swapped, and the USD equivalent amount. 

### Method: redeem
```rust
function redeem(...) external
 1	nonReentrant
 2	whenRedeemNotPaused
 3	whenNotPaused
 {
 4	if (amount ==  0) {
 5		revert AmountIsZero();
  	} 
 6	if (!_daoCollateralStorageV0().tokenMapping.isUsd0Collateral(rwaToken)) {
 7		revert InvalidToken();
  	}
 8	uint256 stableFee = _transferFee(amount, rwaToken);
 9	uint256 returnedCollateral = _burnStableTokenAndTransferCollateral(rwaToken, amount, stableFee);
10	if (returnedCollateral < minAmountOut) {
11		revert AmountTooLow();
  	}
12	emit Redeem(msg.sender, rwaToken, amount, returnedCollateral, stableFee);
}
```
1. The function is protected against reentrancy attacks by using the `nonReentrant` modifier, ensuring that the function cannot be called recursively or from other functions that are also protected by the same guard.
2. The `whenRedeemNotPaused` modifier checks if the redeem functionality is not paused, preventing the function from executing if the redeeming process is temporarily disabled.
3. The `whenNotPaused` modifier ensures that the overall contract is not paused, preventing the function from executing if the contract is temporarily disabled.
4. Checks if the `amount` specified for redemption is zero.
5. Reverts the transaction with the `AmountIsZero` error if the specified amount is zero, as zero-value transactions are not allowed.
8. Checks if the specified `rwaToken` is a valid USD0 collateral token using the `isUsd0Collateral` function from the `tokenMapping` object.
9. Reverts the transaction with the `InvalidToken` error if the specified `rwaToken` is not a recognized collateral token, ensuring that only valid tokens can be redeemed.
10. Calls the `_transferFee` function to calculate and transfer the fee for the redemption, and stores the fee amount in the `stableFee` variable. 
11. Calls the `_burnStableTokenAndTransferCollateral` function to burn the specified amount of stablecoins and transfer the equivalent collateral to the user, accounting for the `stableFee`. The returned collateral amount is stored in the `returnedCollateral` variable.
12. Checks if the amount of collateral returned (`returnedCollateral`) is less than the minimum amount specified (`minAmountOut`).
13. Reverts the transaction with the `AmountTooLow` error if the returned collateral amount is less than the specified minimum, ensuring that the user receives at least the minimum expected amount.
14. Emits the `Redeem` event, logging the details of the redemption, including the caller's address, the `rwaToken`, the amount redeemed, the collateral returned, and the fee charged.

### Method: swapRWAtoStbc
```rust
function  swapRWAtoStbc(...) external 
1	nonReentrant 
2	whenNotPaused 
3	whenSwapNotPaused 
{
4	_swapRWAtoStbc(msg.sender, rwaToken, amountInTokenDecimals, partialMatching, orderIdsToTake, approval);
}
```
1. The function is protected against reentrancy attacks by using the `nonReentrant` modifier, ensuring that the function cannot be called recursively or from other functions that are also protected by the same guard.
2. The `whenNotPaused` modifier ensures that the overall contract is not paused, preventing the function from executing if the contract is temporarily disabled.
3. The `whenSwapNotPaused` modifier checks if the swap functionality is not paused, preventing the function from executing if the swapping process is temporarily disabled.
4. Calls the `_swapRWAtoStbc` internal function, passing in the caller's address (`msg.sender`), the specified `rwaToken`, the amount in token decimals (`amountInTokenDecimals`), whether partial matching is allowed (`partialMatching`), the array of order IDs to match against (`orderIdsToTake`), and the approval status (`approval`). This encapsulates the main logic for the swap operation within an internal function.

### Method: swapRWAtoStbcIntent
Exemple Tx : [0x1de813625ec5aa3fc3a236e493ca0a6e873a9d1056afe6709e5de4a04abfcd42](https://etherscan.io/tx/0x1de813625ec5aa3fc3a236e493ca0a6e873a9d1056afe6709e5de4a04abfcd42)
```rust
function swapRWAtoStbcIntent(...) external 
1	nonReentrant 
2	whenNotPaused 
3	whenSwapNotPaused 
{
4	if (block.timestamp > intent.deadline) {
5		revert ExpiredSignature(intent.deadline);
	}
6	if (approval.deadline != intent.deadline) {
7		revert InvalidDeadline(approval.deadline, intent.deadline);
	}
8	uint256 nonce = _useNonce(intent.recipient);
	bytes32 structHash = keccak256(
9		abi.encode(INTENT_TYPE_HASH,intent.recipient,intent.rwaToken,intent.amountInTokenDecimals,nonce,intent.deadline)
	);  
10	bytes32  hash  = _hashTypedDataV4(structHash);
11	bytes  memory signature = intent.signature;
12	if (!SignatureChecker.isValidSignatureNow(intent.recipient, hash, signature)) {
13		revert InvalidSigner(intent.recipient);
	}
14	(uint256 amountInTokenDecimals, uint256 amountInUSD) = _swapRWAtoStbc(intent.recipient,intent.rwaToken,intent.amountInTokenDecimals,partialMatching,orderIdsToTake,approval);
15	emit IntentMatched(intent.recipient, nonce, intent.rwaToken, amountInTokenDecimals, amountInUSD);
}
```
1. The function is protected against reentrancy attacks by using the `nonReentrant` modifier, ensuring that the function cannot be called recursively or from other functions that are also protected by the same guard.
2. The `whenNotPaused` modifier ensures that the overall contract is not paused, preventing the function from executing if the contract is temporarily disabled.
3. The `whenSwapNotPaused` modifier checks if the swap functionality is not paused, preventing the function from executing if the swapping process is temporarily disabled.
4. Checks if the current block timestamp is greater than the deadline specified in the `intent`.
5. If the deadline has passed, the function reverts with an `ExpiredSignature` error.
6. Ensures the `approval` deadline matches the `intent` deadline. 
7. If they do not match, the function reverts with an `InvalidDeadline` error.
8. Uses the `_useNonce` function to retrieve and increment the nonce associated with the recipient address from the `intent`.
9. Creates a hash of the `intent` data using the `keccak256` hashing function. The `abi.encode` function encodes the data to be hashed, which includes the recipient, RWA token, amount in token decimals, nonce, and deadline.
10. Generates an EIP-712 compliant hash using `_hashTypedDataV4`, which includes the `structHash` created in the previous step.
11. Retrieves the signature from the `intent`.
12. Validates the signature using the `SignatureChecker.isValidSignatureNow` function. 
13. If the signature is not valid, the function reverts with an `InvalidSigner` error.
14. Calls the `_swapRWAtoStbc` internal function, passing in the recipient, RWA token, amount in token decimals, partial matching flag, order IDs to take, and approval. This performs the main logic of the swap.
15. Emits the `IntentMatched` event, logging the recipient, nonce, RWA token, amount in token decimals, and the amount in USD from the swap.