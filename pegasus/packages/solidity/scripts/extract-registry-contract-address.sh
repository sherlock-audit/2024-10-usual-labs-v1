#!/usr/bin/env bash

# check if jq is installed
check_jq_is_installed() {
  if ! command -v jq &>/dev/null; then
    echo "jq could not be found. Please install jq by running:"
    echo "sudo apt-get install jq or brew install jq on macos or install it from https://stedolan.github.io/jq/download/"
    exit -1
  fi
}

# function that calls tenderly web3 action manually using curl
extract_registry_contract_address() {
  if [ -z "$TENDERLY_BROADCAST_FOLDER" ]; then
    TENDERLY_BROADCAST_FOLDER="broadcast"
  fi

  # Find the folder with a name that ends with "FinalConfig.s.sol"
  folder=$(find $TENDERLY_BROADCAST_FOLDER -type d -name "FinalConfig.s.sol" -print -quit)

  # Check if a folder was found
  if [ -z "$folder" ]; then
    echo "FinalConfig Folder not found"
    exit -1
  fi
  # find the registry contract address inside the broadcast folder inside the folder that ends with FinalConfig.s.sol and inside the folder $TENDERLY_FORK_CHAIN_ID/run-latest.json file find inside the transactions array the contractAddress field for the lement with the "transactionType" equal to "CREATE" and "contractName" equal to  "RegistryContract"

  REGISTRY_CONTRACT_ADDRESS=$(cat $folder/$TENDERLY_FORK_CHAIN_ID/run-latest.json | jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "RegistryContract") | .contractAddress')

}

# check system requirements.
check_jq_is_installed
# check that TENDERLY_FORK_CHAIN_ID is set
if [[ -z "$TENDERLY_FORK_CHAIN_ID" ]]; then
  echo "Please set TENDERLY_FORK_CHAIN_ID environment variable to the chain id where the registry contract has been deployed."
  exit -1
fi
#  calling tenderly web3 action.
extract_registry_contract_address
echo $REGISTRY_CONTRACT_ADDRESS
