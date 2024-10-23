#!/usr/bin/env bash

# expect args like local-env-setup.sh http://localhost:8545 .env FinalConfig.s.sol FinalConfigScript 0x28C6c06298d514Db089934071355E5743bf21d60

DEPLOYMENT_RPC_URL="$1"
if [ -z "$DEPLOYMENT_RPC_URL" ]; then
  DEPLOYMENT_RPC_URL="http://localhost:8545"
fi

ENV_FILE="$2"
if [ -z "$ENV_FILE" ]; then
  ENV_FILE=".env"
fi

# assign script second arguments to env LAST_DEPLOY_SCRIPT_FILENAME
LAST_DEPLOY_SCRIPT_FILENAME="$3"
if [ -z "$LAST_DEPLOY_SCRIPT_FILENAME" ]; then
  LAST_DEPLOY_SCRIPT_FILENAME="FinalConfig.s.sol"
fi

LAST_DEPLOY_SCRIPT_CONTRACT_NAME="$4"
# if LAST_DEPLOY_SCRIPT is empty then use FinalConfigScript
if [ -z "$LAST_DEPLOY_SCRIPT_CONTRACT_NAME" ]; then
  LAST_DEPLOY_SCRIPT_CONTRACT_NAME="FinalConfigScript"
fi

STABLECOIN_WHALE="$5"
# if STABLECOIN_WHALE is empty then use Binance 14
if [ -z "$STABLECOIN_WHALE" ]; then
  STABLECOIN_WHALE=0x28C6c06298d514Db089934071355E5743bf21d60
fi

# JSON array of major stablecoin name, addresses and their decimals
STABLECOINS_JSON='[{"name":"WETH","address":"0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2","decimals":18,"maxAmount":"10000000000000000000"},{"name":"WBTC","address":"0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599","decimals":8,"maxAmount":"100000000"},{"name":"USDT","address":"0xdAC17F958D2ee523a2206206994597C13D831ec7","decimals":6},{"name":"USDC","address":"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48","decimals":6},{"name":"DAI","address":"0x6b175474e89094c44da98b954eedeac495271d0f","decimals":18,"maxAmount":"100000000000000000000"}]'

set -o allexport
source $ENV_FILE
set +o allexport

# check if .env file exists
check_env_file_exists() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "env file $ENV_FILE does not exist. Please create it by copying .env.example and filling in the required values."
    exit 1
  fi
}

# check if jq is installed
check_jq_is_installed() {
  if ! command -v jq &>/dev/null; then
    echo "jq could not be found. Please install it by following the instructions here: https://stedolan.github.io/jq/download/"
    exit 1
  fi
}

# check if curl is installed
check_curl_is_installed() {
  if ! command -v curl &>/dev/null; then
    echo "curl could not be found. Please install it by following the instructions here: https://curl.se/download.html"
    exit 1
  fi
}

# check if lsof is installed
check_lsof_is_installed() {
  if ! command -v lsof &>/dev/null; then
    echo "lsof could not be found. Please install it by following the instructions here: https://lsof.readthedocs.io/en/latest/getting-started/"
    exit 1
  fi
}

# check if forge is installed
check_forge_is_installed() {
  if ! command -v forge &>/dev/null; then
    echo "forge could not be found. Please install it by following the instructions here: https://book.getfoundry.sh/getting-started/installation"
    exit 1
  fi
}

wait_for_anvil_to_start() {
  # display loading animation
  echo "please wait for anvil to start..."
  spinner=(Ooooo oOooo ooOoo oooOo ooooO)
  while ! cast bn &>/dev/null; do
    for i in "${spinner[@]}"; do
      echo -ne "\r$i"
      sleep 0.1
    done
  done
  echo -ne "\r"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinner=(Ooooo oOooo ooOoo oooOo ooooO)
   
    while ps -p $pid > /dev/null 2>&1; do
      for i in "${spinner[@]}"; do
        echo -ne "\r$i"
        sleep 0.1
      done
    done
   echo -ne "\r"
}


check_anvil_is_running() {
  ANVIL_CONTAINER_ID=$(docker container ls --filter "publish=8545/tcp" --latest --quiet)
  if ! [ -z "$ANVIL_CONTAINER_ID" ]; then
    echo "Anvil is running in Docker container: $ANVIL_CONTAINER_ID."
    wait_for_anvil_to_start
    return
  fi

  ANVIL_PID=$(lsof -t -i:8545)
  if [ -z "$ANVIL_PID" ]; then
    echo "Anvil is not running. will start now."
    yarn start:anvil &>/dev/null &
    wait_for_anvil_to_start
  else
    echo "Anvil is running with PID: $ANVIL_PID. Do you want to kill it? [y/n]"
    read -r kill_anvil
    if [ "$kill_anvil" = "y" ]; then
      kill -9 $ANVIL_PID
      echo "Process killed. Restarting anvil."
      yarn start:anvil &>/dev/null &
      wait_for_anvil_to_start
    fi
  fi
}

