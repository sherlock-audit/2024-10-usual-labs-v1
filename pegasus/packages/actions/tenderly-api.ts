import { JsonRpcProvider } from "@ethersproject/providers";
import axios, { AxiosResponse } from "axios";

type TenderlyForkRequest = {
  block_number?: number;
  network_id: string;
  transaction_index?: number;
  initial_balance?: number;
  alias?: string;
  chain_config?: {
    chain_id: number;
    homestead_block: number;
    dao_fork_support: boolean;
    eip_150_block: number;
    eip_150_hash: string;
    eip_155_block: number;
    eip_158_block: number;
    byzantium_block: number;
    constantinople_block: number;
    petersburg_block: number;
    istanbul_block: number;
    berlin_block: number;
  };
};
export type Alert = {
  id: string;
  project_id: string;
  name: string;
  description: string;
  enabled: boolean;
  color: string;
  severity: string;
  created_at: string;
  delivery_channels: any[];
};
export type Account = {
  id: string;
  balance: string;
  address: string;
  contract_name: string;
  type: string;
  creation_block: number;
  creator_address: string;
};

export type Wallet = {
  id: string;
  display_name: string;
  account_type: string;
  account: Account;
};

export type Contract = {
  id: string;
  display_name: string;
  account_type: string;
  account: Account;
  contract: Account;
};

export type TenderlyForkProvider = {
  provider: JsonRpcProvider;
  id: string;
  blockNumber: number;
  /**
   * map from address to given address' balance
   */
  removeFork: () => Promise<AxiosResponse<any, any>>;
};

export const tenderlyApi = (
  projectSlug: string,
  username: string,
  accessKey: string
) => {
  const somewhereInTenderly = (where: string = projectSlug || "") => {
    console.log(`\nTenderly API for ${where}`);
    return axios.create({
      baseURL: `https://api.tenderly.co/api/v1/${where}`,
      headers: {
        "X-Access-Key": accessKey || "",
        "Content-Type": "application/json",
      },
    });
  };

  const inProject = (...path: any[]) =>
    [`account/${username}/project/${projectSlug}`, ...path]
      .join("/")
      .replace("//", "");

  const anAxiosOnTenderly = () => somewhereInTenderly("");
  const axiosOnTenderly = anAxiosOnTenderly();

  const axiosInProject = somewhereInTenderly(inProject());

  const removeFork = async (forkId: string) => {
    console.info(`\nRemoving test fork ${forkId}`);
    return await axiosOnTenderly.delete(inProject(`fork/${forkId}`));
  };

  async function aTenderlyFork(
    fork: TenderlyForkRequest,
    id?: string
  ): Promise<TenderlyForkProvider> {
    let forkId = id || "";
    let blockNumber: number = 0;
    if (!id) {
      const forkResponse = await axiosInProject.post(`/fork`, fork);
      forkId = forkResponse.data.root_transaction.fork_id as string;
      const bn = (
        forkResponse.data.root_transaction.receipt.blockNumber as string
      ).replace("0x", "");
      blockNumber = Number.parseInt(bn, 16);
    }
    const forkProviderUrl = `https://rpc.tenderly.co/fork/${forkId}`;
    const forkProvider = new JsonRpcProvider(forkProviderUrl);
    if (blockNumber === 0) {
      blockNumber = await forkProvider.getBlockNumber();
    }
    console.info(
      `\nForked with fork id ${forkId} at block number ${blockNumber}`
    );

    console.info(`https://dashboard.tenderly.co/${inProject("fork", forkId)}`);

    console.info("JSON-RPC:", forkProviderUrl);

    return {
      provider: forkProvider,
      blockNumber,
      id: forkId,
      removeFork: () => removeFork(forkId),
    };
  }

  async function getAlert(alertId?: string): Promise<Alert> {
    if (alertId) {
      const response = await axiosInProject.get(`/alerts`);
      const alerts = response.data.alerts;
      return alerts.find((alert: any) => alert.id === alertId);
    }
    return {
      id: "",
      project_id: "",
      name: "",
      description: "",
      enabled: false,
      color: "",
      severity: "",
      created_at: "",
      delivery_channels: [],
    };
  }

  async function getContract(address?: string): Promise<Contract> {
    if (address) {
      const response = await axiosInProject.get(
        `/contracts?accountType=contract`
      );
      const contracts = response.data;
      return contracts.find(
        (contract: any) => contract.contract.address === address
      );
    }
    return {
      id: "",
      display_name: "",
      account_type: "",
      account: {
        id: "",
        balance: "",
        address: "",
        contract_name: "",
        type: "",
        creation_block: 0,
        creator_address: "",
      },
      contract: {
        id: "",
        balance: "",
        address: "",
        contract_name: "",
        type: "",
        creation_block: 0,
        creator_address: "",
      },
    };
  }

  async function getWallet(address?: string): Promise<Wallet> {
    if (address) {
      const response = await axiosInProject.get(`/wallet/${address}/network/1`);
      const wallet = response.data;
      return wallet;
    }
    return {
      id: "",
      display_name: "",
      account_type: "",
      account: {
        id: "",
        balance: "",
        address: "",
        contract_name: "",
        type: "",
        creation_block: 0,
        creator_address: "",
      },
    };
  }

  return {
    aTenderlyFork,
    getAlert,
    getContract,
    getWallet,
  };
};
