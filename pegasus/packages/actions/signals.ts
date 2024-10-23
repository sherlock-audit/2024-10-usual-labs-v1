import { ActionFn, Context, Event, AlertEvent, Log } from "@tenderly/actions";
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

async function web3AlertToSign4l(
  context: Context,
  evt: AlertEvent,
  message: string,
  alert: Alert
) {
  const sign4lWebHookForDangerAlert = await context.storage.getStr(
    "sign4lWebHookForDangerAlert"
  );
  const sign4lDangerAlertStartHour = await context.storage.getNumber(
    "sign4lDangerAlertStartHour"
  );
  const sign4lDangerAlertEndHour = await context.storage.getNumber(
    "sign4lDangerAlertEndHour"
  );
  const mainnetRpc = await context.storage.getStr("MAINNET_JSON_RPC");
  const provider = new ethers.providers.JsonRpcProvider(mainnetRpc);
  const blockTimestamp = (await provider.getBlock(evt.blockNumber)).timestamp;
  // check if unix date time blocktimestamp is between 00:00h and 6:00 AM UTC time
  // if not, do not send the alert
  const date = new Date(blockTimestamp * 1000);
  let hours = date.getHours();

  if (hours < sign4lDangerAlertStartHour || hours > sign4lDangerAlertEndHour) {
    return "No sign4l sent";
  }

  // extract the timestamp from the alert
  // if the alert is a danger alert, send a signal to the sign4l alerting system
  if (alert.severity === "danger") {
    // Send SIGNL4 alert
    // Alert data
    const data = {
      Title: alert.description,
      Message: message,
    };

    // add the signal data to the message
    const res = await axios.post(sign4lWebHookForDangerAlert, data);
    return res.status;
  }
  return "No sign4l sent";
}

async function web3AlertToTelegram(
  context: Context,
  evt: AlertEvent,
  message: string,
  severity: string
) {
  const accessToken = await context.secrets.get("TELEGRAM_BOT_ACCESS_TOKEN");
  const infoChanId = await context.storage.getStr("TELEGRAM_GROUP_ID");
  const dangerChanId = await context.storage.getStr("DANGER_TELEGRAM_GROUP_ID");

  // send a message to the telegram group using bot api and axios
  const url = `https://api.telegram.org/bot${accessToken}/sendMessage`;

  let chanId = infoChanId;
  if (severity === "danger") {
    chanId = dangerChanId;
  } else if (severity === "warning") {
    chanId = dangerChanId;
  }
  // add the signal data to the message
  const res = await axios.post(url, {
    chat_id: chanId,
    text: message,
    parse_mode: "Markdown",
    link_preview_options: {
      is_disabled: true,
    },
  });
  return res.status;
}

const createMessage = async (
  context: Context,
  evt: AlertEvent
): Promise<{ message: string; alert: Alert }> => {
  const addressToName: { [key: string]: string } =
    await context.storage.getJson("addressToName");
  const addressToDecimals: { [key: string]: number } =
    await context.storage.getJson("addressToDecimals");
  const bytes32ToRole: { [key: string]: string } =
    await context.storage.getJson("bytes32ToRole");
  const TENDERLY_USERNAME = "usual";
  const TENDERLY_PROJECT_SLUG = "cd";

  // get alert info from tenderly API
  const myApi = tenderlyApi(
    TENDERLY_PROJECT_SLUG,
    TENDERLY_USERNAME,
    // TENDERLY_ACCESS_KEY is provided in the dashboard secrets
    await context.secrets.get("TENDERLY_ACCESS_KEY")
  );
  const alertId = evt.alertId;
  const from = evt.from.toLowerCase();
  const to = evt.to?.toLowerCase();
  const txFeeInEth = Number(
    ethers.utils.formatEther(
      BigNumber.from(evt.gasPrice).mul(BigNumber.from(evt.gasUsed))
    )
  );
  const ethPrice = await getUsdPrice("ethereum");
  const txFeeInUsd = txFeeInEth * Number(ethPrice);
  const alert = await myApi.getAlert(alertId);
  const toName = addressToName[to || "0x"]
    ? `_${addressToName[to || "0x"]}_`
    : formatAddress(to || "0x");
  const fromName = addressToName[from]
    ? `_${addressToName[from]}_`
    : formatAddress(from);

  // within the evt.logs array find the topics corresponding to a transfer event
  // and extract the values of the transfer
  const transfers = evt.logs?.filter(
    (log) =>
      log.topics[0] ===
      "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  );
  // Upgraded(address)
  const upgraded = evt.logs?.filter(
    (log) =>
      log.topics[0] ===
      "0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b"
  );
  // Paused(address)
  const paused = evt.logs?.filter(
    (log) =>
      log.topics[0] ===
      "0x62e78cea01bee320cd4e420270b5ea74000d11b0c9f74754ebdbfc544b05a258"
  );

  // AdminChanged(address,address)
  const AdminChanged = evt.logs?.filter(
    (log) =>
      log.topics[0] ===
      "0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f"
  );

  // RoleGranted(bytes32,address,address)
  const RoleGranted = evt.logs?.filter(
    (log) =>
      log.topics[0] ===
      "0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d"
  );

  // RoleRevoked(bytes32,address,address)
  const RoleRevoked = evt.logs?.filter(
    (log) =>
      log.topics[0] ===
      "0xf6391f5c32d9c69d2a47ea670b442974b53935d1edc7fd64eb21e047a839171b"
  );
  const severity = alert.severity;
  let message = `${formatBaseMessage(
    alert.name,
    severity,
    Math.round(txFeeInUsd),
    evt,
    fromName,
    toName
  )}
  ${await formatTransfers(
    transfers,
    addressToName,
    addressToDecimals
  )}${await formatUpgrades(upgraded, addressToName)}${await formatAdminChanges(
    AdminChanged,
    addressToName
  )}${await formatPauses(paused, addressToName)}${await formatGrantRoles(
    RoleGranted,
    addressToName,
    bytes32ToRole
  )}${await formatRevokeRoles(RoleRevoked, addressToName, bytes32ToRole)}
  `;
  return { message, alert };
};

export const onAlertHook: ActionFn = async (context: Context, event: Event) => {
  const evt = event as AlertEvent;
  const { message, alert } = await createMessage(context, evt);
  const resSignal = await web3AlertToSign4l(context, evt, message, alert);
  console.log("resSignal", resSignal);
  const resTelegram = await web3AlertToTelegram(
    context,
    evt,
    message,
    alert.severity
  );
  console.log("resTelegram", resTelegram);
  return { sign4l: resSignal, telegram: resTelegram };
};
