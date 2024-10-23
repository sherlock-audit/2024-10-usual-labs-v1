# Upgrade Script Guide

This guide explains the steps to follow when calling the script between P1 and P14 inside the `Upgrade.s.sol`.

## Prerequisites

- Ensure you have [Foundry](https://github.com/gakonst/foundry) installed.
- Navigate to the project directory.

## Steps

1. **Navigate to the Script Directory**

   ```sh
   cd /home/zgo/work/src/github.com/usual-dao/pegasus/packages/solidity/scripts/deployment
   ```

2. **Compile the Contracts**

   ```sh
   forge build
   ```

## Test with a Mainnet fork

### Fund the Deployer Address and Proxy Admin

Before running the upgrade script, ensure that both the deployer address and the proxy admin have sufficient funds to cover gas fees on the mainnet fork.

1. **Create a Mainnet Fork on Tenderly**

   - Log in to your [Tenderly](https://tenderly.co/) account.
   - Navigate to the "Forks" section and create a new fork of the Ethereum mainnet.
   - Copy the fork URL provided by Tenderly.

2. **Fund the Deployer Address**

   - Transfer funds from another account to the deployer address. If you want to use a mnemonic file, you can create a file inside the solidity folder (e.g., `mnemonic`) and call the script like this:

   ```sh
   forge clean && forge script scripts/deployment/Upgrade.s.sol --tc P10 -f <YOUR_RPC_URL> --mnemonic-paths mnemonic --broadcast --slow
   ```

3. **Fund the Proxy Admin**

   - Similarly, ensure the proxy admin address has enough funds to perform the necessary transactions.

4. **Run the Upgrade Scripts on Testnet**

   ```sh
   forge clean && forge script scripts/deployment/Upgrade.s.sol --tc P10 -f <YOUR_RPC_URL> --mnemonic-paths mnemonic --broadcast --slow
   ```

   execute the requested transactions on the mainnet fork impersonating the multisig admin.
   you can either use the tenderly RPC builder, select `eth_sendTransaction` and paste the `selector and encoded data` output inside the data field, or use the cast command with the same data i.e. calling `upgradeAndCall` on USD0 proxy admin from the proxy admin multisig.

   ```sh
    cast send -r https://virtual.mainnet.rpc.tenderly.co/<YOUR_RPC_URL> -f 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16 --unlocked 0xC15091D3478296fD522B2807a9541578910DCC41 0x9623609d00000000000000000000000073a15fed60bf67631dc6cd7bc5b6e8da8190acf50000000000000000000000001859f8a5702d88fb894c740db1c519305c9d2280000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000045cd8a76b00000000000000000000000000000000000000000000000000000000
   ```

5. **Verify the Deployment**

   - Check the output logs for any errors.
   - Check the transaction on the tenderly virtual chain.
   - Copy paste the newly deployed addresses into the verification script and run it.

     ```sh
         forge clean && forge script scripts/deployment/Verification.s.sol -f <YOUR_RPC_URL>
     ```

### Notes

- Replace `<YOUR_RPC_URL>` with your actual RPC URL.
- Ensure you have the necessary private keys and environment variables set up for deployment.

By following these steps, you can successfully call the script and perform the upgrade.

## Deploy on Mainnet

Once you have tested the upgrade on a mainnet fork and verified that everything works as expected, you can proceed to deploy the upgrade on the actual Ethereum mainnet.

1. **Prepare for Deployment**

   - Ensure that the deployer address and the proxy admin have sufficient ETH to cover gas fees.
   - Double-check all contract addresses and parameters to avoid any mistakes.

2. **Run the Upgrade Script**

repeat these steps for each of the contract inside the upgrade script.

- Execute the upgrade script on the mainnet

```sh
forge clean && forge script scripts/deployment/Upgrade.s.sol --tc P10 -f <YOUR_MAINNET_RPC_URL> --ledger --etherscan-api-key <KEY> --verifier etherscan  --broadcast
```

- Check the output logs for any errors and verify the transactions on etherscan. Assess that the contract has been verified on etherscan.
- Open the multisig safe enter the transaction as displayed in the logs and confirm it.
- Wait for the transactions to be included and verify the transactions on etherscan.
- Repeat the above steps for each of the contracts inside the upgrade script. next call will be
  ```sh
  forge clean && forge script scripts/deployment/Upgrade.s.sol --tc P11 -f <YOUR_MAINNET_RPC_URL> --ledger --etherscan-api-key <KEY> --verifier etherscan  --broadcast
  ```

3. **Verify the Deployment**

After the script execution, fill and run the verify script with the newly deployed addresses. You have to update the new implementation addresses and the new proxy in the `Verification.s.sol` script.

```sh
forge clean && forge script scripts/deployment/Verification.s.sol -f <YOUR_MAINNET_RPC_URL>
```

4. **Monitor Transactions**

   - Check the transaction status on [Etherscan](https://etherscan.io/).
   - Ensure that all transactions are successfully mined and there are no errors.

5. **Code and Bytecode verification**

   - Verify that the source code of the new implementation contract matches the source code on etherscan. If not you can use the forge verify-code command to verify the code.

   ```sh
   forge verify-code --rpc-url <RPC_URL> --etherscan-api-key <KEY>  <CONTRACT_ADDRESS_TO_VERIFY> <path>:<contractname> --watch
   ```

   - Verify that the bytecode of the new implementation contract matches the bytecode on etherscan.

   ```sh
   forge verify-bytecode --rpc-url <RPC_URL> --etherscan-api-key <KEY>  <CONTRACT_ADDRESS_TO_VERIFY> <path>:<contractname>
   ```

6. **Post-Deployment Checks**

   - Verify that the upgraded contracts are functioning as expected.
   - Perform any additional tests to ensure the stability and correctness of the deployment.

By following these steps, you can deploy the upgrade on the Ethereum mainnet with confidence.
