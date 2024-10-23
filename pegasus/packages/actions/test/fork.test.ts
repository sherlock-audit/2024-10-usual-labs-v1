// File: src/web3-actions-local/run.ts
// web3-actions sources location: src/actions/awesomeActions.ts

import { TestWebhookEvent, TestRuntime } from "@tenderly/actions-test";
import { onForkHook } from "../fork-webhook";

import * as dotenv from "dotenv";
dotenv.config();

/*
 * Running Web3 Actions code locally.
 * TestRuntime is a helper class that allows you to run the functions,
 * and set storage and secrets before running the function
 **/
const main = async () => {
  const testRuntime = new TestRuntime();

  testRuntime.context.secrets.put(
    "TENDERLY_ACCESS_KEY",
    process.env.TENDERLY_ACCESS_KEY || ""
  );
  testRuntime.context.secrets.put(
    "MNEMONIC",
    process.env.MNEMONIC ||
      "diesel refuse sand submit frost will hungry nasty boss resemble million father"
  );
  const res = await testRuntime.execute(
    onForkHook,
    new TestWebhookEvent({
      removeFork: false,
      forkId: "017f698e-0b84-455b-b402-489607361bad",
      networkId: 1,
      alias: "test",
      mnemonicIndexCount: 2,
      tokenAmount: "100",
    })
  );
  console.log(res);
};

(async () => await main())();
