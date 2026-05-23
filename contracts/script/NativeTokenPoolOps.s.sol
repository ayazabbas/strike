// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {NativeTokenParimutuelFactory} from "../src/NativeTokenParimutuelFactory.sol";
import {NativeTokenPoolReason} from "../src/NativeTokenPoolTypes.sol";

contract NativeTokenPoolOpsBase is Script {
    function _privateKey(string memory envName) internal view returns (uint256) {
        uint256 fallbackKey = vm.envOr("PRIVATE_KEY", uint256(0));
        uint256 pk = vm.envOr(envName, fallbackKey);
        require(pk != 0, "NativeTokenPoolOps: missing private key");
        return pk;
    }

    function _factory() internal view returns (NativeTokenParimutuelFactory) {
        return NativeTokenParimutuelFactory(vm.envAddress("NATIVE_TOKEN_POOL_FACTORY"));
    }

    function _marketId() internal view returns (uint256) {
        return vm.envUint("NATIVE_TOKEN_POOL_MARKET_ID");
    }

    function _reason() internal view returns (NativeTokenPoolReason) {
        uint256 reasonRaw = vm.envOr("NATIVE_TOKEN_POOL_REASON", uint256(NativeTokenPoolReason.Other));
        require(reasonRaw <= uint256(NativeTokenPoolReason.Other), "NativeTokenPoolOps: invalid reason");
        return NativeTokenPoolReason(reasonRaw);
    }

    function _reasonHash() internal view returns (bytes32) {
        return vm.envOr("NATIVE_TOKEN_POOL_REASON_HASH", bytes32(0));
    }
}

/// @notice Opens a challenge with the factory's current challenger bond.
/// @dev Dry-run first, then add --broadcast only after explicit deployment approval.
contract NativeTokenPoolOpenChallengeScript is NativeTokenPoolOpsBase {
    function run() external {
        uint256 pk = _privateKey("CHALLENGER_PRIVATE_KEY");
        NativeTokenParimutuelFactory factory = _factory();
        uint256 marketId = _marketId();
        uint256 bond = factory.challengerBondAmount();

        console.log("Opening native token pool challenge");
        console.log("  Factory:", address(factory));
        console.log("  Market ID:", marketId);
        console.log("  Challenger:", vm.addr(pk));
        console.log("  Bond wei:", bond);

        vm.startBroadcast(pk);
        factory.openChallenge{value: bond}(marketId, _reason(), _reasonHash());
        vm.stopBroadcast();
    }
}

/// @notice Adjudicates an open challenge as the pool admin.
/// @dev Set NATIVE_TOKEN_POOL_CHALLENGE_SUCCESSFUL=true to slash creator bond.
contract NativeTokenPoolAdjudicateChallengeScript is NativeTokenPoolOpsBase {
    function run() external {
        uint256 pk = _privateKey("ADMIN_PRIVATE_KEY");
        NativeTokenParimutuelFactory factory = _factory();
        uint256 marketId = _marketId();
        bool successful = vm.envBool("NATIVE_TOKEN_POOL_CHALLENGE_SUCCESSFUL");

        console.log("Adjudicating native token pool challenge");
        console.log("  Factory:", address(factory));
        console.log("  Market ID:", marketId);
        console.log("  Admin:", vm.addr(pk));
        console.log("  Successful:", successful);

        vm.startBroadcast(pk);
        factory.adjudicateChallenge(marketId, successful, _reason(), _reasonHash());
        vm.stopBroadcast();
    }
}

/// @notice Finalizes a terminal market after its challenge window has closed.
contract NativeTokenPoolFinalizeScript is NativeTokenPoolOpsBase {
    function run() external {
        uint256 pk = _privateKey("FINALIZER_PRIVATE_KEY");
        NativeTokenParimutuelFactory factory = _factory();
        uint256 marketId = _marketId();

        console.log("Finalizing native token pool market");
        console.log("  Factory:", address(factory));
        console.log("  Market ID:", marketId);
        console.log("  Finalizer:", vm.addr(pk));

        vm.startBroadcast(pk);
        factory.finalizeMarket(marketId);
        vm.stopBroadcast();
    }
}

/// @notice Withdraws pending BNB payouts for the signer.
contract NativeTokenPoolWithdrawNativePayoutScript is NativeTokenPoolOpsBase {
    function run() external {
        uint256 pk = _privateKey("WITHDRAWER_PRIVATE_KEY");
        NativeTokenParimutuelFactory factory = _factory();
        address withdrawer = vm.addr(pk);
        uint256 pending = factory.pendingNativePayouts(withdrawer);

        console.log("Withdrawing native token pool payout");
        console.log("  Factory:", address(factory));
        console.log("  Withdrawer:", withdrawer);
        console.log("  Pending wei:", pending);

        vm.startBroadcast(pk);
        uint256 amount = factory.withdrawNativePayout();
        vm.stopBroadcast();

        console.log("  Withdrawn wei:", amount);
    }
}
