const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const fs = require("fs");
const yargs = require("yargs/yargs");
const { hideBin } = require("yargs/helpers");

// Define arguments for the address, Merkle tree path, and optional output file path
const argv = yargs(hideBin(process.argv))
  .option("address", {
    alias: "a",
    type: "string",
    description: "The address to generate a Merkle proof for",
    demandOption: true
  })
  .option("tree", {
    alias: "t",
    type: "string",
    description: "The path to the Merkle tree JSON file",
    demandOption: true
  })
  .option("output", {
    alias: "o",
    type: "string",
    description: "The optional path to the output file to write the proof"
  })
  .argv;

// Read the address, tree path, and output path from command line arguments
const address = argv.address;
const treePath = argv.tree;
const outputPath = argv.output;

// Check if the tree file exists
if (!fs.existsSync(treePath)) {
  console.error(`Error: Merkle tree file not found at path "${treePath}". Please provide a valid file.`);
  process.exit(1);
}

// Load the Merkle tree from the specified path
const tree = StandardMerkleTree.load(JSON.parse(fs.readFileSync(treePath, "utf8")));

// Generate proof for the given address
let proof = null;
for (const [i, v] of tree.entries()) {
  if (v[0] === address) {
    proof = tree.getProof(i);
    break;
  }
}

if (proof) {
  console.log("Generated proof:", proof.join(" ")); // Log proof to the console
  if (outputPath) {
    fs.writeFileSync(outputPath, JSON.stringify(proof)); // Write proof to the specified output file if provided
    console.log(`Proof written to ${outputPath}`);
  }
} else {
  throw new Error("Address not found in the Merkle tree");
}
