// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title StrikeCreditReserve
/// @notice Event-scoped STRIKE-backed credit ledger for STRIKE pool markets.
contract StrikeCreditReserve is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    struct CreditEvent {
        uint256 fundedAmount;
        uint256 redeemedAmount;
        uint256 freeCredit;
        uint256 lockedCredit;
        uint256 activeCreditMarkets;
        uint64 claimStart;
        uint64 claimEnd;
        uint64 endedAt;
        bool exists;
        bool finalized;
    }

    struct UserEventCredit {
        uint256 assignedBaseline;
        uint256 claimableCredit;
        uint256 freeCredit;
        uint256 lockedCredit;
        uint256 redeemedCredit;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREDIT_SIGNER_ROLE = keccak256("CREDIT_SIGNER_ROLE");
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");

    IERC20 public immutable strikeToken;

    mapping(uint256 => CreditEvent) public creditEvents;
    mapping(uint256 => mapping(address => UserEventCredit)) internal _userCredits;
    mapping(bytes32 => bool) public claimedGrant;
    mapping(uint256 => mapping(uint256 => bool)) public activeCreditMarket;
    uint256 public totalFreeCredit;

    event CreditEventCreated(uint256 indexed eventId, uint64 claimStart, uint64 claimEnd);
    event CreditEventFunded(uint256 indexed eventId, address indexed funder, uint256 amount);
    event CreditEventEnded(uint256 indexed eventId, uint64 endedAt);
    event CreditEventFinalized(uint256 indexed eventId);
    event CreditAssigned(uint256 indexed eventId, address indexed user, uint256 assignedBaseline, uint256 claimableCredit);
    event CreditClaimed(
        uint256 indexed eventId,
        address indexed user,
        bytes32 indexed grantId,
        uint256 amount,
        uint256 assignedBaseline
    );
    event CreditAdjusted(
        uint256 indexed eventId,
        address indexed user,
        uint256 assignedBaseline,
        uint256 freeCredit,
        uint256 lockedCredit
    );
    event CreditLocked(uint256 indexed eventId, address indexed user, address indexed poolVault, uint256 amount);
    event CreditSettled(
        uint256 indexed eventId,
        address indexed user,
        uint256 lockedCreditConsumed,
        uint256 creditReturned
    );
    event CreditRedeemed(uint256 indexed eventId, address indexed user, uint256 amount);
    event CreditMarketRegistered(uint256 indexed eventId, uint256 indexed marketId);
    event CreditMarketCleared(uint256 indexed eventId, uint256 indexed marketId);
    event SurplusWithdrawn(address indexed recipient, uint256 amount);

    constructor(address admin, address strikeToken_) {
        require(admin != address(0), "StrikeCreditReserve: zero admin");
        require(strikeToken_ != address(0), "StrikeCreditReserve: zero strike token");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(CREDIT_SIGNER_ROLE, admin);

        strikeToken = IERC20(strikeToken_);
    }

    function createEvent(uint256 eventId, uint64 claimStart, uint64 claimEnd) external onlyRole(ADMIN_ROLE) {
        require(eventId != 0, "StrikeCreditReserve: zero eventId");
        require(!creditEvents[eventId].exists, "StrikeCreditReserve: event exists");
        require(claimEnd > claimStart, "StrikeCreditReserve: invalid claim window");

        creditEvents[eventId].exists = true;
        creditEvents[eventId].claimStart = claimStart;
        creditEvents[eventId].claimEnd = claimEnd;

        emit CreditEventCreated(eventId, claimStart, claimEnd);
    }

    function fundEvent(uint256 eventId, uint256 amount) external nonReentrant {
        _requireEvent(eventId);
        require(amount > 0, "StrikeCreditReserve: zero amount");

        creditEvents[eventId].fundedAmount += amount;
        strikeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit CreditEventFunded(eventId, msg.sender, amount);
    }

    function assignCredit(uint256 eventId, address user, uint256 assignedBaseline, uint256 claimableCredit)
        external
        onlyRole(ADMIN_ROLE)
    {
        _requireEvent(eventId);
        require(user != address(0), "StrikeCreditReserve: zero user");

        UserEventCredit storage credit = _userCredits[eventId][user];
        credit.assignedBaseline = assignedBaseline;
        credit.claimableCredit = claimableCredit;

        emit CreditAssigned(eventId, user, assignedBaseline, claimableCredit);
    }

    function getGrantDigest(
        uint256 eventId,
        address user,
        bytes32 grantId,
        uint256 amount,
        uint256 assignedBaseline,
        uint256 claimStart,
        uint256 claimEnd
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(address(this), block.chainid, eventId, user, grantId, amount, assignedBaseline, claimStart, claimEnd)
        ).toEthSignedMessageHash();
    }

    function claimCredit(
        uint256 eventId,
        bytes32 grantId,
        uint256 amount,
        uint256 assignedBaseline,
        uint256 claimStart,
        uint256 claimEnd,
        bytes calldata signature
    ) external nonReentrant {
        CreditEvent storage creditEvent = _requireClaimableEvent(eventId);
        require(amount > 0, "StrikeCreditReserve: zero amount");
        require(block.timestamp >= claimStart && block.timestamp <= claimEnd, "StrikeCreditReserve: grant inactive");
        require(claimStart >= creditEvent.claimStart && claimEnd <= creditEvent.claimEnd, "StrikeCreditReserve: bad grant window");
        require(!claimedGrant[grantId], "StrikeCreditReserve: grant already claimed");

        bytes32 digest = getGrantDigest(eventId, msg.sender, grantId, amount, assignedBaseline, claimStart, claimEnd);
        address signer = ECDSA.recover(digest, signature);
        require(hasRole(CREDIT_SIGNER_ROLE, signer), "StrikeCreditReserve: invalid signature");

        UserEventCredit storage credit = _userCredits[eventId][msg.sender];
        require(credit.assignedBaseline == assignedBaseline, "StrikeCreditReserve: baseline mismatch");
        require(credit.claimableCredit >= amount, "StrikeCreditReserve: insufficient claimable");

        claimedGrant[grantId] = true;
        credit.claimableCredit -= amount;
        credit.freeCredit += amount;
        creditEvent.freeCredit += amount;
        totalFreeCredit += amount;
        _requireEventBacked(creditEvent);

        emit CreditClaimed(eventId, msg.sender, grantId, amount, assignedBaseline);
    }

    function adjustUserCredit(
        uint256 eventId,
        address user,
        uint256 assignedBaseline,
        uint256 freeCredit,
        uint256 lockedCredit
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        require(user != address(0), "StrikeCreditReserve: zero user");

        UserEventCredit storage credit = _userCredits[eventId][user];
        require(freeCredit + lockedCredit >= credit.redeemedCredit, "StrikeCreditReserve: below redeemed");

        creditEvent.freeCredit = creditEvent.freeCredit + freeCredit - credit.freeCredit;
        creditEvent.lockedCredit = creditEvent.lockedCredit + lockedCredit - credit.lockedCredit;
        totalFreeCredit = totalFreeCredit + freeCredit - credit.freeCredit;

        credit.assignedBaseline = assignedBaseline;
        credit.freeCredit = freeCredit;
        credit.lockedCredit = lockedCredit;
        _requireEventBacked(creditEvent);

        emit CreditAdjusted(eventId, user, assignedBaseline, freeCredit, lockedCredit);
    }

    function registerCreditMarket(uint256 eventId, uint256 marketId) external onlyRole(SPENDER_ROLE) {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        require(marketId != 0, "StrikeCreditReserve: zero marketId");
        require(!creditEvent.finalized, "StrikeCreditReserve: event finalized");
        require(!activeCreditMarket[eventId][marketId], "StrikeCreditReserve: market active");

        activeCreditMarket[eventId][marketId] = true;
        creditEvent.activeCreditMarkets += 1;
        emit CreditMarketRegistered(eventId, marketId);
    }

    function clearCreditMarket(uint256 eventId, uint256 marketId) external onlyRole(SPENDER_ROLE) {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        require(activeCreditMarket[eventId][marketId], "StrikeCreditReserve: market not active");

        activeCreditMarket[eventId][marketId] = false;
        creditEvent.activeCreditMarkets -= 1;
        emit CreditMarketCleared(eventId, marketId);
    }

    function spendCredit(uint256 eventId, address user, address poolVault, uint256 amount)
        external
        onlyRole(SPENDER_ROLE)
        nonReentrant
    {
        CreditEvent storage creditEvent = _requireSpendableEvent(eventId);
        require(user != address(0), "StrikeCreditReserve: zero user");
        require(poolVault != address(0), "StrikeCreditReserve: zero pool vault");
        require(amount > 0, "StrikeCreditReserve: zero amount");

        UserEventCredit storage credit = _userCredits[eventId][user];
        require(credit.freeCredit >= amount, "StrikeCreditReserve: insufficient credit");

        credit.freeCredit -= amount;
        credit.lockedCredit += amount;
        creditEvent.freeCredit -= amount;
        creditEvent.lockedCredit += amount;
        totalFreeCredit -= amount;
        strikeToken.safeTransfer(poolVault, amount);

        emit CreditLocked(eventId, user, poolVault, amount);
    }

    function settleCredit(uint256 eventId, address user, uint256 lockedCreditConsumed, uint256 creditReturned)
        external
        onlyRole(SPENDER_ROLE)
    {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        require(user != address(0), "StrikeCreditReserve: zero user");
        require(lockedCreditConsumed > 0 || creditReturned > 0, "StrikeCreditReserve: zero settlement");

        UserEventCredit storage credit = _userCredits[eventId][user];
        require(credit.lockedCredit >= lockedCreditConsumed, "StrikeCreditReserve: insufficient locked");

        credit.lockedCredit -= lockedCreditConsumed;
        credit.freeCredit += creditReturned;
        creditEvent.lockedCredit -= lockedCreditConsumed;
        creditEvent.freeCredit += creditReturned;
        totalFreeCredit += creditReturned;
        _requireEventBacked(creditEvent);

        emit CreditSettled(eventId, user, lockedCreditConsumed, creditReturned);
    }

    function endEvent(uint256 eventId) external onlyRole(ADMIN_ROLE) {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        require(creditEvent.endedAt == 0, "StrikeCreditReserve: event ended");

        creditEvent.endedAt = uint64(block.timestamp);
        emit CreditEventEnded(eventId, uint64(block.timestamp));
    }

    function finalizeEvent(uint256 eventId) external onlyRole(ADMIN_ROLE) {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        require(creditEvent.endedAt != 0, "StrikeCreditReserve: event not ended");
        require(!creditEvent.finalized, "StrikeCreditReserve: event finalized");
        require(creditEvent.activeCreditMarkets == 0, "StrikeCreditReserve: active credit markets");

        creditEvent.finalized = true;
        emit CreditEventFinalized(eventId);
    }

    function redeemExcessCredit(uint256 eventId) external nonReentrant returns (uint256 redeemable) {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        require(creditEvent.finalized, "StrikeCreditReserve: event not finalized");

        UserEventCredit storage credit = _userCredits[eventId][msg.sender];
        if (credit.freeCredit > credit.assignedBaseline) {
            redeemable = credit.freeCredit - credit.assignedBaseline;
        }
        require(redeemable > 0, "StrikeCreditReserve: nothing redeemable");

        credit.freeCredit -= redeemable;
        credit.redeemedCredit += redeemable;
        creditEvent.freeCredit -= redeemable;
        creditEvent.redeemedAmount += redeemable;
        totalFreeCredit -= redeemable;
        strikeToken.safeTransfer(msg.sender, redeemable);

        emit CreditRedeemed(eventId, msg.sender, redeemable);
    }

    function withdrawSurplus(address recipient, uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(recipient != address(0), "StrikeCreditReserve: zero recipient");
        require(amount > 0, "StrikeCreditReserve: zero amount");
        require(strikeToken.balanceOf(address(this)) >= totalFreeCredit + amount, "StrikeCreditReserve: locked");

        strikeToken.safeTransfer(recipient, amount);
        emit SurplusWithdrawn(recipient, amount);
    }

    function getUserCredit(uint256 eventId, address user) external view returns (UserEventCredit memory) {
        return _userCredits[eventId][user];
    }

    function creditBalance(uint256 eventId, address user) external view returns (uint256) {
        return _userCredits[eventId][user].freeCredit;
    }

    function redeemableCredit(uint256 eventId, address user) external view returns (uint256) {
        UserEventCredit memory credit = _userCredits[eventId][user];
        if (credit.freeCredit <= credit.assignedBaseline) {
            return 0;
        }
        return credit.freeCredit - credit.assignedBaseline;
    }

    function _requireEvent(uint256 eventId) internal view returns (CreditEvent storage creditEvent) {
        creditEvent = creditEvents[eventId];
        require(creditEvent.exists, "StrikeCreditReserve: event not found");
    }

    function _requireClaimableEvent(uint256 eventId) internal view returns (CreditEvent storage creditEvent) {
        creditEvent = _requireEvent(eventId);
        require(creditEvent.endedAt == 0, "StrikeCreditReserve: event ended");
        require(!creditEvent.finalized, "StrikeCreditReserve: event finalized");
        require(
            block.timestamp >= creditEvent.claimStart && block.timestamp <= creditEvent.claimEnd,
            "StrikeCreditReserve: claim closed"
        );
    }

    function _requireSpendableEvent(uint256 eventId) internal view returns (CreditEvent storage creditEvent) {
        creditEvent = _requireEvent(eventId);
        require(!creditEvent.finalized, "StrikeCreditReserve: event finalized");
        require(creditEvent.endedAt == 0, "StrikeCreditReserve: event ended");
    }

    function _requireEventBacked(CreditEvent storage) internal view {
        require(
            strikeToken.balanceOf(address(this)) >= totalFreeCredit,
            "StrikeCreditReserve: insufficient backing"
        );
    }
}
