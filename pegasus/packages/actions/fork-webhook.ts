import { ActionFn, Context, Event, WebhookEvent } from "@tenderly/actions";
import { BigNumber, ethers } from "ethers";
import { tenderlyApi } from "./tenderly-api";
import { abi as TokenAbi } from "./abi/token.json";
import * as Whales from "./addresses/whale.json";
import * as TokensByChainId from "./addresses/token.json";

const TENDERLY_USERNAME = "usual";
const TENDERLY_PROJECT_SLUG = "cd";
const tokenAbi = new ethers.utils.Interface(TokenAbi);

// can be use to simulate a transaction
async function simulate(
  tokenAddress: string,
  walletAddress: string,
  amount: BigNumber
) {
  const SIMULATE_API = `https://api.tenderly.co/api/v1/account/${TENDERLY_USERNAME}/project/${TENDERLY_PROJECT_SLUG}/simulate`;
  const provider = new ethers.providers.JsonRpcProvider(
    "https://arb1.arbitrum.io/rpc"
  );
  const signer = provider.getSigner();
  const token = new ethers.Contract(tokenAddress, TokenAbi, signer);
  const tx = await token.transfer(walletAddress, amount);
  await tx.wait();
  return tx;
}

async function setBalance(
  forkProvider: ethers.providers.JsonRpcProvider,
  walletAddresses: any[],
  amount: BigNumber
) {
  return await forkProvider.send("tenderly_setBalance", [
    walletAddresses,
    ethers.utils.hexValue(amount),
  ]);
}

async function addBalance(
  forkProvider: ethers.providers.JsonRpcProvider,
  walletAddresses: any[],
  amount: BigNumber
) {
  return await forkProvider.send("tenderly_addBalance", [
    walletAddresses,
    ethers.utils.hexValue(amount),
  ]);
}
async function dealERC20(
  forkProvider: ethers.providers.JsonRpcProvider,
  tokenAddress: string,
  walletAddress: string,
  whaleAddress: string,
  amount: BigNumber
): Promise<ethers.providers.TransactionResponse> {
  const [whaleSigner] = [forkProvider.getSigner(whaleAddress)];
  // give some ether to the whale so that he can transfer tokens
  if (
    (await forkProvider.getBalance(whaleAddress)).lt(
      ethers.utils.parseEther("1")
    )
  ) {
    await addBalance(
      forkProvider,
      [whaleAddress],
      ethers.utils.parseEther("1")
    );
  }

  // TX: transfer token from whale to wallet
  return await whaleSigner.sendTransaction({
    to: tokenAddress,
    data: tokenAbi.encodeFunctionData("transfer", [
      ethers.utils.hexZeroPad(walletAddress.toLowerCase(), 20),
      amount,
    ]),
    gasLimit: 800000,
  });
}

/**
 * Simulates the transaction submitted to Multisig on the Tenderly fork.
 * @param submitted the submitted transaction to simulate
 * @returns difference in token balance prior and after the transaction
 */
