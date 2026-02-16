import { type Context, InlineKeyboard } from "grammy";
import { getUser } from "../db/database.js";
import { getBalance } from "../services/blockchain.js";
import type { Address } from "viem";
import { config } from "../config.js";

export async function handleWallet(ctx: Context) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);

  if (!user) {
    await ctx.editMessageText("You need to /start first to create a wallet.");
    return;
  }

  const balance = await getBalance(user.wallet_address as Address).catch(() => "0");

  const explorer = config.chainId === 56
    ? `https://bscscan.com/address/${user.wallet_address}`
    : `https://testnet.bscscan.com/address/${user.wallet_address}`;

  const network = config.chainId === 56 ? "BSC Mainnet" : "BSC Testnet";

  const text = [
    `Your Wallet\n`,
    `Address:`,
    `\`${user.wallet_address}\``,
    ``,
    `Balance: ${Number(balance).toFixed(6)} BNB`,
    `Network: ${network}`,
    ``,
    `To deposit, send BNB to the address above.`,
    ``,
    `[View on BSCScan](${explorer})`,
  ].join("\n");

  const kb = new InlineKeyboard()
    .text("Refresh Balance", "wallet")
    .row()
    .text("Copy Address", "copyaddr")
    .row()
    .text("Back", "main");

  await ctx.editMessageText(text, {
    parse_mode: "Markdown",
    link_preview_options: { is_disabled: true },
    reply_markup: kb,
  });
}

export async function handleCopyAddress(ctx: Context) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);
  if (!user) return;

  // Can't actually copy to clipboard via bot API, so just send the address as a clean message
  await ctx.reply(user.wallet_address);
  await ctx.answerCallbackQuery({ text: "Address sent below!" });
}
