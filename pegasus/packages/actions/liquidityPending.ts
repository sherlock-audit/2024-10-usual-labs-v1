import {
  ActionFn,
  Context,
  Event,
  AlertEvent,
  TransactionEvent,
} from "@tenderly/actions";
import { Alert, tenderlyApi } from "./tenderly-api";
import { BigNumber, ethers } from "ethers";
import axios from "axios";
import { formatAddress, getUsdPrice } from "./utils";
import {
  formatAdminChanges,
  formatBaseMessage,
  formatGrantRoles,
  formatPauses,
  formatRevokeRoles,
  formatTransfers,
  formatUpgrades,
} from "./formatLogs";

import { abi as SwapperEngineAbi } from "./abi/swapperEngine.json";
const swapperEngineAbi = new ethers.utils.Interface(SwapperEngineAbi);

async function pendingLiquidityAlertToTelegram(
  context: Context,
  evt: TransactionEvent
) {
  const accessToken = await context.secrets.get("TELEGRAM_BOT_ACCESS_TOKEN");
  const chanId = await context.storage.getStr("LIQUIDITY_TELEGRAM_GROUP_ID");
  // send a message to the telegram group using bot api and axios
  const url = `https://api.telegram.org/bot${accessToken}/sendMessage`;
  const addressToName: { [key: string]: string } =
    await context.storage.getJson("addressToName");
  const addressToDecimals: { [key: string]: number } =
    await context.storage.getJson("addressToDecimals");
  const bytes32ToRole: { [key: string]: string } =
    await context.storage.getJson("bytes32ToRole");
  const TENDERLY_USERNAME = "usual";
  const TENDERLY_PROJECT_SLUG = "cd";

  const from = evt.from.toLowerCase();
  const to = evt.to?.toLowerCase();
  const txFeeInEth = Number(
    ethers.utils.formatEther(
      BigNumber.from(evt.gasPrice).mul(BigNumber.from(evt.gasUsed))
    )
  );
  const ethPrice = await getUsdPrice("ethereum");
  const txFeeInUsd = txFeeInEth * Number(ethPrice);
  const toName = addressToName[to || "0x"]
    ? `_${addressToName[to || "0x"]}_`
    : formatAddress(to || "0x");
  const fromName = addressToName[from]
    ? `_${addressToName[from]}_`
    : formatAddress(from);

  let message = `${formatBaseMessage(
    "Liquidity Still Pending !",
    "danger",
    Math.round(txFeeInUsd),
    evt,
    fromName,
    toName
  )}
  `;

  // add the signal data to the message
  const res = await axios.post(url, {
    chat_id: chanId,
    text: message,
    parse_mode: "Markdown",
    link_preview_options: {
      is_disabled: true,
    },
  });
  return res.data;
}

async function getOrder(
  rpc: string | undefined,
  orderId: string | undefined
): Promise<boolean> {
  if (!orderId || !rpc) {
    console.log("FAIL orderId:%s rpc:%s", orderId, rpc);
    return false;
  }

  const provider = new ethers.providers.JsonRpcProvider(rpc);
  const swapperEngine = new ethers.Contract(
    "0xB969B0d14F7682bAF37ba7c364b351B830a812B2",
    swapperEngineAbi,
    provider
  );
  //  returns (bool active, uint256 tokenAmount)
  const order = await swapperEngine.getOrder(orderId);
  console.log("order", order);
  const orderAmount = order.tokenAmount.toString();
  console.log("order tokenAmount", orderAmount);
  console.log("order order.active", order.active);

  return order.active || false;
}

export const onDepositLiquidityHook: ActionFn = async (
  context: Context,
  event: Event
) => {
  const evt = event as TransactionEvent;
  // extract the orderID from the logs
  // and send a message to the telegram group
  // event Deposit(address indexed requester, uint256 indexed orderId, uint256 amount);
  const log = evt.logs.find(
    (log) =>
      log.topics[0] ===
      "0x90890809c654f11d6e72a28fa60149770a0d11ec6c92319d6ceb2bb0a4ea1a15"
  );
  console.log("log", log);
  const orderID = log?.topics[2];
  console.log("orderID", orderID);
  const rpc = await context.storage.getStr("MAINNET_JSON_RPC");
  const isActive = await getOrder(rpc, orderID);
  // get the order from the swapper engine contract
  if (isActive) {
    await pendingLiquidityAlertToTelegram(context, evt);
  }
};