async function simulateOnFork(
  context: Context,
  networkId: string = "1",
  indexCount: number = 1,
  forkId: string = "",
  removeFork: boolean = false,
  tokenAmount: string = "100",
  alias: string = ""
) {
  // create a fork new fork with the freshest data from the network
  const myApi = tenderlyApi(
    TENDERLY_PROJECT_SLUG,
    TENDERLY_USERNAME,
    // TENDERLY_ACCESS_KEY is provided in the dashboard secrets
    await context.secrets.get("TENDERLY_ACCESS_KEY")
  );
  const fork = await myApi.aTenderlyFork(
    { network_id: networkId, alias },
    forkId
  );
  const tokens: { [key: string]: any } = TokensByChainId;
  const whales: { [key: string]: any } = Whales;
  const tokenAddresses: { [key: string]: any } = tokens[networkId];
  const whaleAddresses: { [key: string]: any } = whales[networkId];
  const ethersOnFork = fork.provider; // just grab the provider
  const seed = await context.secrets.get("MNEMONIC");
  const minimumNumberOfWallets = 6;
  console.info(`\n will take the first ${indexCount} addresses`);
  const indexes = Array.from(
    {
      length:
        indexCount < minimumNumberOfWallets
          ? minimumNumberOfWallets
          : indexCount,
    },
    (_, i) => i
  );
  const getAddresses = indexes.map(async (index) => {
    const path = `m/44'/60'/0'/0/${index}`;
    return ethers.Wallet.fromMnemonic(seed, path).getAddress();
  });
  let wallets = await Promise.all(getAddresses);

  // set balance  to at least first 6 wallets
  const ethAmount = ethers.utils.parseEther(tokenAmount);
  // remove wallet from the list of wallet if it already has enough ETH
  const walletsToSetBalance = (
    await Promise.all(
      wallets.map(async (wallet) => {
        const balance = await ethersOnFork.getBalance(wallet);
        if (balance.lt(ethAmount)) {
          return wallet;
        }
        return Promise.resolve();
      })
    )
  ).filter((wallet) => wallet);
  let txSetBal = "";
  console.info(
    `\n will set balance of ETH to wallets  ${JSON.stringify(wallets)} `
  );
  if (walletsToSetBalance.length != 0) {
    txSetBal = await setBalance(
      ethersOnFork,
      walletsToSetBalance,
      ethers.utils.parseEther("100")
    );
  }
  // reduce the number of wallets to fit index count
  if (indexCount < minimumNumberOfWallets) {
    wallets = wallets.splice(0, indexCount);
  }

  // send tokens to each wallet
  const addresses: Promise<(void | ethers.providers.TransactionResponse)[]>[] =
    wallets.map(async (wallet) => {
      /// go through on each property of the tokenAddresses object and send the token to the seed addresses
      const res = async (
        ethersOnFork: ethers.providers.JsonRpcProvider,
        wallet: string
      ) => {
        const result = Object.keys(tokenAddresses).map(
          async (key): Promise<void | ethers.providers.TransactionResponse> => {
            const token = tokenAddresses[key];
            const whale = whaleAddresses[key];
            const deals = async (
              ethersOnFork: ethers.providers.JsonRpcProvider,
              token: {
                address: string;
                decimals: number;
                maxAmount: string | null;
              },
              wallet: string,
              whale: string
            ) => {
              const amount = token.maxAmount
                ? token.maxAmount.toString()
                : tokenAmount;
              // check first that wallet has enough token

              const ERC20token = new ethers.Contract(
                token.address,
                TokenAbi,
                ethersOnFork
              );
              const balance = await ERC20token.balanceOf(wallet);
              if (balance.lt(ethers.utils.parseUnits(amount, token.decimals))) {
                return dealERC20(
                  ethersOnFork,
                  token.address,
                  wallet,
                  whale,
                  ethers.utils.parseUnits(amount, token.decimals)
                );
              } else {
                return Promise.resolve();
              }
            };
            return deals(ethersOnFork, token, wallet, whale);
          }
        );
        return Promise.all(result);
      };
      return res(ethersOnFork, wallet);
    });

  const txResponses = (await Promise.all(addresses)).flat(1);
  console.info(
    `\n transactions:  ${JSON.stringify(
      txResponses ?? { transactionsResponses: [] }.transactionsResponses
    )} `
  );

  if (removeFork) {
    await fork.removeFork(); // remove the fork. For debugging purposes leave it in place
  }
  // add a maxAmount property to each token inside tokenAddresses when it is not already present
  Object.keys(tokenAddresses).forEach((key) => {
    if (!tokenAddresses[key].maxAmount) {
      tokenAddresses[key].maxAmount = tokenAmount;
    }
  });

  return {
    rpc: ethersOnFork.connection.url,
    forkId: fork.id,
    networkId,
    wallets,
    tokens: tokenAddresses,
    transactionsResponses: [...txResponses, txSetBal],
  };
}

/* 
	If authenticated is set to true, you must include the Tenderly Access Token 
	with your request to be able to run the Web3 Action as the value of x-access-key. 
	You can find the cURL of the exposed webhook in the Web3 Action overview in the Tenderly Dashboard. 

	curl -X POST \
	-H "x-access-key: $ACCESS_TOKEN" \
	-H "Content-Type: application/json" \
	https://api.tenderly.co/api/v1/actions/{web3-action-id}/webhook \
	-d '{"chainId": 1, "mnemonicIndexCount": 1, "forkId": "7a6fc622-b751-4faa-9676-25133b40d61b", "removeFork": true, amount: "100"}'
*/

export const onForkHook: ActionFn = async (context: Context, event: Event) => {
  const evt = event as WebhookEvent;

  console.log(event);
  return await simulateOnFork(
    context,
    evt.payload.networkId,
    evt.payload.mnemonicIndexCount,
    evt.payload.forkId,
    evt.payload.removeFork,
    evt.payload.tokenAmount,
    evt.payload.alias
  );
};
