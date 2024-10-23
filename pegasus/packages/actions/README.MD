# Web3 Actions

## fork-webhook : Tenderly fork actions script

This script `solidity/scripts/tenderly-action-fork.sh` is used to create a fork of a network and transfer tokens to a number of accounts. The tokens are defined in the `packages/actions/addresses/token.json` file and the whale account that will transfer the tokens is defined in the `packages/actions/addresses/whale.json` file.
If `TENDERLY_FORK_ID` is not set in the environment variables, the script will try to find it based on the `TENDERLY_FORK_ALIAS` env.

It will then call the web3 action that create the fork if `TENDERLY_FORK_ID` is not provided and transfer the tokens to the accounts .

It will then populate the `TENDERLY_FORK_RPC` and `TENDERLY_FORK_ID` environment variables with the fork id and the rpc url of the fork.

### Web3 Actions

this tenderly web3 action will fork a network, create a number of accounts from a mnemonic and transfer tokens to each account. The tokens are defined in the `packages/actions/addresses/token.json` file and the whale account that will transfer the tokens is defined in the `packages/actions/addresses/whale.json` file.
This is used to deploy the contracts or run the tests against.

to run locally, you need to have a .env file with the following variables:

copy paste the `.env.sample` file and rename it to `.env`

```bash
TENDERLY_ACCESS_KEY=
MNEMONIC=
```

MNEMONIC should be the same as the one used in the deploy contracts scripts (check packages/solidity/.env)

install the dependencies

```bash
yarn workspace @usual-money/actions install
```

and run it locally

```bash
 yarn workspace @usual-money/actions run:local
```

