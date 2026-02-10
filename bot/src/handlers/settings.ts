import { type Context, InlineKeyboard } from "grammy";
import { getUser } from "../db/database.js";
import { config } from "../config.js";

export async function handleSettings(ctx: Context) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);
  const network = config.chainId === 56 ? "BSC Mainnet" : "BSC Testnet";

  const text = [
    `Settings\n`,
    `Network: ${network}`,
    `User ID: ${telegramId}`,
    user ? `Wallet: \`${user.wallet_address}\`` : "No wallet created",
    ``,
    `Strike Bot v0.1.0`,
  ].join("\n");

  await ctx.editMessageText(text, {
    parse_mode: "Markdown",
    reply_markup: new InlineKeyboard().text("Back", "main"),
  });
}
