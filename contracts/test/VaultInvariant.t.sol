// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/Vault.sol";

/// @notice Invariant test: Vault BNB balance == sum of all account balances + all known market pools.
contract VaultInvariantTest is Test {
    Vault public vault;
    VaultHandler public handler;

    address public admin = address(0x1);

    function setUp() public {
        vm.startPrank(admin);
        vault = new Vault(admin);
        handler = new VaultHandler(vault);
        vault.grantRole(vault.PROTOCOL_ROLE(), address(handler));
        vm.stopPrank();

        // Fund all actors
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            vm.deal(actors[i], 100 ether);
        }

        targetContract(address(handler));
    }

    function invariant_VaultBalance_EqSumOfAccounts() public view {
        uint256 totalAccountBalances;
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            totalAccountBalances += vault.balance(actors[i]);
        }

        uint256 totalPools;
        uint256[] memory mIds = handler.getMarketIds();
        for (uint256 i = 0; i < mIds.length; i++) {
            totalPools += vault.marketPool(mIds[i]);
        }

        assertEq(
            address(vault).balance,
            totalAccountBalances + totalPools,
            "Vault BNB != sum(balances) + sum(pools)"
        );
    }
}

contract VaultHandler is Test {
    Vault public vault;

    address[5] internal _actors;
    uint256[] public marketIds;
    mapping(uint256 => bool) public isMarket;

    constructor(Vault _vault) {
        vault = _vault;
        _actors[0] = address(0x1001);
        _actors[1] = address(0x1002);
        _actors[2] = address(0x1003);
        _actors[3] = address(0x1004);
        _actors[4] = address(0x1005);
    }

    function getActors() public view returns (address[] memory out) {
        out = new address[](5);
        for (uint256 i = 0; i < 5; i++) out[i] = _actors[i];
    }

    function getMarketIds() external view returns (uint256[] memory) {
        return marketIds;
    }

    function deposit(uint256 actorIdx, uint256 amount) external {
        address actor = _actors[actorIdx % 5];
        amount = bound(amount, 1 wei, 10 ether);
        if (actor.balance < amount) return;

        vm.prank(actor);
        vault.deposit{value: amount}();
    }

    function withdraw(uint256 actorIdx, uint256 amount) external {
        address actor = _actors[actorIdx % 5];
        uint256 avail = vault.available(actor);
        if (avail == 0) return;
        amount = bound(amount, 1, avail);

        vm.prank(actor);
        vault.withdraw(amount);
    }

    function lock(uint256 actorIdx, uint256 amount) external {
        address actor = _actors[actorIdx % 5];
        uint256 avail = vault.available(actor);
        if (avail == 0) return;
        amount = bound(amount, 1, avail);

        vault.lock(actor, amount);
    }

    function unlock(uint256 actorIdx, uint256 amount) external {
        address actor = _actors[actorIdx % 5];
        uint256 lck = vault.locked(actor);
        if (lck == 0) return;
        amount = bound(amount, 1, lck);

        vault.unlock(actor, amount);
    }

    function addToPool(uint256 actorIdx, uint256 mktIdx, uint256 amount) external {
        address actor = _actors[actorIdx % 5];
        uint256 lck = vault.locked(actor);
        if (lck == 0) return;
        amount = bound(amount, 1, lck);

        uint256 mId = (mktIdx % 10) + 1;
        if (!isMarket[mId]) {
            marketIds.push(mId);
            isMarket[mId] = true;
        }

        vault.addToMarketPool(actor, mId, amount);
    }
}