# retrieve address at index 2 on the MNEMONIC seed
get_addresses() {
  ACCOUNTS=$(cast rpc eth_accounts -r $DEPLOYMENT_RPC_URL | jq)
  ACC1=$(echo $ACCOUNTS | jq -r --argjson MNEMONIC_INDEX $MNEMONIC_INDEX '.[$MNEMONIC_INDEX]')
  ACC2=$(echo $ACCOUNTS | jq -r --argjson MNEMONIC_INDEX $((MNEMONIC_INDEX + 1)) '.[$MNEMONIC_INDEX]')
  ACC3=$(echo $ACCOUNTS | jq -r --argjson MNEMONIC_INDEX $((MNEMONIC_INDEX + 2)) '.[$MNEMONIC_INDEX]')
  ACC4=$(echo $ACCOUNTS | jq -r --argjson MNEMONIC_INDEX $((MNEMONIC_INDEX + 3)) '.[$MNEMONIC_INDEX]')
  ACC5=$(echo $ACCOUNTS | jq -r --argjson MNEMONIC_INDEX $((MNEMONIC_INDEX + 4)) '.[$MNEMONIC_INDEX]')
  ACC6=$(echo $ACCOUNTS | jq -r --argjson MNEMONIC_INDEX $((MNEMONIC_INDEX + 5)) '.[$MNEMONIC_INDEX]')
}

send_stablecoins_to_accounts() {
  cast rpc anvil_impersonateAccount $STABLECOIN_WHALE -r $DEPLOYMENT_RPC_URL &>/dev/null
  # send stablecoins to accounts
  for i in $(echo $STABLECOINS_JSON | jq -r '.[] | @base64'); do
    _jq() {
      echo ${i} | base64 --decode | jq -r ${1}
    }
    TOKEN_NAME=$(_jq '.name')
    TOKEN_ADDRESS=$(_jq '.address')
    TOKEN_DECIMALS=$(_jq '.decimals')
    MAX_AMOUNT=$(_jq '.maxAmount')
    if [ "$MAX_AMOUNT" = "null" ]; then
      # if decimals is 18 then just add the string "00000000000000000000"
      if [ "$TOKEN_DECIMALS" = "18" ]; then
        AMOUNT=1000000000000000000000000
      else
        AMOUNT=$((100 * 10 ** $TOKEN_DECIMALS))
      fi
    else
      AMOUNT=$MAX_AMOUNT
    fi
    echo "sending $AMOUNT $TOKEN_NAME."
    cast send --unlocked $TOKEN_ADDRESS --from $STABLECOIN_WHALE "transfer(address,uint256)(bool)" $ACC1 $AMOUNT >/dev/null
    cast send --unlocked $TOKEN_ADDRESS --from $STABLECOIN_WHALE "transfer(address,uint256)(bool)" $ACC2 $AMOUNT >/dev/null
    cast send --unlocked $TOKEN_ADDRESS --from $STABLECOIN_WHALE "transfer(address,uint256)(bool)" $ACC3 $AMOUNT >/dev/null
    cast send --unlocked $TOKEN_ADDRESS --from $STABLECOIN_WHALE "transfer(address,uint256)(bool)" $ACC4 $AMOUNT >/dev/null
  done
  cast rpc anvil_stopImpersonatingAccount $STABLECOIN_WHALE -r $DEPLOYMENT_RPC_URL &>/dev/null
}

# function that will retrieve an array of all the contracts address and name deployed by the deploy script in the file $LAST_DEPLOY_SCRIPT/$CHAIN_ID/latest.json inside the array transactions where transactionType == "CREATE" get the contractAddress and the contractName
get_deployed_contracts() {
  echo "getting deployed contracts after $LAST_DEPLOY_SCRIPT_FILENAME ."
  CONTRACTS=$(cat broadcast/$LAST_DEPLOY_SCRIPT_FILENAME/$CHAIN_ID/run-latest.json | jq -r '.transactions[] | select(.transactionType == "CREATE" or .transactionType == "CREATE2") | {address: .contractAddress, name: .contractName}')
}

