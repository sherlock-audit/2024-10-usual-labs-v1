import { Alert } from "./tenderly-api";
import { AlertEvent, Log } from "@tenderly/actions";
import { ethers } from "ethers";
import { formatAddress, formatBytes32 } from "./utils";

// responsible for the header of the message
export const formatBaseMessage = (
  alertName: string,
  severity: string,
  txFeeInUsd: number,
  evt: AlertEvent,
  fromName: string,
  toName: string
) => {
  let icon = "ℹ️";
  if (severity === "danger") {
    icon = "🚨";
  } else if (severity === "warning") {
    icon = "⚠️";
  } else if (severity === "success") {
    icon = "✅";
  }
  let feeIcon = "💲";
  if (txFeeInUsd > 50) {
    // burn icon
    feeIcon = "🔥💲";
  }
  const network = evt.network;
  let networkIcon = `[🌐](https://chainlist.org/chain/${network})`;
  if (network === "1") {
    networkIcon = `[🔷](https://chainlist.org/chain/1)`;
  } else if (network === "11155111") {
    networkIcon = `[🟩](https://chainlist.org/chain/11155111)`;
  } else if (network === "10") {
    networkIcon = `[♦️](https://chainlist.org/chain/137)`;
  } else if (network === "42161") {
    networkIcon = `[💠](https://chainlist.org/chain/42161)`;
  } else if (network === "8453") {
    networkIcon = `[🌰](https://chainlist.org/chain/8453)`;
  }

  let message = `${icon} *${alertName}* ${icon} ${networkIcon} [🔗](https://etherscan.io/tx/${evt.hash}/)  
  *From* ${fromName} *To* ${toName} _Fees:${txFeeInUsd} ${feeIcon}_ 
  `;

  return message;
};

// for each transfer event, extract the value and the transfer from and to address
export const formatTransfer = (
  token: string,
  tokenAddress: string,
  fromName: string,
  toName: string,
  value: number
) => {
  let isWhale = false;
  let isSmallWhale = false;

  if (value > 1000000) {
    isWhale = true;
  } else if (value > 100000) {
    isSmallWhale = true;
  }
  // format the value as a number
  const valueString = value.toLocaleString("en-US", {
    maximumFractionDigits: 2,
  });
  let message: string;
  if (fromName === "0x") {
    // minting
    message = `⛏️ *Mint To* ${toName} *For* ${valueString} [${token}](https://etherscan.io/address/${tokenAddress}/)`;
  } else if (toName === "0x") {
    // burning
    message = `🔥 *Burn From* ${fromName} *For* ${valueString} [${token}](https://etherscan.io/address/${tokenAddress}/)`;
  } else {
    message = `💸 *Transfer From* ${fromName} *To* ${toName} *For* ${valueString} [${token}](https://etherscan.io/address/${tokenAddress}/)`; // add the signal data to the message
  }
  return `${message} ${isWhale ? "🐳" : isSmallWhale ? "🐋" : ""}`;
};

export const formatTokenTransfers = (
  token: string,
  transfers: {
    tokenAddress: string;
    from: string;
    to: string;
    value: number;
  }[]
) => {
  const transferMessages = transfers.map((transfer) => {
    return formatTransfer(
      token,
      transfer.tokenAddress,
      transfer.from,
      transfer.to,
      transfer.value
    );
  });
  return transferMessages.join("\n");
};