to deploy you need the [tenderly CLI](https://docs.tenderly.co/web3-actions/references/cli-cheatsheet) and then to login to tenderly

```bash
tenderly login
```

you can then deploy

```bash
# run within the folder containing tenderly.yaml

# Build the project (optional)
tenderly actions build

# Publish the project to Tenderly without running it (start manually)
tenderly actions publish

# Deploy the project to Tenderly Runtime (or re-deploy any changes you make)
tenderly actions deploy
```

### webhook API

description of the payload that is sent to the webhook the payload that is sent to the `https://api.tenderly.co/api/v1/actions/{web3-action-id}/webhook` endpoint

```json
{
  "chainId": 1,
  "mnemonicIndexCount": 1,
  "forkId": "7a6fc622-b751-4faa-9676-25133b40d61b",
  "removeFork": true,
  "amount": "100",
  "alias": "test"
}
```

#### chainId (optional - default: 1)

the network id of the chain that the action will be executed on
note that the action will be executed on a fork of the chain
we need to fill the files `packages/actions/addresses/token.json` and `packages/actions/addresses/whale.json` with the tokens and the whale account that can transfer this token on that network

#### mnemonicIndexCount (optional - default: 1)

the number of accounts that will be created from the mnemonic
each account will be funded with the amount specified in the `amount` field or with the max amount specified in the `packages/actions/addresses/token.json` file if it is less than the amount specified in the `amount` field.

#### forkId (optional)

the id of the fork that will be used to execute the action
If the fork does not exist, it will be created

#### removeFork (optional - default: true)

if true, the fork will be removed after the action is executed

#### tokenAmount (optional - default: 100)

the amount of tokens that will be transferred to each account
tokens are defined in the `packages/actions/addresses/token.json` file
tokens will be transferred from the whale account specified in the `packages/actions/addresses/whale.json` file

#### alias (optional)

it will be used as an alias the fork that will be created

you can call the webhook API with the following curl command. Note that the action is authenticated with the `x-access-key` header and the `ACCESS_TOKEN` is the value of the `TENDERLY_ACCESS_KEY` environment variable.

```bash
	curl -X POST \
	-H "x-access-key: $ACCESS_TOKEN" \
	-H "Content-Type: application/json" \
	https://api.tenderly.co/api/v1/actions/{web3-action-id}/webhook \
	-d '{"chainId": 1, "mnemonicIndexCount": 1, "removeFork": false, "tokenAmount": "100"}'
```

you will get a response containing the JRPC url of the fork that was created or used, the chain ID and the wallet addresses that were transferred tokens. We also have the list of tokens that were transferred to each wallet address. Finally we have the transaction receipt of the transfer transactions.

```json
{
  "rpc": "https://rpc.tenderly.co/fork/26858929-6fc2-4b0e-80ad-446ea2c5d421",
  "forkId": "26858929-6fc2-4b0e-80ad-446ea2c5d421",
  "networkId": "1",
  "wallets": ["0x411FAB2b2A2811Fa7DeE401F8822De1782561804"],
  "tokens": {
    "USDC": {
      "address": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "decimals": 6,
      "maxAmount": "100"
    },
    "DAI": {
      "address": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
      "decimals": 18,
      "maxAmount": "100"
    },
    "USDT": {
      "address": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
      "decimals": 6,
      "maxAmount": "100"
    },
    "WBTC": {
      "address": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
      "decimals": 8,
      "maxAmount": "1"
    }
  },
  "transactionsResponses": [
    {
      "hash": "0x5cdbaf9a6526ed05a9fa50ffc34872a3982c423611254abed9c7c71e4378b416",
      "type": 0,
      "accessList": null,
      "blockHash": "0xa1356e8285f99e6159c3e87d9a88483937317e0665ccc77e3b6651cbca2477fd",
      "blockNumber": 16924412,
      "transactionIndex": 0,
      "confirmations": 1,
      "from": "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
      "gasPrice": 0,
      "gasLimit": 0,
      "to": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "value": 0,
      "nonce": 20,
      "data": "0xa9059cbb000000000000000000000000411fab2b2a2811fa7dee401f8822de17825618040000000000000000000000000000000000000000000000000000000005f5e100",
      "r": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "s": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "v": 0,
      "creates": null,
      "chainId": 1,
      "wait": null
    },
    {
      "hash": "0x4b5ee9758ddebcd053ac4b97c3bb7779273713d18c44e5175a7083500ec76a7d",
      "type": 0,
      "accessList": null,
      "blockHash": "0x8819fc356f731d955b9fa01633cd02c4822e8b82b22e32956976212f89357c08",
      "blockNumber": 16924409,
      "transactionIndex": 0,
      "confirmations": 1,
      "from": "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
      "gasPrice": 0,
      "gasLimit": 0,
      "to": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
      "value": 0,
      "nonce": 18,
      "data": "0xa9059cbb000000000000000000000000411fab2b2a2811fa7dee401f8822de17825618040000000000000000000000000000000000000000000000056bc75e2d63100000",
      "r": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "s": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "v": 0,
      "creates": null,
      "chainId": 1,
      "wait": null
    },
    {
      "hash": "0x64b5d9e6e71c8f366c708b987aca6cf3b735f66b05fb70b1bc1d9feabed08042",
      "type": 0,
      "accessList": null,
      "blockHash": "0x913501479173eb06f3f8bd9bb11a228b90d1531bcd5828d2eeea12129463d309",
      "blockNumber": 16924410,
      "transactionIndex": 0,
      "confirmations": 1,
      "from": "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
      "gasPrice": 0,
      "gasLimit": 0,
      "to": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
      "value": 0,
      "nonce": 19,
      "data": "0xa9059cbb000000000000000000000000411fab2b2a2811fa7dee401f8822de17825618040000000000000000000000000000000000000000000000000000000005f5e100",
      "r": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "s": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "v": 0,
      "creates": null,
      "chainId": 1,
      "wait": null
    },
    {
      "hash": "0xd394900fba999471ec821d5199a981a15af3de8cb89e37edd565ebed91bba17f",
      "type": 0,
      "accessList": null,
      "blockHash": "0x83d53205708a6fa7b2b22ae7bf037a4bd1cd98023c78e31a8d8e6d63fc064f35",
      "blockNumber": 16924411,
      "transactionIndex": 0,
      "confirmations": 1,
      "from": "0x28C6c06298d514Db089934071355E5743bf21d60",
      "gasPrice": 0,
      "gasLimit": 0,
      "to": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
      "value": 0,
      "nonce": 6286663,
      "data": "0xa9059cbb000000000000000000000000411fab2b2a2811fa7dee401f8822de17825618040000000000000000000000000000000000000000000000000000000005f5e100",
      "r": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "s": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "v": 0,
      "creates": null,
      "chainId": 1,
      "wait": null
    },
    "0x14c9e0b002d593a03ccacd09eb328c7f1097a70420120d73576eeca1100f96d0"
  ]
}
```

## signals : receive alert signals, process them and send to telegram and signl4

that can be added as a tenderly alert destination.
The alert will be then decoded and format and sent to a telegram group where our [telegram bot](https://t.me/usual_signals_bot) will send the processed data. The bot token is defined by **TELEGRAM_BOT_ACCESS_TOKEN** in the [web3 action secrets](https://dashboard.tenderly.co/usual/cd/actions/secrets)

It is then sent to a telegram group define by **DANGER_TELEGRAM_GROUP_ID** for alerts defined as warning or danger and **TELEGRAM_GROUP_ID** for others in the [web3 action storage](https://dashboard.tenderly.co/usual/cd/actions/storage).

We check all the addresses involved in the transaction that triggered against the **addressToName** json table. When a token is involved we format the value based on the decimals store in the **addressToDecimals** table.

if the alert category is **Danger** and the transaction timestamp is between `sign4lDangerAlertStartHour` and `sign4lDangerAlertEndHour` UTC, we also send the alert on the [signl4 alerting group](https://account.signl4.com/) through the webhook defined by `sign4lWebHookForDangerAlert` storage key

## testnet-heartbeat : Action listens to new block and send transaction from MNEMONIC first address to force fork sync

From action secret `MNEMONIC` we derive the first address and send a transaction of one wei to the same address.
This action is triggerred every 300 blocks on mainnet.
This will force virtual testnet to sync with mainnet. The list of virtual testnet is defined in the action storage `virtualTestNetAdminRPCToKeepAlive`.

## LiquidityPending : receive alert when USDC is deposited. With the orderId we check after 10 blocks that the order has been taken if not it sends a message to telegram

The action is triggered by a mainnet transaction that emits the `Deposit` event of the `SwapperEngine` contract.
The action will then check the `orderId` of the deposit and wait for 10 blocks to check if the order has been taken.
If the order has not been taken, it will send a message to the telegram group defined by the `LIQUIDITY_TELEGRAM_GROUP_ID` in the [web3 action storage](https://dashboard.tenderly.co/usual/cd/actions/storage).
It uses `MAINNET_JSON_RPC` to get the order details.
