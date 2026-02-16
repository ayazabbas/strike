import { type Context, InlineKeyboard } from "grammy";
import { getUser, getQuickBetAmounts, setQuickBetAmount } from "../db/database.js";
import { config } from "../config.js";

export async function handleSettings(ctx: Context) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);
  const network = config.chainId === 56 ? "BSC Mainnet" : "BSC Testnet";
  const amounts = getQuickBetAmounts(telegramId);

  const text = [
    `⚙️ Settings\n`,
    `Network: ${network}`,
    `User ID: ${telegramId}`,
    user ? `Wallet: \`${user.wallet_address}\`` : "No wallet created",
    ``,
    `Quick-bet amounts:`,
    `  1️⃣  ${amounts[0]} BNB`,
    `  2️⃣  ${amounts[1]} BNB`,
    `  3️⃣  ${amounts[2]} BNB`,
    ``,
    `Tap a button below to change an amount.`,
  ].join("\n");

  const kb = new InlineKeyboard()
    .text(`1️⃣ ${amounts[0]}`, "setbet:1")
    .text(`2️⃣ ${amounts[1]}`, "setbet:2")
    .text(`3️⃣ ${amounts[2]}`, "setbet:3")
    .row()
    .text("🔄 Reset Defaults", "setbet:reset")
    .row()
    .text("« Back", "main");

  try {
    await ctx.editMessageText(text, { parse_mode: "Markdown", reply_markup: kb });
  } catch {
    await ctx.reply(text, { parse_mode: "Markdown", reply_markup: kb });
  }
}

export async function handleSetBetPrompt(ctx: Context, slot: number) {
  const telegramId = ctx.from!.id;
  const amounts = getQuickBetAmounts(telegramId);

  await ctx.editMessageText(
    `Enter new amount for quick-bet button ${slot} (currently ${amounts[slot - 1]} BNB):\n\nMinimum: 0.001 BNB`,
    {
      reply_markup: new InlineKeyboard().text("Cancel", "settings"),
    }
  );
}

export async function handleSetBetReset(ctx: Context) {
  const telegramId = ctx.from!.id;
  setQuickBetAmount(telegramId, 1, "0.01");
  setQuickBetAmount(telegramId, 2, "0.05");
  setQuickBetAmount(telegramId, 3, "0.1");
  await handleSettings(ctx);
}

// Tracks users awaiting quick-bet setting input
export const pendingSettingsInput = new Map<number, number>(); // telegramId -> slot (1-3)

export async function handleSettingsAmountInput(ctx: Context): Promise<boolean> {
  const telegramId = ctx.from!.id;
  const slot = pendingSettingsInput.get(telegramId);
  if (!slot) return false;

  const text = ctx.message?.text?.trim();
  if (!text) return false;

  const amount = parseFloat(text);
  if (isNaN(amount) || amount < 0.001 || amount > 100) {
    await ctx.reply("Invalid amount. Enter a value between 0.001 and 100 BNB:");
    return true;
  }

  pendingSettingsInput.delete(telegramId);

  const amountStr = parseFloat(amount.toFixed(6)).toString();
  setQuickBetAmount(telegramId, slot as 1 | 2 | 3, amountStr);

  const amounts = getQuickBetAmounts(telegramId);
  const confirmText = [
    `✅ Quick-bet button ${slot} set to ${amountStr} BNB\n`,
    `Your quick-bet amounts:`,
    `  1️⃣  ${amounts[0]} BNB`,
    `  2️⃣  ${amounts[1]} BNB`,
    `  3️⃣  ${amounts[2]} BNB`,
  ].join("\n");

  const kb = new InlineKeyboard()
    .text(`1️⃣ ${amounts[0]}`, "setbet:1")
    .text(`2️⃣ ${amounts[1]}`, "setbet:2")
    .text(`3️⃣ ${amounts[2]}`, "setbet:3")
    .row()
    .text("« Back", "main");

  await ctx.reply(confirmText, { reply_markup: kb });
  return true;
}
