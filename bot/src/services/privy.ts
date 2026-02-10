import { PrivyClient } from "@privy-io/node";
import { config } from "../config.js";

const privy = new PrivyClient({
  appId: config.privyAppId,
  appSecret: config.privyAppSecret,
});

export interface WalletInfo {
  walletId: string;
  walletAddress: string;
}

/**
 * Create a new server-managed Privy wallet.
 * Each Telegram user gets one wallet stored by wallet ID in our DB.
 */
export async function createWallet(): Promise<WalletInfo> {
  const wallet = await privy.wallets().create({
    chain_type: "ethereum",
  });

  return {
    walletId: wallet.id,
    walletAddress: wallet.address,
  };
}

/**
 * Sign and send a transaction using Privy's server wallet.
 */
export async function sendTransaction(walletId: string, tx: {
  to: string;
  value: string;
  data: string;
  chainId: number;
  gasLimit?: string;
}): Promise<string> {
  const caip2 = `eip155:${tx.chainId}`;

  const result = await privy.wallets().ethereum().sendTransaction(walletId, {
    caip2,
    params: {
      transaction: {
        to: tx.to,
        value: tx.value,
        data: tx.data,
        chain_id: tx.chainId,
        ...(tx.gasLimit ? { gas_limit: tx.gasLimit } : {}),
      },
    },
  });

  return result.hash;
}
