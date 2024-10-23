import CommandLineArgs from "command-line-args";
import { optionDefinitions } from "../utils/types";
import { scriptHandler } from "./script";

const main = async () => {
  const cmdArgs = process.argv.slice(2);
  const name = cmdArgs[0];
  if (!name) {
    throw new Error("script name is mandatory");
  }

  let args;
  try {
    args = CommandLineArgs(optionDefinitions);
  } catch (error: unknown) {
    console.error(`Argument parse failed!, error: ${error}`);
    return;
  }
  const { stdout, stderr } = await scriptHandler(args, name);
  console.log(stdout);
  if (stderr) {
    console.error(stderr);
    process.exit(1);
  }
  console.log("Script successful ✅.");
};

main();
