import axios from "axios";

// formatAddress function to format an address to only the first 6 characters and create an url to etherscan in markdown
export const formatAddress = (address: string) => {
  if (address === "0x") {
    return "0x";
  }
  return `[${reduceString(address)}](https://etherscan.io/address/${address})`;
};

// formatBytes32 function to format a bytes32 to only the first 6 characters
export const formatBytes32 = (bytes32: string) => {
  return reduceString(bytes32);
};

// function to reduce a string to only the first 6 characters
// and add "..." at the end
export const reduceString = (str: string) => {
  return str.length > 6 ? str.slice(0, 6) + "..." : str;
};

export const getUsdPrice = async (coin: string) => {
  const coinInfo = await axios.get(
    `https://api.coingecko.com/api/v3/coins/${coin}`
  );
  return coinInfo.data.market_data.current_price.usd;
};
