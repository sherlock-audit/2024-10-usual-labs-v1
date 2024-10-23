#!/usr/bin/env bash

# check if curl is installed
check_curl_is_installed() {
  if ! command -v curl &>/dev/null; then
    echo "curl could not be found. Please install curl by running:"
    echo "sudo apt-get install curl or brew install curl on macos or install it from https://curl.se/download.html"
    exit -1
  fi
}

# check if jq is installed
check_jq_is_installed() {
  if ! command -v jq &>/dev/null; then
    echo "jq could not be found. Please install jq by running:"
    echo "sudo apt-get install jq or brew install jq on macos or install it from https://stedolan.github.io/jq/download/"
    exit -1
  fi
}

check_chain_id() {
  local rpc_url="$1" # your RPC endpoint URL
  local chain_id_hex=$(curl -sS -H 'Content-Type: application/json' -d '{"jsonrpc": "2.0", "method": "eth_chainId", "params": [], "id": 1}' "$rpc_url" | jq -r '.result')
  # test if the chain id is a valid hex number
  if ! [[ "$chain_id_hex" =~ ^0x[0-9a-fA-F]+$ ]]; then
    # Chain ID is not a valid hex number
    return 1
  fi
  # remove first two characters (0x) and convert to decimal

  local chain_id_dec=$(printf '%d' "$((16#${chain_id_hex#0x}))")
  if [ "$chain_id_dec" -eq "$TENDERLY_FORK_CHAIN_ID" ]; then
    # Chain ID matches current network ID
    return 0
  else
    # Chain ID does NOT match current network ID
    return 1
  fi
}

get_fork_id_from_alias() {
  # call tenderly api to get the list of forks for the project
  FORKS_ANSWER=$(curl -s -X GET -H "x-access-key: $TENDERLY_ACCESS_KEY" https://api.tenderly.co/api/v1/account/usual-tech/project/cd/forks)
  # get the id of the fork that was created based on the alias
  TENDERLY_FORK_ID=$(echo $FORKS_ANSWER | jq -r '.simulation_forks[] | select(.alias == "'$TENDERLY_FORK_ALIAS'") | .id')
}

# function that calls tenderly web3 action manually using curl
call_action() {
  if [ -z "$TENDERLY_FORK_CHAIN_ID" ]; then
    TENDERLY_FORK_CHAIN_ID=1
  fi
  # check if we already have a fork with provided ID or alias
  if [ -n "$TENDERLY_FORK_ID" ]; then
    # check that the RPC exists and corresponds to the chain ID
    if ! check_chain_id "https://rpc.tenderly.co/fork/$TENDERLY_FORK_ID"; then
      # the provided TENDERLY_FORK_ID will be ignored because it is either incorrect or targets the wrong chainId
      TENDERLY_FORK_ID=""
    fi
  fi
  # trying to retrieve the fork id with the alias if TENDERLY_FORK_ID is still empty
  if [[ -z "$TENDERLY_FORK_ID" ]]; then
    # if the alias corresponds to an existing fork, get the fork id
    get_fork_id_from_alias
  fi
  # call tenderly web3 action that will create a fork if TENDERLY_FORK_ID is not set
  curl -s -X POST -H "x-access-key: $TENDERLY_ACCESS_KEY" -H "Content-Type: application/json" https://api.tenderly.co/api/v1/actions/$TENDERLY_WEB3_ACTION_ID/webhook -d '{"chainId":  "'$TENDERLY_FORK_CHAIN_ID'", "mnemonicIndexCount": "'$MNEMONIC_INDEX_COUNT'", "removeFork": false, "tokenAmount": "100", "forkId": "'$TENDERLY_FORK_ID'", "alias": "'$TENDERLY_FORK_ALIAS'"}' >/dev/null
  # if TENDERLY_FORK_ID is empty call tenderly api to get the list of forks for the project
  if [ -z "$TENDERLY_FORK_ID" ]; then
    # wait for 5 seconds to give time for the fork to be created
    sleep 5
    get_fork_id_from_alias
  fi
  if [ -z "$TENDERLY_FORK_ID" ]; then
    echo "Fork was not created. Please check your TENDERLY_ACCESS_KEY and TENDERLY_WEB3_ACTION_ID"
    exit -1
  fi
  TENDERLY_FORK_RPC=https://rpc.tenderly.co/fork/$TENDERLY_FORK_ID
}

# check system requirements.
check_curl_is_installed
check_jq_is_installed
# check that TENDERLY_FORK_ALIAS is set
if [[ -z "$TENDERLY_FORK_ALIAS" ]]; then
  echo "Please set TENDERLY_FORK_ALIAS environment variable to the alias of the fork you want to use."
  exit -1
fi
#  calling tenderly web3 action.
call_action
echo $TENDERLY_FORK_RPC
