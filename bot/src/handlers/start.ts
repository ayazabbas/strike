import { type Context, InlineKeyboard } from "grammy";
import { getUser, createUser } from "../db/database.js";
import { createWallet } from "../services/privy.js";
import { getBalance } from "../services/blockchain.js";
import type { Address } from "viem";

export function mainMenuKeyboard() {
  return new InlineKeyboard()
    .text("⚡ Live", "live")
    .text("🎲 My Bets", "mybets")
    .row()
    .text("👛 Wallet", "wallet")
    .text("⚙️ Settings", "settings")
    .row()
    .text("❓ How it Works", "howitworks");
}

export async function handleStart(ctx: Context) {
  const telegramId = ctx.from!.id;
  const username = ctx.from!.username ?? null;

  await ctx.reply("Loading...");

  let user = getUser(telegramId);

  if (!user) {
    await ctx.reply("Creating your wallet...");
    try {
      const wallet = await createWallet();
      user = createUser(telegramId, username, wallet.walletAddress, wallet.walletId);
    } catch (err) {
      console.error("Wallet creation failed:", err);
      await ctx.reply("Failed to create wallet. Please try /start again.");
      return;
    }
  }

  const balance = await getBalance(user.wallet_address as Address).catch(() => "0");

  const text = [
    `Welcome to Strike!`,
    ``,
    `Your wallet:`,
    `\`${user.wallet_address}\``,
    `Balance: ${Number(balance).toFixed(4)} BNB`,
    ``,
    `Send BNB to your wallet address to start betting.`,
    ``,
    `What would you like to do?`,
  ].join("\n");

  await ctx.reply(text, {
    parse_mode: "Markdown",
    reply_markup: mainMenuKeyboard(),
  });
}
