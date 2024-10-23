const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const fs = require("fs");
const csvParser = require("csv-parser");
const yargs = require("yargs/yargs");
const { hideBin } = require("yargs/helpers");

const argv = yargs(hideBin(process.argv))
  .option("csv", {
    alias: "c",
    type: "string",
    description: "CSV file with addresses, amounts, and isTop80 flags",
    demandOption: true
  })
  .option("output", {
    alias: "o",
    type: "string",
    description: "Output file path for the Merkle tree",
    default: "test/utils/airdropTree.json"  // Default output file path
  })
  .argv;

const csvFilePath = argv.csv;
const outputFilePath = argv.output;
const values = [];

// Check if the CSV file exists
if (!fs.existsSync(csvFilePath)) {
  console.error(`Error: CSV file not found at path "${csvFilePath}". Please provide a valid file.`);
  process.exit(1);
}

// Read and parse the CSV file
fs.createReadStream(csvFilePath)
  .pipe(csvParser())
  .on("data", (row) => {
    const address = row['address'];
    const amount = row['amount'];
    const isTop80 = row['isTop80'] === 'true'; // Convert to boolean

    // Add to the values array
    values.push([address, amount, isTop80]);
  })
  .on("end", () => {
    if (values.length === 0) {
      console.error("Error: No data found in the CSV file.");
      process.exit(1);
    }

    // Generate the Merkle Tree from the CSV data
    const tree = StandardMerkleTree.of(values, ["address", "uint256", "bool"]);

    // Output the Merkle Root and save the tree to the output file
    console.log("Merkle Root:", tree.root);
    fs.writeFileSync(outputFilePath, JSON.stringify(tree.dump()));
    console.log(`Merkle Tree written to ${outputFilePath}`);
  })
  .on("error", (error) => {
    console.error(`Error reading CSV file: ${error.message}`);
    process.exit(1);
  });
