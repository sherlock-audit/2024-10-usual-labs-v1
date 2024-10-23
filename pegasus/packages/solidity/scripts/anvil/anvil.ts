import { spawn } from "child_process";
import { getENV } from "../utils";

(async () => {
  const env = getENV();
  const mnemonic = env.mnemonic;
  const chainId = env.chainId;

  console.log(`using ${env.rpcUrl} and seed from ENV for anvil...`);
  const command = spawn("anvil", [
    "--host",
    "0.0.0.0",
    "-f",
    env.rpcUrl,
    "-m",
    mnemonic as string,
    "--chain-id",
    chainId as string,
    "--auto-impersonate",
  ]);
  command.stdout.on("data", (output: any) => {
    console.log(output.toString());
  });
})();