// for each transfer event, extract the value of the transfer and check topic [1] and [2] as from and to address
// and get the wallet or contract name from the tenderly API
// if the address is not a wallet, it is a contract
// get the contract name from the tenderly API
// send a message to the telegram group with the alert name, from, to, and value
export const formatTransfers = async (
  transfers: Log[] | null,
  addressToName: { [key: string]: string },
  addressToDecimals: { [key: string]: number }
) => {
  if (transfers && transfers.length > 0) {
    // mapping between token and array
    const tokenTransfers: { [key: string]: Log[] } = {};
    // for each transfer call the formatTransfer function and resolve all promises
    const transferMessages = await Promise.all(
      transfers.map((transfer) => {
        const from = ethers.utils
          .hexStripZeros(transfer.topics[1])
          .toLowerCase();
        const to = ethers.utils.hexStripZeros(transfer.topics[2]).toLowerCase();

        const tokenAddress = transfer.address.toLowerCase();

        const value = ethers.utils.formatUnits(
          transfer.data,
          addressToDecimals[tokenAddress] || 18
        );

        // boolean to check if the string amount is greater than 1 million
        const numberValue = Number(value);

        const token = addressToName[tokenAddress] || "ERC20token";
        // get the wallet or contract name from the tenderly storage
        const toName = addressToName[to]
          ? `_${addressToName[to]}_`
          : formatAddress(to);
        const fromName = addressToName[from]
          ? `_${addressToName[from]}_`
          : formatAddress(from);
        let message: string;
        return { token, fromName, toName, numberValue, tokenAddress };
      })
    );
    // go through all the transfer messages and reduce them into the tokenTransfers object
    // the tokenTransfers object will have the token address as the key and the value will be add or substract if we have a transfer from and a trasnfer to the same address
    const reducedTokenTransfer: {
      [key: string]: {
        from: string;
        to: string;
        value: number;
        tokenAddress: string;
      }[];
    } = {};
    transferMessages.forEach((transfer) => {
      if (!reducedTokenTransfer[transfer.token]) {
        reducedTokenTransfer[transfer.token] = [
          {
            from: transfer.fromName,
            to: transfer.toName,
            value: transfer.numberValue,
            tokenAddress: transfer.tokenAddress,
          },
        ];
      } else {
        // we already have the same transfer we find the index and add the value
        const indexSame = reducedTokenTransfer[transfer.token].findIndex(
          (t) => t.from === transfer.fromName && t.to === transfer.toName
        );
        if (indexSame !== -1) {
          reducedTokenTransfer[transfer.token][indexSame].value +=
            transfer.numberValue;
          return;
        }
        const indexInverted = reducedTokenTransfer[transfer.token].findIndex(
          (t) => t.to === transfer.fromName && t.from === transfer.toName
        );

        // we already have a transfer we from and to address inverted, we find the index and add the value
        if (indexInverted !== -1) {
          reducedTokenTransfer[transfer.token][indexInverted].value -=
            transfer.numberValue;
          return;
        }
        // we don't have the transfer we add it
        reducedTokenTransfer[transfer.token].push({
          from: transfer.fromName,
          to: transfer.toName,
          value: transfer.numberValue,
          tokenAddress: transfer.tokenAddress,
        });
      }
    });
    // format each token transfer within reducedTokenTransfer through the formatTransfer function
    const transferMessagesReduced = Object.keys(reducedTokenTransfer).map(
      (token) => {
        return formatTokenTransfers(token, reducedTokenTransfer[token]);
      }
    );

    return `*Token Transfers*
${transferMessagesReduced.join("\n")} `;
  }
  return "";
};

export const formatUpgrade = async (
  upgrade: Log,
  addressToName: { [key: string]: string }
) => {
  const newImplementationAddress = ethers.utils
    .hexStripZeros(upgrade.topics[1])
    .toLowerCase();
  const contractUpgradedAddress = upgrade.address.toLowerCase();

  // get the wallet or contract name from the tenderly storage
  const contractUpgraded = addressToName[contractUpgradedAddress]
    ? `_${addressToName[contractUpgradedAddress]}_`
    : formatAddress(contractUpgradedAddress);
  const newImplementation = addressToName[newImplementationAddress]
    ? `_${addressToName[newImplementationAddress]}_`
    : formatAddress(newImplementationAddress);

  // upgrade message
  return `⚙️ ${contractUpgraded} *Upgraded to* ${newImplementation}`;
};

export const formatUpgrades = async (
  upgrades: Log[] | null,
  addressToName: { [key: string]: string }
) => {
  if (upgrades && upgrades.length > 0) {
    // for each transfer call the formatTransfer function and resolve all promises
    const upgradeMessages = await Promise.all(
      upgrades.map((upgrade) => {
        return formatUpgrade(upgrade, addressToName);
      })
    );
    return `*Upgrades*
${upgradeMessages.join("\n")} `;
  }
  return "";
};

export const formatAdminChange = async (
  adminChange: Log,
  addressToName: { [key: string]: string }
) => {
  const previousAdminAddress = ethers.utils
    .hexStripZeros(adminChange.topics[1])
    .toLowerCase();
  const newAdminAddress = ethers.utils
    .hexStripZeros(adminChange.topics[2])
    .toLowerCase();
  const proxyAddress = adminChange.address.toLowerCase();

  // get the wallet or contract name from the tenderly storage
  const proxy = addressToName[proxyAddress]
    ? `_${addressToName[proxyAddress]}_`
    : formatAddress(proxyAddress);
  const previousAdmin = addressToName[previousAdminAddress]
    ? `_${addressToName[previousAdminAddress]}_`
    : formatAddress(previousAdminAddress);
  const newAdmin = addressToName[newAdminAddress]
    ? `_${addressToName[newAdminAddress]}_`
    : formatAddress(newAdminAddress);

  return `🔁 ${proxy} *Admin changed from* ${previousAdmin} *to* ${newAdmin}`;
};

