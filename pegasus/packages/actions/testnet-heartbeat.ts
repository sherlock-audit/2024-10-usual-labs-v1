import { ActionFn, Context, Event, BlockEvent } from "@tenderly/actions";
import { ethers, providers } from "ethers";

async function sendTxOnVirtualTestnet(
  context: Context,
  testnetRPCs: string[] = []
) {
  const seed = await context.secrets.get("MNEMONIC");
  const path = `m/44'/60'/0'/0/0`;
  const aliceWallet = ethers.Wallet.fromMnemonic(seed, path);
  const aliceAddresse = await aliceWallet.getAddress();
  const tx: providers.TransactionRequest = {
    to: aliceAddresse,
    value: 1,
  };
  console.log(`walletAddress:${aliceAddresse}`);
  // for each rpc, send a transaction to keep the testnet alive
  for (const rpc of testnetRPCs) {
    // Initialize an ethers provider instance
    const provider = new ethers.providers.JsonRpcProvider(rpc);

    try {
      const txResponse = await aliceWallet
        .connect(provider)
        .sendTransaction(tx);
      console.log(`Transaction sent to ${rpc}: ${txResponse.hash}`);
    } catch (error) {
      console.error(`Error sending transaction to ${rpc}`);
    }
  }
}

export const onBlockHook: ActionFn = async (context: Context, event: Event) => {
  const evt = event as BlockEvent;

  // console.log(event);
  // get all testnets rpc from storage
  const testnetRPCs: string[] = await context.storage.getJson(
    "virtualTestNetAdminRPCToKeepAlive"
  );
  return await sendTxOnVirtualTestnet(context, testnetRPCs);
};
