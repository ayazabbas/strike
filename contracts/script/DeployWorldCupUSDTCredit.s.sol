// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {USDTCreditReserve} from "../src/USDTCreditReserve.sol";
import {USDTParimutuelV3Factory} from "../src/USDTParimutuelV3Factory.sol";
import {USDTParimutuelV3Manager} from "../src/USDTParimutuelV3Manager.sol";
import {USDTParimutuelV3Redemption} from "../src/USDTParimutuelV3Redemption.sol";
import {USDTParimutuelV3Vault} from "../src/USDTParimutuelV3Vault.sol";
import {WorldCupWinnerMarket} from "../src/WorldCupWinnerMarket.sol";

/// @notice Deploy and wire the isolated World Cup USDT credit stack.
/// @dev Required env:
///      PRIVATE_KEY or DEPLOYER_PRIVATE_KEY
///      Optional env:
///      WORLD_CUP_FINAL_ADMIN defaults to deployer
///      WORLD_CUP_FEE_RECIPIENT defaults to final admin
///      WORLD_CUP_USDT defaults to BSC-USD on BNB Chain
///      WORLD_CUP_RESOLVER defaults to Flap WorldCupResolver proxy on BNB Chain
///      WORLD_CUP_CREDIT_EVENT_ID defaults to 2026061101
///      WORLD_CUP_CREDIT_CLAIM_START defaults to block.timestamp
///      WORLD_CUP_CREDIT_CLAIM_END defaults to 2026-07-19 23:59:59 UTC
///      WORLD_CUP_CREDIT_EVENT_END defaults to 2026-08-01 23:59:59 UTC
///      WORLD_CUP_WINNER_FEE_BPS defaults to 200
///      USDT_PARIMUTUEL_V3_MARKET_CREATOR defaults to final admin
contract DeployWorldCupUSDTCreditScript is Script {
    address internal constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;
    address internal constant FLAP_WORLD_CUP_RESOLVER = 0x134C6b9562E226096947e018ddEe4804c9146921;
    uint256 internal constant DEFAULT_CREDIT_EVENT_ID = 2026061101;
    uint64 internal constant DEFAULT_CLAIM_END = 1_784_505_599; // 2026-07-19 23:59:59 UTC
    uint64 internal constant DEFAULT_EVENT_END = 1_785_628_799; // 2026-08-01 23:59:59 UTC
    uint16 internal constant DEFAULT_WINNER_FEE_BPS = 200;

    struct Deployed {
        address usdt;
        address creditReserve;
        address usdtParimutuelV3Factory;
        address usdtParimutuelV3Manager;
        address usdtParimutuelV3Vault;
        address usdtParimutuelV3Redemption;
        address worldCupWinnerMarket;
        address worldCupResolver;
        address admin;
        address feeRecipient;
        address marketCreator;
        uint256 creditEventId;
        uint64 claimStart;
        uint64 claimEnd;
        uint64 eventEnd;
        uint16 winnerFeeBps;
    }

    function run() external {
        uint256 pk = _privateKey();
        address deployer = vm.addr(pk);
        address finalAdmin = vm.envOr("WORLD_CUP_FINAL_ADMIN", deployer);
        address feeRecipient = vm.envOr("WORLD_CUP_FEE_RECIPIENT", finalAdmin);
        address marketCreator = vm.envOr("USDT_PARIMUTUEL_V3_MARKET_CREATOR", finalAdmin);
        address usdt = vm.envOr("WORLD_CUP_USDT", BSC_USDT);
        address resolver = vm.envOr("WORLD_CUP_RESOLVER", FLAP_WORLD_CUP_RESOLVER);
        uint256 creditEventId = vm.envOr("WORLD_CUP_CREDIT_EVENT_ID", DEFAULT_CREDIT_EVENT_ID);
        uint64 claimStart = uint64(vm.envOr("WORLD_CUP_CREDIT_CLAIM_START", block.timestamp));
        uint64 claimEnd = uint64(vm.envOr("WORLD_CUP_CREDIT_CLAIM_END", uint256(DEFAULT_CLAIM_END)));
        uint64 eventEnd = uint64(vm.envOr("WORLD_CUP_CREDIT_EVENT_END", uint256(DEFAULT_EVENT_END)));
        uint256 feeBpsRaw = vm.envOr("WORLD_CUP_WINNER_FEE_BPS", uint256(DEFAULT_WINNER_FEE_BPS));

        require(finalAdmin != address(0), "DeployWorldCup: zero final admin");
        require(feeRecipient != address(0), "DeployWorldCup: zero fee recipient");
        require(marketCreator != address(0), "DeployWorldCup: zero market creator");
        require(usdt != address(0), "DeployWorldCup: zero usdt");
        require(resolver != address(0), "DeployWorldCup: zero resolver");
        require(creditEventId != 0, "DeployWorldCup: zero event id");
        require(claimEnd > claimStart, "DeployWorldCup: invalid claim window");
        require(eventEnd >= claimEnd, "DeployWorldCup: invalid event end");
        require(feeBpsRaw <= 10_000, "DeployWorldCup: invalid fee bps");
        uint16 winnerFeeBps = uint16(feeBpsRaw);

        console.log("Deploying World Cup USDT credit stack...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  Final admin:", finalAdmin);
        console.log("  Fee recipient:", feeRecipient);
        console.log("  Market creator:", marketCreator);
        console.log("  USDT:", usdt);
        console.log("  WorldCupResolver:", resolver);
        console.log("  Credit event ID:", creditEventId);
        console.log("  Claim start:", claimStart);
        console.log("  Claim end:", claimEnd);
        console.log("  Event end:", eventEnd);
        console.log("  Winner fee bps:", winnerFeeBps);

        vm.startBroadcast(pk);

        USDTCreditReserve creditReserve = new USDTCreditReserve(deployer, usdt);
        USDTParimutuelV3Factory factory = new USDTParimutuelV3Factory(deployer);
        USDTParimutuelV3Vault vault = new USDTParimutuelV3Vault(deployer, usdt);
        USDTParimutuelV3Manager manager = new USDTParimutuelV3Manager(
            deployer, address(factory), address(vault), address(creditReserve), feeRecipient
        );
        USDTParimutuelV3Redemption redemption =
            new USDTParimutuelV3Redemption(deployer, address(manager), address(vault));
        WorldCupWinnerMarket winnerMarket = new WorldCupWinnerMarket(
            deployer, usdt, address(creditReserve), resolver, creditEventId, feeRecipient, winnerFeeBps
        );

        _wireProtocol(factory, vault, manager, redemption, creditReserve, winnerMarket, creditEventId, marketCreator);
        creditReserve.createEvent(creditEventId, claimStart, claimEnd, eventEnd);
        creditReserve.setAuthorizedMarket(creditEventId, address(manager), true);
        creditReserve.setAuthorizedMarket(creditEventId, address(winnerMarket), true);
        _handoffAdmin(factory, vault, manager, redemption, creditReserve, winnerMarket, deployer, finalAdmin);

        vm.stopBroadcast();

        Deployed memory d = Deployed({
            usdt: usdt,
            creditReserve: address(creditReserve),
            usdtParimutuelV3Factory: address(factory),
            usdtParimutuelV3Manager: address(manager),
            usdtParimutuelV3Vault: address(vault),
            usdtParimutuelV3Redemption: address(redemption),
            worldCupWinnerMarket: address(winnerMarket),
            worldCupResolver: resolver,
            admin: finalAdmin,
            feeRecipient: feeRecipient,
            marketCreator: marketCreator,
            creditEventId: creditEventId,
            claimStart: claimStart,
            claimEnd: claimEnd,
            eventEnd: eventEnd,
            winnerFeeBps: winnerFeeBps
        });

        _printJson(d);
    }

    function _wireProtocol(
        USDTParimutuelV3Factory factory,
        USDTParimutuelV3Vault vault,
        USDTParimutuelV3Manager manager,
        USDTParimutuelV3Redemption redemption,
        USDTCreditReserve,
        WorldCupWinnerMarket,
        uint256,
        address marketCreator
    ) internal {
        factory.setManager(address(manager));
        if (!factory.hasRole(factory.MARKET_CREATOR_ROLE(), marketCreator)) {
            factory.grantRole(factory.MARKET_CREATOR_ROLE(), marketCreator);
        }
        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));
    }

    function _handoffAdmin(
        USDTParimutuelV3Factory factory,
        USDTParimutuelV3Vault vault,
        USDTParimutuelV3Manager manager,
        USDTParimutuelV3Redemption redemption,
        USDTCreditReserve creditReserve,
        WorldCupWinnerMarket winnerMarket,
        address bootstrapAdmin,
        address finalAdmin
    ) internal {
        if (finalAdmin == bootstrapAdmin) {
            return;
        }

        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), finalAdmin);
        factory.grantRole(factory.ADMIN_ROLE(), finalAdmin);
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), finalAdmin);
        manager.grantRole(manager.DEFAULT_ADMIN_ROLE(), finalAdmin);
        manager.grantRole(manager.ADMIN_ROLE(), finalAdmin);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), finalAdmin);
        redemption.grantRole(redemption.DEFAULT_ADMIN_ROLE(), finalAdmin);
        redemption.grantRole(redemption.ADMIN_ROLE(), finalAdmin);
        creditReserve.grantRole(creditReserve.DEFAULT_ADMIN_ROLE(), finalAdmin);
        creditReserve.grantRole(creditReserve.ADMIN_ROLE(), finalAdmin);
        creditReserve.grantRole(creditReserve.CREDIT_SIGNER_ROLE(), finalAdmin);
        winnerMarket.grantRole(winnerMarket.DEFAULT_ADMIN_ROLE(), finalAdmin);
        winnerMarket.grantRole(winnerMarket.ADMIN_ROLE(), finalAdmin);

        factory.revokeRole(factory.MARKET_CREATOR_ROLE(), bootstrapAdmin);
        factory.revokeRole(factory.ADMIN_ROLE(), bootstrapAdmin);
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        manager.revokeRole(manager.ADMIN_ROLE(), bootstrapAdmin);
        manager.revokeRole(manager.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        redemption.revokeRole(redemption.ADMIN_ROLE(), bootstrapAdmin);
        redemption.revokeRole(redemption.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        creditReserve.revokeRole(creditReserve.CREDIT_SIGNER_ROLE(), bootstrapAdmin);
        creditReserve.revokeRole(creditReserve.ADMIN_ROLE(), bootstrapAdmin);
        creditReserve.revokeRole(creditReserve.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        winnerMarket.revokeRole(winnerMarket.ADMIN_ROLE(), bootstrapAdmin);
        winnerMarket.revokeRole(winnerMarket.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
    }

    function _privateKey() internal view returns (uint256) {
        uint256 fallbackKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        uint256 pk = vm.envOr("PRIVATE_KEY", fallbackKey);
        require(pk != 0, "DeployWorldCup: missing private key");
        return pk;
    }

    function _printJson(Deployed memory d) internal pure {
        string memory json = string.concat(
            '{"usdt":"',
            vm.toString(d.usdt),
            '","usdtCreditReserve":"',
            vm.toString(d.creditReserve),
            '","usdtParimutuelV3Factory":"',
            vm.toString(d.usdtParimutuelV3Factory),
            '","usdtParimutuelV3Manager":"',
            vm.toString(d.usdtParimutuelV3Manager),
            '","usdtParimutuelV3Vault":"',
            vm.toString(d.usdtParimutuelV3Vault),
            '","usdtParimutuelV3Redemption":"',
            vm.toString(d.usdtParimutuelV3Redemption),
            '","worldCupWinnerMarket":"',
            vm.toString(d.worldCupWinnerMarket)
        );
        json = string.concat(
            json,
            '","worldCupResolver":"',
            vm.toString(d.worldCupResolver),
            '","admin":"',
            vm.toString(d.admin),
            '","feeRecipient":"',
            vm.toString(d.feeRecipient),
            '","marketCreator":"',
            vm.toString(d.marketCreator),
            '","creditEventId":"',
            vm.toString(d.creditEventId),
            '","claimStart":"',
            vm.toString(d.claimStart),
            '","claimEnd":"',
            vm.toString(d.claimEnd),
            '","eventEnd":"',
            vm.toString(d.eventEnd),
            '","winnerFeeBps":"',
            vm.toString(d.winnerFeeBps),
            '"}'
        );
        console.log(json);
    }
}