# function that takes a hexadecimal number as input and returns the decimal number
hex_to_dec() {
  ## we need to remove the first to character 0x from the hex number
  HEX_NUMBER=${1:2}
  ## convert the hex number to decimal 
  echo $((16#$HEX_NUMBER)) 
}

# function that will advance the time by 100 seconds
advance_time() {
  ## get the current block number by extracting the field result from the json response with jq
  BLOCK_NUMBER=$(curl -H "Content-Type: application/json" -X POST --data \
          '{"id":1337,"jsonrpc":"2.0","method":"eth_blockNumber","params":[]}' \
          $DEPLOYMENT_RPC_URL | jq -r '.result') 
  ## get the current timestamp by calling eth_getBlockByNumber with BLOCK_NUMBER variable as params extracting the field result from the json response with jq
  TIMESTAMP_CURRENT_HEX=$(curl -H "Content-Type: application/json" -X POST --data \
          '{"id":1337,"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["'$BLOCK_NUMBER'", true]}' \
          $DEPLOYMENT_RPC_URL | jq -r '.result.timestamp') 
  # convert the hex timestamp to decimal
  TIMESTAMP_CURRENT=$(hex_to_dec $TIMESTAMP_CURRENT_HEX) 
  ## add 86400 seconds to the current timestamp
  TIMESTAMP_CURRENT=$(($TIMESTAMP_CURRENT + 100))   
  ## mine a block with this timestamp      
  curl -H "Content-Type: application/json" -X POST --data \
          '{"id":1337,"jsonrpc":"2.0","method":"evm_mine" ,"params":['$TIMESTAMP_CURRENT']}' \
          $DEPLOYMENT_RPC_URL
}

echo "check system requirements..."
check_jq_is_installed
check_curl_is_installed
check_lsof_is_installed
check_forge_is_installed
check_env_file_exists

# check if anvil is running and prompt a message to start it if not
echo "check anvil is running..."
check_anvil_is_running
echo "$DEPLOYMENT_RPC_URL is the rpc url"
get_addresses

# go through all tokens and send to accounts
# send_stablecoins_to_accounts

echo "$ACC1 is the alice address"
echo "$ACC2 is the bob address"
echo "$ACC3 is the deployer address"
echo "$ACC4 is the usual address"
echo "$ACC5 is the hashnote address"

echo "### Cleanup"
forge clean

# Deploys Protocol to Anvil Localchain it will use MNEMONIC_INDEX from .env file
echo "### Deploy contracts"
forge script FinalConfigScript --broadcast --rpc-url $DEPLOYMENT_RPC_URL --unlocked --sender 0x411fab2b2a2811fa7dee401f8822de1782561804 --json &
pid1=$!
echo "Sending transactions... waiting for process pid $pid1 to finish..."
wait $pid1


echo "### Whitelist accounts for USYC"
forge script WhitelistUSYCScript --broadcast --rpc-url $DEPLOYMENT_RPC_URL --unlocked --sender 0x411fab2b2a2811fa7dee401f8822de1782561804 &
pid1=$!
echo "Sending transactions... waiting for process pid $pid1 to finish..."
wait $pid1

echo "### Fund USDC"
forge script FundAccountWithUSDCScript --broadcast --rpc-url $DEPLOYMENT_RPC_URL --unlocked --sender 0x411fab2b2a2811fa7dee401f8822de1782561804 &
pid1=$!
echo "Sending transactions... waiting for process pid $pid1 to finish..."
wait $pid1

echo "### Fund USDT"
forge script FundAccountWithUSDTScript --broadcast --rpc-url $DEPLOYMENT_RPC_URL --unlocked --sender 0x411fab2b2a2811fa7dee401f8822de1782561804 &
pid1=$!
echo "Sending transactions... waiting for process pid $pid1 to finish..."
wait $pid1

echo "### Fund USYC" 
forge script FundAccountWithUSYCScript --broadcast --rpc-url $DEPLOYMENT_RPC_URL --unlocked --sender 0x411fab2b2a2811fa7dee401f8822de1782561804 &
pid1=$!
echo "Sending transactions... waiting for process pid $pid1 to finish..."
wait $pid1

## increase time to make the USD0++ mintable
echo "### Increase Time by 100s"
advance_time 

echo "### Deploy Morpho Market" 
forge script FundMorphoPoolScript --broadcast --rpc-url $DEPLOYMENT_RPC_URL --unlocked --sender 0x411fab2b2a2811fa7dee401f8822de1782561804 &
pid1=$!
echo "Sending transactions... waiting for process pid $pid1 to finish..."
wait $pid1

# get the deployed address
get_deployed_contracts
echo $CONTRACTS | jq