export const formatAdminChanges = async (
  adminChanges: Log[] | null,
  addressToName: { [key: string]: string }
) => {
  if (adminChanges && adminChanges.length > 0) {
    // for each transfer call the formatTransfer function and resolve all promises
    const adminChangeMessages = await Promise.all(
      adminChanges.map((adminChange) => {
        return formatAdminChange(adminChange, addressToName);
      })
    );
    return `*Admin Changes*
${adminChangeMessages.join("\n")} `;
  }
  return "";
};

export const formatPause = async (
  pause: Log,
  addressToName: { [key: string]: string }
) => {
  const pausedAddress = ethers.utils
    .hexStripZeros(pause.topics[1])
    .toLowerCase();
  const proxyAddress = pause.address.toLowerCase();

  // get the wallet or contract name from the tenderly storage
  const proxy = addressToName[proxyAddress]
    ? `_${addressToName[proxyAddress]}_`
    : formatAddress(proxyAddress);
  const paused = addressToName[pausedAddress]
    ? `_${addressToName[pausedAddress]}_`
    : formatAddress(pausedAddress);

  return `⏸️ ${proxy} *Paused by* ${paused}`;
};

export const formatPauses = async (
  pauses: Log[] | null,
  addressToName: { [key: string]: string }
) => {
  if (pauses && pauses.length > 0) {
    // for each transfer call the formatTransfer function and resolve all promises
    const pauseMessages = await Promise.all(
      pauses.map((pause) => {
        return formatPause(pause, addressToName);
      })
    );
    return `*Pauses*
${pauseMessages.join("\n")} `;
  }
  return "";
};

export const formatGrantRole = async (
  grantRole: Log,
  addressToName: { [key: string]: string },
  bytes32ToRole: { [key: string]: string }
) => {
  const roleBytes32 = ethers.utils
    .hexStripZeros(grantRole.topics[1])
    .toLowerCase();
  const accountAddress = ethers.utils
    .hexStripZeros(grantRole.topics[2])
    .toLowerCase();
  const senderAddress = ethers.utils
    .hexStripZeros(grantRole.topics[3])
    .toLowerCase();

  // get the wallet or contract name from the tenderly storage
  const role = bytes32ToRole[roleBytes32]
    ? `_${bytes32ToRole[roleBytes32]}_`
    : formatBytes32(roleBytes32);
  const account = addressToName[accountAddress]
    ? `_${addressToName[accountAddress]}_`
    : formatAddress(accountAddress);
  const sender = addressToName[senderAddress]
    ? `_${addressToName[senderAddress]}_`
    : formatAddress(senderAddress);

  return `🔑➕ ${sender} *Granted role* ${role} *to* ${account}`;
};

export const formatGrantRoles = async (
  grantsRoles: Log[] | null,
  addressToName: { [key: string]: string },
  bytes32ToRole: { [key: string]: string }
) => {
  if (grantsRoles && grantsRoles.length > 0) {
    // for each transfer call the formatTransfer function and resolve all promises
    const grantRoleMessages = await Promise.all(
      grantsRoles.map((grantRole) => {
        return formatGrantRole(grantRole, addressToName, bytes32ToRole);
      })
    );
    return `*Role Grants*
${grantRoleMessages.join("\n")} `;
  }
  return "";
};

export const formatRevokeRole = async (
  revokeRole: Log,
  addressToName: { [key: string]: string },
  bytes32ToRole: { [key: string]: string }
) => {
  const roleBytes32 = ethers.utils
    .hexStripZeros(revokeRole.topics[1])
    .toLowerCase();
  const accountAddress = ethers.utils
    .hexStripZeros(revokeRole.topics[2])
    .toLowerCase();
  const senderAddress = ethers.utils
    .hexStripZeros(revokeRole.topics[3])
    .toLowerCase();

  // get the wallet or contract name from the tenderly storage
  const role = bytes32ToRole[roleBytes32]
    ? `_${bytes32ToRole[roleBytes32]}_`
    : formatBytes32(roleBytes32);
  const account = addressToName[accountAddress]
    ? `_${addressToName[accountAddress]}_`
    : formatAddress(accountAddress);
  const sender = addressToName[senderAddress]
    ? `_${addressToName[senderAddress]}_`
    : formatAddress(senderAddress);

  return `🔑➖ ${sender} *Revoked role* ${role} *from* ${account}`;
};

export const formatRevokeRoles = async (
  revokesRoles: Log[] | null,
  addressToName: { [key: string]: string },
  bytes32ToRole: { [key: string]: string }
) => {
  if (revokesRoles && revokesRoles.length > 0) {
    // for each transfer call the formatTransfer function and resolve all promises
    const revokeRoleMessages = await Promise.all(
      revokesRoles.map((revokeRole) => {
        return formatRevokeRole(revokeRole, addressToName, bytes32ToRole);
      })
    );
    return `*Role Revokes*
${revokeRoleMessages.join("\n")} `;
  }
  return "";
};
