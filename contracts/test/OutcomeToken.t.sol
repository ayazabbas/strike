// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/OutcomeToken.sol";

contract OutcomeTokenTest is Test {
    OutcomeToken public token;

    address public admin = address(0x1);
    address public minter = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public unauthorized = address(0x5);

    function setUp() public {
        vm.startPrank(admin);
        token = new OutcomeToken(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Token ID scheme
    // -------------------------------------------------------------------------

    function test_TokenIdScheme_YES() public view {
        // marketId * 2 = YES token
        assertEq(token.yesTokenId(0), 0);
        assertEq(token.yesTokenId(1), 2);
        assertEq(token.yesTokenId(5), 10);
        assertEq(token.yesTokenId(100), 200);
    }

    function test_TokenIdScheme_NO() public view {
        // marketId * 2 + 1 = NO token
        assertEq(token.noTokenId(0), 1);
        assertEq(token.noTokenId(1), 3);
        assertEq(token.noTokenId(5), 11);
        assertEq(token.noTokenId(100), 201);
    }

    function test_TokenIdScheme_NeverCollide() public view {
        // YES and NO for same market never collide
        for (uint256 i = 0; i < 10; i++) {
            assertTrue(token.yesTokenId(i) != token.noTokenId(i));
        }
        // YES of market i != NO of market j for adjacent markets
        for (uint256 i = 0; i < 9; i++) {
            assertTrue(token.noTokenId(i) != token.yesTokenId(i + 1));
        }
    }

    // -------------------------------------------------------------------------
    // mintPair
    // -------------------------------------------------------------------------

    function test_MintPair_BasicMint() public {
        vm.prank(minter);
        token.mintPair(user1, 1, 100);

        assertEq(token.balanceOf(user1, token.yesTokenId(1)), 100);
        assertEq(token.balanceOf(user1, token.noTokenId(1)), 100);
    }

    function test_MintPair_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit OutcomeToken.PairMinted(user1, 1, 50);

        vm.prank(minter);
        token.mintPair(user1, 1, 50);
    }

    function test_MintPair_DifferentMarkets() public {
        vm.startPrank(minter);
        token.mintPair(user1, 0, 10);
        token.mintPair(user1, 1, 20);
        token.mintPair(user1, 5, 30);
        vm.stopPrank();

        assertEq(token.balanceOf(user1, token.yesTokenId(0)), 10);
        assertEq(token.balanceOf(user1, token.noTokenId(0)), 10);
        assertEq(token.balanceOf(user1, token.yesTokenId(1)), 20);
        assertEq(token.balanceOf(user1, token.noTokenId(1)), 20);
        assertEq(token.balanceOf(user1, token.yesTokenId(5)), 30);
        assertEq(token.balanceOf(user1, token.noTokenId(5)), 30);
    }

    function test_MintPair_MultipleUsers() public {
        vm.startPrank(minter);
        token.mintPair(user1, 1, 100);
        token.mintPair(user2, 1, 200);
        vm.stopPrank();

        assertEq(token.balanceOf(user1, token.yesTokenId(1)), 100);
        assertEq(token.balanceOf(user2, token.yesTokenId(1)), 200);
    }

    function test_MintPair_RevertOnZeroAmount() public {
        vm.expectRevert("OutcomeToken: zero amount");
        vm.prank(minter);
        token.mintPair(user1, 1, 0);
    }

    function test_MintPair_RevertIfNotMinter() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        token.mintPair(user1, 1, 100);
    }

    function test_MintPair_RevertIfAdmin() public {
        // Admin doesn't have MINTER_ROLE by default
        vm.expectRevert();
        vm.prank(admin);
        token.mintPair(user1, 1, 100);
    }

    // -------------------------------------------------------------------------
    // burnPair
    // -------------------------------------------------------------------------

    function test_BurnPair_Basic() public {
        vm.startPrank(minter);
        token.mintPair(user1, 1, 100);
        token.burnPair(user1, 1, 40);
        vm.stopPrank();

        assertEq(token.balanceOf(user1, token.yesTokenId(1)), 60);
        assertEq(token.balanceOf(user1, token.noTokenId(1)), 60);
    }

    function test_BurnPair_Full() public {
        vm.startPrank(minter);
        token.mintPair(user1, 2, 50);
        token.burnPair(user1, 2, 50);
        vm.stopPrank();

        assertEq(token.balanceOf(user1, token.yesTokenId(2)), 0);
        assertEq(token.balanceOf(user1, token.noTokenId(2)), 0);
    }

    function test_BurnPair_EmitsEvent() public {
        vm.prank(minter);
        token.mintPair(user1, 3, 100);

        vm.expectEmit(true, true, false, true);
        emit OutcomeToken.PairBurned(user1, 3, 30);

        vm.prank(minter);
        token.burnPair(user1, 3, 30);
    }

    function test_BurnPair_RevertOnZeroAmount() public {
        vm.expectRevert("OutcomeToken: zero amount");
        vm.prank(minter);
        token.burnPair(user1, 1, 0);
    }

    function test_BurnPair_RevertIfInsufficient() public {
        vm.prank(minter);
        token.mintPair(user1, 1, 10);

        vm.expectRevert();
        vm.prank(minter);
        token.burnPair(user1, 1, 11); // more than minted
    }

    function test_BurnPair_RevertIfNotMinter() public {
        vm.prank(minter);
        token.mintPair(user1, 1, 100);

        vm.expectRevert();
        vm.prank(unauthorized);
        token.burnPair(user1, 1, 50);
    }

    // -------------------------------------------------------------------------
    // redeem
    // -------------------------------------------------------------------------

    function test_Redeem_YesTokens() public {
        vm.prank(minter);
        token.mintPair(user1, 1, 100);

        vm.prank(minter);
        token.redeem(user1, 1, 60, true); // burn 60 YES tokens

        assertEq(token.balanceOf(user1, token.yesTokenId(1)), 40);
        assertEq(token.balanceOf(user1, token.noTokenId(1)), 100); // NO untouched
    }

    function test_Redeem_NoTokens() public {
        vm.prank(minter);
        token.mintPair(user1, 1, 100);

        vm.prank(minter);
        token.redeem(user1, 1, 70, false); // burn 70 NO tokens

        assertEq(token.balanceOf(user1, token.yesTokenId(1)), 100); // YES untouched
        assertEq(token.balanceOf(user1, token.noTokenId(1)), 30);
    }

    function test_Redeem_EmitsEvent() public {
        vm.prank(minter);
        token.mintPair(user1, 2, 50);

        vm.expectEmit(true, true, false, true);
        emit OutcomeToken.Redeemed(user1, 2, 50, true);

        vm.prank(minter);
        token.redeem(user1, 2, 50, true);
    }

    function test_Redeem_RevertOnZeroAmount() public {
        vm.expectRevert("OutcomeToken: zero amount");
        vm.prank(minter);
        token.redeem(user1, 1, 0, true);
    }

    function test_Redeem_RevertIfNotMinter() public {
        vm.prank(minter);
        token.mintPair(user1, 1, 100);

        vm.expectRevert();
        vm.prank(unauthorized);
        token.redeem(user1, 1, 100, true);
    }

    function test_Redeem_RevertIfInsufficientBalance() public {
        vm.prank(minter);
        token.mintPair(user1, 1, 10);

        vm.expectRevert();
        vm.prank(minter);
        token.redeem(user1, 1, 11, true); // more than minted
    }

    // -------------------------------------------------------------------------
    // Access control
    // -------------------------------------------------------------------------

    function test_AccessControl_AdminCanGrantMinterRole() public {
        address newMinter = address(0x99);
        bytes32 role = token.MINTER_ROLE(); // capture before prank; external call would consume it
        vm.prank(admin);
        token.grantRole(role, newMinter);

        vm.prank(newMinter);
        token.mintPair(user1, 1, 1);
        assertEq(token.balanceOf(user1, token.yesTokenId(1)), 1);
    }

    function test_AccessControl_AdminCanRevokeMinterRole() public {
        bytes32 role = token.MINTER_ROLE(); // capture before prank
        vm.prank(admin);
        token.revokeRole(role, minter);

        vm.expectRevert();
        vm.prank(minter);
        token.mintPair(user1, 1, 1);
    }

    function test_AccessControl_SupportsInterface() public view {
        // Should support ERC1155 and AccessControl interfaces
        assertTrue(token.supportsInterface(0xd9b67a26)); // ERC1155
        assertTrue(token.supportsInterface(0x7965db0b)); // AccessControl (IAccessControl)
    }

    // -------------------------------------------------------------------------
    // Fuzz tests
    // -------------------------------------------------------------------------

    function testFuzz_MintAndBurnPair(uint256 marketId, uint96 amount) public {
        vm.assume(amount > 0);
        // marketId * 2 + 1 must not overflow uint256
        vm.assume(marketId <= type(uint256).max / 2 - 1);

        vm.startPrank(minter);
        token.mintPair(user1, marketId, amount);

        assertEq(token.balanceOf(user1, token.yesTokenId(marketId)), amount);
        assertEq(token.balanceOf(user1, token.noTokenId(marketId)), amount);

        token.burnPair(user1, marketId, amount);

        assertEq(token.balanceOf(user1, token.yesTokenId(marketId)), 0);
        assertEq(token.balanceOf(user1, token.noTokenId(marketId)), 0);
        vm.stopPrank();
    }

    function testFuzz_TokenIds_NeverCollide(uint128 a, uint128 b) public view {
        vm.assume(a != b);
        // YES(a) != NO(a), YES(a) != YES(b), NO(a) != NO(b), YES(a) != NO(b)
        assertTrue(token.yesTokenId(a) != token.noTokenId(a));
        assertTrue(token.yesTokenId(a) != token.yesTokenId(b));
        assertTrue(token.noTokenId(a) != token.noTokenId(b));
    }
}
