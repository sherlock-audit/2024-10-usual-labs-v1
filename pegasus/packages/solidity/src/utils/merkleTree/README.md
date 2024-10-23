# Merkle Tree Utilities

This directory contains utilities for generating Merkle root and proofs for token distributions.

## Generate Merkle Root

Use `generateAirdropMerkleRoot.js` to create a Merkle root for the airdrop distribution:

```bash
node generateAirdropMerkleRoot.js --csv data.csv --output test/utils/airdropTree.json
```

### This script:
1. Takes a CSV file with address, amount, and isTop80 (boolean) columns as input.
2. Creates a Merkle tree with [address, amount, isTop80] triples.
3. Outputs the Merkle root to the console.
4. Saves the tree data to the specified output file (defaults to test/utils/airdropTree.json).

### Exemple of CSV file:
```
address,amount
0x6a8b32cb656559c0fC49cD7Db3ce48C074A7abe3,4866160317000000000000000000,true
0x02A02da2CB9795931fb68C8ae3d6237d2dD8e70e,167600175000000000000000000,true
0xa000c80DCB9Cb742Cb37Fbe410E73c8C7A0702c1,18450169000000000000000000,true
0xE18526A1F8D22bf747a6234eEAE1139797C49369,62497000000000000000000,false
0x8D1cbf0a75D63e63a5C887EC33ed9c2A5458a614,1000000000000000000,false
```

### Custom Output:
You can specify a different output file path using the --output (or -o) option:

```bash
node generateAirdropMerkleRoot.js --csv data.csv --output customTree.json
```

## Generate Merkle Proof

Use `generateAirdropMerkleProof.js` to generate a proof for an address in the airdrop distribution:

```bash
node generateAirdropMerkleProof.js --address 0x123... --tree path/to/airdropTree.json
```

### This script:
1. Takes an address and the path to the Merkle tree JSON file as input.
2. Generates a Merkle proof for the address using the data from the specified Merkle tree file.
3. Outputs the proof to the console.
4. Optionally, you can specify an output file to save the proof:
    
```bash    
node generateAirdropMerkleProof.js --address 0x123... --tree path/to/airdropTree.json --output proof.json
```

## Notes

- Ensure you've generated the Merkle tree before attempting to create proofs.
- All amounts should be in wei (10^18 units for most ERC20 tokens).
- Addresses should be full Ethereum addresses (42 characters, including '0x').
- The vesting flags are booleans indicating whether the amount is in the top 80% of the distribution (true) or not (false).

## Dependencies

These scripts use the following npm packages:
- @openzeppelin/merkle-tree
- csv-parser
- fs
- yargs

Ensure you have these installed in your project before running the scripts.

