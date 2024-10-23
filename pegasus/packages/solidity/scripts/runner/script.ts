import { InputParams, ForgeScriptArguments, ScriptResult } from "../utils/types";
import { execute, getENV } from "../utils";

const script = async (args: ForgeScriptArguments): Promise<ScriptResult> => {
  let prepareCmd = " --unlocked --sender 0x411fab2b2a2811fa7dee401f8822de1782561804";
  prepareCmd += " --force --slow";

  if (args.broadcast) {
    prepareCmd += " --broadcast";
    console.log("will broadcast transactions");

    // will not verify if deployment did not broadcast
    if (args.etherscanApiKey) {
      prepareCmd += ` --etherscan-api-key ${args.etherscanApiKey} --verify`;
    }
  }

  if (args.rpcUrl) {
    prepareCmd += ` --rpc-url ${args.rpcUrl}`;
  }

  if (args.verbosity > 0) {
    prepareCmd += ` -${"v".repeat(args.verbosity)}`;
  }

  const executeCmd: string = `forge script ${args.scriptContractName}${prepareCmd}`;

  console.log(`executeCmd: ${executeCmd}`);
  let result: ScriptResult = {
    stdout: "",
    stderr: null,
  };
  try {
    const { stdout: _stdout, stderr: _stderr } = await execute(executeCmd);
    result.stdout = _stdout;
  } catch (err: any) {
    result.stdout = err?.stdout;
    result.stderr = err?.stderr;
  }
  return result;
};

export const scriptHandler = async (args: InputParams, scriptContractName: string) => {
  const env = getENV();

  const broadcast = Boolean(args.broadcast);
  // RPC provided through args will override the one in .env
  let rpcUrl = args.rpcUrl ?? undefined;
  if (!rpcUrl) {
    rpcUrl = env.rpcUrl;
    console.log(`no RPC provided will use RPC_URL env`);
  }

  // Etherscan Api Key provided through args will override the one in .env
  let etherscanApiKey: string | undefined = args.etherscanApiKey ?? undefined;
  if (!etherscanApiKey && broadcast) {
    etherscanApiKey = env.etherscanApiKey;
    console.log(`will use etherscan Api Key from ENV`);
  }

  const verbosity = parseInt(args.verbosity);

  const { stdout, stderr } = await script({
    rpcUrl,
    scriptContractName,
    etherscanApiKey,
    broadcast,
    verbosity,
  });

  return { stdout, stderr };
};
