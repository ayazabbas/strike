// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ParimutuelAIResolver} from "../src/ParimutuelAIResolver.sol";
import {ParimutuelPythResolver} from "../src/ParimutuelPythResolver.sol";
import {StrikeCreditReserve} from "../src/StrikeCreditReserve.sol";
import {StrikeParimutuelFactory} from "../src/StrikeParimutuelFactory.sol";
import {StrikePoolManager} from "../src/StrikePoolManager.sol";
import {StrikePoolRedemption} from "../src/StrikePoolRedemption.sol";
import {StrikePoolVault} from "../src/StrikePoolVault.sol";

/// @notice Deploy the isolated STRIKE-denominated pool protocol and wire bootstrap roles.
/// @dev Required env:
///      PRIVATE_KEY or DEPLOYER_PRIVATE_KEY
///      STRIKE_ADDRESS
///      PYTH_ADDRESS
///      Optional env:
///      STRIKE_POOL_FINAL_ADMIN defaults to deployer
///      STRIKE_POOL_FEE_RECIPIENT defaults to final admin
///      STRIKE_POOL_MARKET_CREATOR defaults to final admin
///      STRIKE_POOL_KEEPER defaults to final admin
///      STRIKE_POOL_CREDIT_SIGNER defaults to final admin
contract DeployStrikePoolScript is Script {
    uint256 internal constant INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED = 40_000e18;
    uint256 internal constant INDEPENDENT_LOG_LIQUIDITY_CONSERVATIVE = 100_000e18;

    struct Deployed {
        address factory;
        address manager;
        address vault;
        address redemption;
        address creditReserve;
        address aiResolver;
        address pythResolver;
        address strikeToken;
        address admin;
        address feeRecipient;
        address marketCreator;
        address keeper;
        address creditSigner;
    }

    function run() external {
        uint256 pk = _privateKey();
        address deployer = vm.addr(pk);
        address finalAdmin = vm.envOr("STRIKE_POOL_FINAL_ADMIN", deployer);
        address strikeToken = vm.envAddress("STRIKE_ADDRESS");
        address pythAddress = vm.envAddress("PYTH_ADDRESS");
        address feeRecipient = vm.envOr("STRIKE_POOL_FEE_RECIPIENT", finalAdmin);
        address marketCreator = vm.envOr("STRIKE_POOL_MARKET_CREATOR", finalAdmin);
        address keeper = vm.envOr("STRIKE_POOL_KEEPER", finalAdmin);
        address creditSigner = vm.envOr("STRIKE_POOL_CREDIT_SIGNER", finalAdmin);

        require(finalAdmin != address(0), "DeployStrikePool: zero final admin");
        require(strikeToken != address(0), "DeployStrikePool: zero strike token");
        require(pythAddress != address(0), "DeployStrikePool: zero pyth");
        require(feeRecipient != address(0), "DeployStrikePool: zero fee recipient");
        require(marketCreator != address(0), "DeployStrikePool: zero creator");
        require(keeper != address(0), "DeployStrikePool: zero keeper");
        require(creditSigner != address(0), "DeployStrikePool: zero credit signer");

        console.log("Deploying STRIKE pool protocol...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  Final admin:", finalAdmin);
        console.log("  STRIKE:", strikeToken);
        console.log("  Pyth:", pythAddress);
        console.log("  Fee recipient:", feeRecipient);
        console.log("  Market creator:", marketCreator);
        console.log("  Keeper:", keeper);
        console.log("  Credit signer:", creditSigner);

        vm.startBroadcast(pk);

        StrikeParimutuelFactory factory = new StrikeParimutuelFactory(deployer);
        StrikePoolVault vault = new StrikePoolVault(deployer, strikeToken);
        StrikeCreditReserve creditReserve = new StrikeCreditReserve(deployer, strikeToken);
        StrikePoolManager manager =
            new StrikePoolManager(deployer, address(factory), address(vault), address(creditReserve), feeRecipient);
        StrikePoolRedemption redemption =
            new StrikePoolRedemption(deployer, address(manager), address(vault), address(creditReserve));
        ParimutuelAIResolver aiResolver = new ParimutuelAIResolver(address(factory), feeRecipient);
        ParimutuelPythResolver pythResolver = new ParimutuelPythResolver(pythAddress, address(factory));

        _wireRoles(
            factory,
            manager,
            vault,
            redemption,
            creditReserve,
            aiResolver,
            pythResolver,
            deployer,
            finalAdmin,
            marketCreator,
            keeper,
            creditSigner
        );

        vm.stopBroadcast();

        Deployed memory d = Deployed({
            factory: address(factory),
            manager: address(manager),
            vault: address(vault),
            redemption: address(redemption),
            creditReserve: address(creditReserve),
            aiResolver: address(aiResolver),
            pythResolver: address(pythResolver),
            strikeToken: strikeToken,
            admin: finalAdmin,
            feeRecipient: feeRecipient,
            marketCreator: marketCreator,
            keeper: keeper,
            creditSigner: creditSigner
        });

        _printJson(d);
    }

    function _wireRoles(
        StrikeParimutuelFactory factory,
        StrikePoolManager manager,
        StrikePoolVault vault,
        StrikePoolRedemption redemption,
        StrikeCreditReserve creditReserve,
        ParimutuelAIResolver aiResolver,
        ParimutuelPythResolver pythResolver,
        address bootstrapAdmin,
        address finalAdmin,
        address marketCreator,
        address keeper,
        address creditSigner
    ) internal {
        factory.setPoolManager(address(manager));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), marketCreator);
        factory.grantRole(factory.RESOLVER_ROLE(), address(aiResolver));
        factory.grantRole(factory.RESOLVER_ROLE(), address(pythResolver));

        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));

        creditReserve.grantRole(creditReserve.SPENDER_ROLE(), address(manager));
        creditReserve.grantRole(creditReserve.SPENDER_ROLE(), address(redemption));
        creditReserve.grantRole(creditReserve.CREDIT_SIGNER_ROLE(), creditSigner);

        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));
        aiResolver.grantRole(aiResolver.KEEPER_ROLE(), keeper);

        if (marketCreator != finalAdmin) {
            factory.grantRole(factory.MARKET_CREATOR_ROLE(), finalAdmin);
        }

        _handoffAdmin(
            factory,
            manager,
            vault,
            redemption,
            creditReserve,
            aiResolver,
            pythResolver,
            bootstrapAdmin,
            finalAdmin,
            creditSigner
        );
    }

    function _handoffAdmin(
        StrikeParimutuelFactory factory,
        StrikePoolManager manager,
        StrikePoolVault vault,
        StrikePoolRedemption redemption,
        StrikeCreditReserve creditReserve,
        ParimutuelAIResolver aiResolver,
        ParimutuelPythResolver pythResolver,
        address bootstrapAdmin,
        address finalAdmin,
        address creditSigner
    ) internal {
        if (finalAdmin == bootstrapAdmin) {
            return;
        }

        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), finalAdmin);
        factory.grantRole(factory.ADMIN_ROLE(), finalAdmin);
        manager.grantRole(manager.DEFAULT_ADMIN_ROLE(), finalAdmin);
        manager.grantRole(manager.ADMIN_ROLE(), finalAdmin);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), finalAdmin);
        redemption.grantRole(redemption.DEFAULT_ADMIN_ROLE(), finalAdmin);
        redemption.grantRole(redemption.ADMIN_ROLE(), finalAdmin);
        creditReserve.grantRole(creditReserve.DEFAULT_ADMIN_ROLE(), finalAdmin);
        creditReserve.grantRole(creditReserve.ADMIN_ROLE(), finalAdmin);
        aiResolver.setAdmin(finalAdmin);
        pythResolver.setPendingAdmin(finalAdmin);

        factory.revokeRole(factory.ADMIN_ROLE(), bootstrapAdmin);
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        manager.revokeRole(manager.ADMIN_ROLE(), bootstrapAdmin);
        manager.revokeRole(manager.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        redemption.revokeRole(redemption.ADMIN_ROLE(), bootstrapAdmin);
        redemption.revokeRole(redemption.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        creditReserve.revokeRole(creditReserve.ADMIN_ROLE(), bootstrapAdmin);
        creditReserve.revokeRole(creditReserve.DEFAULT_ADMIN_ROLE(), bootstrapAdmin);
        if (creditSigner != bootstrapAdmin) {
            creditReserve.revokeRole(creditReserve.CREDIT_SIGNER_ROLE(), bootstrapAdmin);
        }
    }

    function _privateKey() internal view returns (uint256) {
        uint256 fallbackKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        uint256 pk = vm.envOr("PRIVATE_KEY", fallbackKey);
        require(pk != 0, "DeployStrikePool: missing private key");
        return pk;
    }

    function _printJson(Deployed memory d) internal pure {
        string memory json = string.concat(
            '{"strikeParimutuelFactory":"',
            vm.toString(d.factory),
            '","strikePoolManager":"',
            vm.toString(d.manager),
            '","strikePoolVault":"',
            vm.toString(d.vault),
            '","strikePoolRedemption":"',
            vm.toString(d.redemption),
            '","strikeCreditReserve":"',
            vm.toString(d.creditReserve),
            '","strikePoolAIResolver":"',
            vm.toString(d.aiResolver),
            '","strikePoolPythResolver":"',
            vm.toString(d.pythResolver),
            '","strikeToken":"',
            vm.toString(d.strikeToken)
        );
        json = string.concat(
            json,
            '","admin":"',
            vm.toString(d.admin),
            '","feeRecipient":"',
            vm.toString(d.feeRecipient),
            '","marketCreator":"',
            vm.toString(d.marketCreator),
            '","keeper":"',
            vm.toString(d.keeper),
            '","creditSigner":"',
            vm.toString(d.creditSigner),
            '","independentLogLiquidityRecommended":"',
            vm.toString(INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED),
            '","independentLogLiquidityConservative":"',
            vm.toString(INDEPENDENT_LOG_LIQUIDITY_CONSERVATIVE),
            '"}'
        );
        console.log(json);
    }
}
