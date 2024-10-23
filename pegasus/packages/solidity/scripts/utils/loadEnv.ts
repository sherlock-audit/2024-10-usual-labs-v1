import fs from "fs";
import path from "path";
import dotenv from "dotenv";
import { HDNodeWallet, Mnemonic } from "ethers";
import { warn } from "./logging";
import { Env } from "./types";

function warnIfNotSet(key: string) {
  if (!process.env[key]?.length) {
    warn(`process.env.${key} not set`);
  } else {
    return process.env[key];
  }
}
const loadEnv = (path: string): Env => {
  dotenv.config({ path });
  const rpcUrl = warnIfNotSet("RPC_URL") || "https://rpc.flashbots.net";
  const mnemonicPhrase = warnIfNotSet("MNEMONIC") || "test test test test test test test test test test test junk";
  const mnemonicIndex = warnIfNotSet("MNEMONIC_INDEX") || "0";
  const chainId = warnIfNotSet("CHAIN_ID") || "1";
  const mnemonic = Mnemonic.fromPhrase(mnemonicPhrase);
  const privateKey = HDNodeWallet.fromMnemonic(mnemonic).privateKey;
  const adminAddress = HDNodeWallet.fromMnemonic(mnemonic).address;

  const etherscanApiKey = warnIfNotSet("ETHERSCAN_API_KEY"); // no fallback

  return {
    rpcUrl,
    privateKey,
    adminAddress,
    etherscanApiKey,
    mnemonic: mnemonicPhrase,
    mnemonicIndex,
    chainId,
  };
};

export const getENV = (): Env => loadEnv(path.join(__dirname, "../../.env"));
