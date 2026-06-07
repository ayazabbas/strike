// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {StrikeDuelsWagerVault} from "../src/StrikeDuelsWagerVault.sol";

/// @notice Dry-run-first deployment helper for Strike Duels wager escrow.
/// @dev Broadcast is approval-required. Run without --broadcast first.
contract DeployStrikeDuelsWagerVaultScript is Script {
    address internal constant DEFAULT_STRIKE_TOKEN = 0xDccC017B0F923Cf3F3ACDB535eb1019439717777;
    uint256 internal constant DEFAULT_AI_STAKE = 20_000 ether;
    uint256 internal constant DEFAULT_AI_REWARD = 20_000 ether;
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
        bool pvpBracketsEnabled;
        uint256 pvpBracketSmall;
        uint256 pvpBracketLarge;
    }

    function run() external {
        uint256 pk = _privateKey();
        address deployer = vm.addr(pk);
        Deployed memory d;
        d.strikeToken = vm.envOr("DUELS_STRIKE_TOKEN", DEFAULT_STRIKE_TOKEN);
        d.admin = vm.envOr("DUELS_WAGER_ADMIN", deployer);
        d.treasury = vm.envOr("DUELS_WAGER_TREASURY", d.admin);
        d.settler = vm.envOr("DUELS_WAGER_SETTLER", d.admin);
        d.aiStakeAmount = vm.envOr("DUELS_AI_STAKE_AMOUNT", DEFAULT_AI_STAKE);
        d.aiWinRewardAmount = vm.envOr("DUELS_AI_WIN_REWARD_AMOUNT", DEFAULT_AI_REWARD);
        uint256 pvpFeeBpsRaw = vm.envOr("DUELS_PVP_FEE_BPS", uint256(DEFAULT_PVP_FEE_BPS));
        d.maxPvpStakeAmount = vm.envOr("DUELS_MAX_PVP_STAKE_WEI", DEFAULT_MAX_PVP_STAKE);
        d.maxAiRewardExposure = vm.envOr("DUELS_MAX_AI_REWARD_EXPOSURE", DEFAULT_MAX_AI_REWARD_EXPOSURE);
        d.pvpBracketsEnabled = vm.envOr("DUELS_ENABLE_PVP_BRACKETS", false);
        d.pvpBracketSmall = vm.envOr("DUELS_PVP_BRACKET_SMALL_WEI", DEFAULT_PVP_BRACKET_SMALL);
        d.pvpBracketLarge = vm.envOr("DUELS_PVP_BRACKET_LARGE_WEI", DEFAULT_PVP_BRACKET_LARGE);

        require(pvpFeeBpsRaw <= type(uint16).max, "DeployDuels: fee bps overflow");
        d.pvpFeeBps = uint16(pvpFeeBpsRaw);

        console.log("Deploying StrikeDuelsWagerVault (dry-run unless --broadcast is supplied)...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  STRIKE token:", d.strikeToken);
        console.log("  Admin:", d.admin);
        console.log("  Treasury:", d.treasury);
        console.log("  Settler:", d.settler);
        console.log("  AI stake:", d.aiStakeAmount);
        console.log("  AI win reward:", d.aiWinRewardAmount);
        console.log("  PvP fee bps:", d.pvpFeeBps);
        console.log("  Max PvP stake:", d.maxPvpStakeAmount);
        console.log("  Max AI exposure:", d.maxAiRewardExposure);
        console.log("  PvP brackets enabled:", d.pvpBracketsEnabled);

        vm.startBroadcast(pk);
        StrikeDuelsWagerVault vault = new StrikeDuelsWagerVault(
            d.strikeToken,
            deployer,
            d.treasury,
            d.settler,
            d.aiStakeAmount,
            d.aiWinRewardAmount,
            d.pvpFeeBps,
            d.maxPvpStakeAmount,
            d.maxAiRewardExposure
        );
        if (d.pvpBracketsEnabled) {
            vault.setPvpBracket(d.pvpBracketSmall, true);
            vault.setPvpBracket(d.pvpBracketLarge, true);
        }
        if (d.admin != deployer) {
            vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), d.admin);
            vault.grantRole(vault.PAUSER_ROLE(), d.admin);
            vault.grantRole(vault.TREASURY_ROLE(), d.admin);
            vault.renounceRole(vault.PAUSER_ROLE(), deployer);
            vault.renounceRole(vault.TREASURY_ROLE(), deployer);
            vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), deployer);
        }
        vm.stopBroadcast();

        d.vault = address(vault);
        _printJson(d);
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
        console.log(d.pvpBracketsEnabled ? '  "pvpBracketsEnabled": true,' : '  "pvpBracketsEnabled": false,');
        console.log('  "pvpBracketSmall": %s,', d.pvpBracketSmall);
        console.log('  "pvpBracketLarge": %s', d.pvpBracketLarge);
        console.log("}");
    }
}
