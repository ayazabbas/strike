// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {StrikeDuelsWagerVault} from "../src/StrikeDuelsWagerVault.sol";

/// @notice Dry-run-first deployment helper for Strike Duels wager escrow.
/// @dev Broadcast is approval-required. Run without --broadcast first.
contract DeployStrikeDuelsWagerVaultScript is Script {
    address internal constant DEFAULT_STRIKE_TOKEN = 0xDccC017B0F923Cf3F3ACDB535eb1019439717777;
    uint256 internal constant DEFAULT_AI_STAKE = 50_000 ether;
    uint256 internal constant DEFAULT_AI_REWARD = 50_000 ether;
    uint16 internal constant DEFAULT_PVP_FEE_BPS = 500;
    uint256 internal constant DEFAULT_MAX_PVP_STAKE = 0.01 ether;
    uint256 internal constant DEFAULT_MAX_AI_REWARD_EXPOSURE = 5_000_000 ether;
    uint256 internal constant DEFAULT_PVP_BRACKET_SMALL = 0.001 ether;
    uint256 internal constant DEFAULT_PVP_BRACKET_LARGE = 0.01 ether;

    struct Deployed {
        address vault;
        address strikeToken;
        address admin;
        address treasury;
        address settler;
        uint256 aiStakeAmount;
        uint256 aiWinRewardAmount;
        uint16 pvpFeeBps;
        uint256 maxPvpStakeAmount;
        uint256 maxAiRewardExposure;
        uint256 pvpBracketSmall;
        uint256 pvpBracketLarge;
    }

    function run() external {
        uint256 pk = _privateKey();
        address deployer = vm.addr(pk);
        address strikeToken = vm.envOr("DUELS_STRIKE_TOKEN", DEFAULT_STRIKE_TOKEN);
        address finalAdmin = vm.envOr("DUELS_WAGER_ADMIN", deployer);
        address treasury = vm.envOr("DUELS_WAGER_TREASURY", finalAdmin);
        address settler = vm.envOr("DUELS_WAGER_SETTLER", finalAdmin);
        uint256 aiStakeAmount = vm.envOr("DUELS_AI_STAKE_AMOUNT", DEFAULT_AI_STAKE);
        uint256 aiWinRewardAmount = vm.envOr("DUELS_AI_WIN_REWARD_AMOUNT", DEFAULT_AI_REWARD);
        uint256 pvpFeeBpsRaw = vm.envOr("DUELS_PVP_FEE_BPS", uint256(DEFAULT_PVP_FEE_BPS));
        uint256 maxPvpStakeAmount = vm.envOr("DUELS_MAX_PVP_STAKE_WEI", DEFAULT_MAX_PVP_STAKE);
        uint256 maxAiRewardExposure = vm.envOr("DUELS_MAX_AI_REWARD_EXPOSURE", DEFAULT_MAX_AI_REWARD_EXPOSURE);
        uint256 pvpBracketSmall = vm.envOr("DUELS_PVP_BRACKET_SMALL_WEI", DEFAULT_PVP_BRACKET_SMALL);
        uint256 pvpBracketLarge = vm.envOr("DUELS_PVP_BRACKET_LARGE_WEI", DEFAULT_PVP_BRACKET_LARGE);

        require(pvpFeeBpsRaw <= type(uint16).max, "DeployDuels: fee bps overflow");
        uint16 pvpFeeBps = uint16(pvpFeeBpsRaw);

        console.log("Deploying StrikeDuelsWagerVault (dry-run unless --broadcast is supplied)...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  STRIKE token:", strikeToken);
        console.log("  Admin:", finalAdmin);
        console.log("  Treasury:", treasury);
        console.log("  Settler:", settler);
        console.log("  AI stake:", aiStakeAmount);
        console.log("  AI win reward:", aiWinRewardAmount);
        console.log("  PvP fee bps:", pvpFeeBps);
        console.log("  Max PvP stake:", maxPvpStakeAmount);
        console.log("  Max AI exposure:", maxAiRewardExposure);

        vm.startBroadcast(pk);
        StrikeDuelsWagerVault vault = new StrikeDuelsWagerVault(
            strikeToken,
            deployer,
            treasury,
            settler,
            aiStakeAmount,
            aiWinRewardAmount,
            pvpFeeBps,
            maxPvpStakeAmount,
            maxAiRewardExposure
        );
        vault.setPvpBracket(pvpBracketSmall, true);
        vault.setPvpBracket(pvpBracketLarge, true);
        if (finalAdmin != deployer) {
            vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), finalAdmin);
            vault.grantRole(vault.PAUSER_ROLE(), finalAdmin);
            vault.grantRole(vault.TREASURY_ROLE(), finalAdmin);
            vault.renounceRole(vault.PAUSER_ROLE(), deployer);
            vault.renounceRole(vault.TREASURY_ROLE(), deployer);
            vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), deployer);
        }
        vm.stopBroadcast();

        _printJson(
            Deployed({
                vault: address(vault),
                strikeToken: strikeToken,
                admin: finalAdmin,
                treasury: treasury,
                settler: settler,
                aiStakeAmount: aiStakeAmount,
                aiWinRewardAmount: aiWinRewardAmount,
                pvpFeeBps: pvpFeeBps,
                maxPvpStakeAmount: maxPvpStakeAmount,
                maxAiRewardExposure: maxAiRewardExposure,
                pvpBracketSmall: pvpBracketSmall,
                pvpBracketLarge: pvpBracketLarge
            })
        );
    }

    function _privateKey() internal view returns (uint256) {
        uint256 pk = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        if (pk == 0) pk = vm.envOr("PRIVATE_KEY", uint256(0));
        require(pk != 0, "DeployDuels: set DEPLOYER_PRIVATE_KEY or PRIVATE_KEY for dry-run");
        return pk;
    }

    function _printJson(Deployed memory d) internal pure {
        console.log("{");
        console.log('  "vault": "%s",', d.vault);
        console.log('  "strikeToken": "%s",', d.strikeToken);
        console.log('  "admin": "%s",', d.admin);
        console.log('  "treasury": "%s",', d.treasury);
        console.log('  "settler": "%s",', d.settler);
        console.log('  "aiStakeAmount": %s,', d.aiStakeAmount);
        console.log('  "aiWinRewardAmount": %s,', d.aiWinRewardAmount);
        console.log('  "pvpFeeBps": %s,', d.pvpFeeBps);
        console.log('  "maxPvpStakeAmount": %s,', d.maxPvpStakeAmount);
        console.log('  "maxAiRewardExposure": %s,', d.maxAiRewardExposure);
        console.log('  "pvpBracketSmall": %s,', d.pvpBracketSmall);
        console.log('  "pvpBracketLarge": %s', d.pvpBracketLarge);
        console.log("}");
    }
}
