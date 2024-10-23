import { OptionDefinition } from "command-line-args";

export const optionDefinitions: OptionDefinition[] = [
  { name: "task", defaultOption: true },
  { name: "rpcUrl", alias: "r", type: String },
  { name: "etherscanApiKey", alias: "k", type: String },
  { name: "broadcast", alias: "b", type: Boolean, defaultValue: false },
  { name: "verbosity", alias: "v", type: Number, defaultValue: 0 },
];
