// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./IUSDTCreditReserve.sol";

/// @title USDTCreditReserve
/// @notice Event-scoped USDT-backed credit ledger for World Cup credit-enabled markets.
contract USDTCreditReserve is IUSDTCreditReserve, AccessControl, EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREDIT_SIGNER_ROLE = keccak256("CREDIT_SIGNER_ROLE");

    bytes32 public constant CREDIT_GRANT_TYPEHASH = keccak256(
        "CreditGrant(uint256 eventId,address user,uint256 amount,uint64 claimStart,uint64 claimEnd,uint256 nonce,uint256 chainId,address reserve)"
    );

    IERC20 public immutable usdt;

    uint256 public lastObservedUsdtBalance;

    mapping(uint256 => CreditEvent) public creditEvents;
    mapping(uint256 => mapping(address => CreditAccount)) internal _accounts;
    mapping(uint256 => mapping(address => bool)) public authorizedMarkets;

    event CreditEventCreated(uint256 indexed eventId, uint64 claimStart, uint64 claimEnd, uint64 eventEnd);
    event CreditEventFunded(uint256 indexed eventId, address indexed funder, uint256 amount);
    event CreditEventFinalized(
        uint256 indexed eventId,
        uint256 fundedUsdt,
        uint256 assignedTotal,
        uint256 settledConsumedTotal,
        uint256 settledPayoutTotal,
        uint256 redeemedTotal,
        uint256 marketWithdrawnTotal
    );
    event MarketAuthorizationUpdated(uint256 indexed eventId, address indexed market, bool authorized);
    event CreditClaimed(uint256 indexed eventId, address indexed user, uint256 amount, uint256 nonce);
    event CreditSpent(
        uint256 indexed eventId, address indexed user, address indexed market, address recipientVault, uint256 amount
    );
    event CreditSettled(
        uint256 indexed eventId,
        address indexed user,
        address indexed market,
        uint256 lockedCreditConsumed,
        uint256 creditReturned
    );
    event ExcessCreditRedeemed(uint256 indexed eventId, address indexed user, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error ZeroEventId();
    error EventExists();
    error EventNotFound();
    error InvalidWindow();
    error EventFinalized();
    error EventNotFinalized();
    error ClaimClosed();
    error GrantInactive();
    error InvalidSignature();
    error UnauthorizedMarket();
    error InsufficientCredit();
    error InsufficientLockedCredit();
    error InsufficientBacking();
    error NothingRedeemable();
    error ActiveAuthorizedMarkets();

    constructor(address admin, address usdt_) EIP712("Strike USDTCreditReserve", "1") {
        if (admin == address(0) || usdt_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(CREDIT_SIGNER_ROLE, admin);

        usdt = IERC20(usdt_);
    }

    function createEvent(uint256 eventId, uint64 claimStart, uint64 claimEnd, uint64 eventEnd)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (eventId == 0) revert ZeroEventId();
        if (creditEvents[eventId].exists) revert EventExists();
        if (claimEnd <= claimStart || eventEnd < claimEnd) revert InvalidWindow();

        CreditEvent storage creditEvent = creditEvents[eventId];
        creditEvent.exists = true;
        creditEvent.claimStart = claimStart;
        creditEvent.claimEnd = claimEnd;
        creditEvent.eventEnd = eventEnd;

        emit CreditEventCreated(eventId, claimStart, claimEnd, eventEnd);
    }

    function fundEvent(uint256 eventId, uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        if (amount == 0) revert ZeroAmount();
        if (creditEvent.finalized) revert EventFinalized();

        creditEvent.fundedUsdt += amount;
        usdt.safeTransferFrom(msg.sender, address(this), amount);
        _syncObservedBalance();

        emit CreditEventFunded(eventId, msg.sender, amount);
    }

    function setAuthorizedMarket(uint256 eventId, address market, bool authorized) external onlyRole(ADMIN_ROLE) {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        if (market == address(0)) revert ZeroAddress();
        if (creditEvent.finalized) revert EventFinalized();

        bool currentlyAuthorized = authorizedMarkets[eventId][market];
        if (currentlyAuthorized != authorized) {
            authorizedMarkets[eventId][market] = authorized;
            if (authorized) {
                creditEvent.authorizedMarketCount += 1;
            } else {
                creditEvent.authorizedMarketCount -= 1;
            }
        }

        emit MarketAuthorizationUpdated(eventId, market, authorized);
    }

    function getGrantDigest(
        uint256 eventId,
        address user,
        uint256 amount,
        uint64 claimStart,
        uint64 claimEnd,
        uint256 nonce
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CREDIT_GRANT_TYPEHASH,
                    eventId,
                    user,
                    amount,
                    claimStart,
                    claimEnd,
                    nonce,
                    block.chainid,
                    address(this)
                )
            )
        );
    }

    function claimCredit(uint256 eventId, uint256 amount, uint64 claimStart, uint64 claimEnd, bytes calldata signature)
        external
        nonReentrant
    {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        if (amount == 0) revert ZeroAmount();
        if (creditEvent.finalized) revert EventFinalized();
        if (block.timestamp < creditEvent.claimStart || block.timestamp > creditEvent.claimEnd) revert ClaimClosed();
        if (block.timestamp < claimStart || block.timestamp > claimEnd) revert GrantInactive();
        if (claimStart < creditEvent.claimStart || claimEnd > creditEvent.claimEnd) revert InvalidWindow();

        CreditAccount storage account = _accounts[eventId][msg.sender];
        uint256 nonce = account.nonce;
        bytes32 digest = getGrantDigest(eventId, msg.sender, amount, claimStart, claimEnd, nonce);
        address signer = ECDSA.recover(digest, signature);
        if (!hasRole(CREDIT_SIGNER_ROLE, signer)) revert InvalidSignature();

        account.nonce = nonce + 1;
        account.assignedBaseline += amount;
        account.freeCredit += amount;
        creditEvent.assignedTotal += amount;
        creditEvent.freeTotal += amount;
        _requireBacked(creditEvent);

        emit CreditClaimed(eventId, msg.sender, amount, nonce);
    }

    function spendCredit(uint256 eventId, address user, address recipientVault, uint256 amount) external nonReentrant {
        CreditEvent storage creditEvent = _requireMarketEvent(eventId);
        if (user == address(0) || recipientVault == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        CreditAccount storage account = _accounts[eventId][user];
        if (account.freeCredit < amount) revert InsufficientCredit();

        account.freeCredit -= amount;
        account.lockedCredit += amount;
        creditEvent.freeTotal -= amount;
        creditEvent.lockedTotal += amount;
        creditEvent.marketWithdrawnTotal += amount;
        _requireFunded(creditEvent);

        usdt.safeTransfer(recipientVault, amount);
        _syncObservedBalance();
        _requireBacked(creditEvent);

        emit CreditSpent(eventId, user, msg.sender, recipientVault, amount);
    }

    function settleCredit(uint256 eventId, address user, uint256 lockedCreditConsumed, uint256 creditReturned)
        external
        nonReentrant
    {
        CreditEvent storage creditEvent = _requireMarketEvent(eventId);
        if (user == address(0)) revert ZeroAddress();
        if (lockedCreditConsumed == 0 && creditReturned == 0) revert ZeroAmount();

        CreditAccount storage account = _accounts[eventId][user];
        if (account.lockedCredit < lockedCreditConsumed) revert InsufficientLockedCredit();
        if (creditReturned > 0 && usdt.balanceOf(address(this)) < lastObservedUsdtBalance + creditReturned) {
            revert InsufficientBacking();
        }

        account.lockedCredit -= lockedCreditConsumed;
        account.freeCredit += creditReturned;
        creditEvent.lockedTotal -= lockedCreditConsumed;
        creditEvent.freeTotal += creditReturned;
        creditEvent.settledConsumedTotal += lockedCreditConsumed;
        creditEvent.settledPayoutTotal += creditReturned;
        creditEvent.fundedUsdt += creditReturned;
        _syncObservedBalance();
        _requireFunded(creditEvent);
        _requireBacked(creditEvent);

        emit CreditSettled(eventId, user, msg.sender, lockedCreditConsumed, creditReturned);
    }

    function finalizeEvent(uint256 eventId) external onlyRole(ADMIN_ROLE) {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        if (creditEvent.finalized) revert EventFinalized();
        if (block.timestamp < creditEvent.eventEnd) revert InvalidWindow();
        if (creditEvent.authorizedMarketCount != 0) revert ActiveAuthorizedMarkets();

        creditEvent.finalized = true;
        emit CreditEventFinalized(
            eventId,
            creditEvent.fundedUsdt,
            creditEvent.assignedTotal,
            creditEvent.settledConsumedTotal,
            creditEvent.settledPayoutTotal,
            creditEvent.redeemedTotal,
            creditEvent.marketWithdrawnTotal
        );
    }

    function redeemExcessCredit(uint256 eventId) external nonReentrant returns (uint256 redeemable) {
        CreditEvent storage creditEvent = _requireEvent(eventId);
        if (!creditEvent.finalized) revert EventNotFinalized();

        CreditAccount storage account = _accounts[eventId][msg.sender];
        redeemable = _redeemable(account);
        if (redeemable == 0) revert NothingRedeemable();

        account.freeCredit -= redeemable;
        account.redeemedExcess += redeemable;
        creditEvent.freeTotal -= redeemable;
        creditEvent.redeemedTotal += redeemable;

        usdt.safeTransfer(msg.sender, redeemable);
        _syncObservedBalance();
        emit ExcessCreditRedeemed(eventId, msg.sender, redeemable);
    }

    function getAccount(uint256 eventId, address user) external view returns (CreditAccount memory) {
        return _accounts[eventId][user];
    }

    function creditBalance(uint256 eventId, address user) external view returns (uint256) {
        return _accounts[eventId][user].freeCredit;
    }

    function lockedCreditBalance(uint256 eventId, address user) external view returns (uint256) {
        return _accounts[eventId][user].lockedCredit;
    }

    function redeemableCredit(uint256 eventId, address user) external view returns (uint256) {
        return _redeemable(_accounts[eventId][user]);
    }

    function _requireEvent(uint256 eventId) internal view returns (CreditEvent storage creditEvent) {
        creditEvent = creditEvents[eventId];
        if (!creditEvent.exists) revert EventNotFound();
    }

    function _requireMarketEvent(uint256 eventId) internal view returns (CreditEvent storage creditEvent) {
        creditEvent = _requireEvent(eventId);
        if (creditEvent.finalized) revert EventFinalized();
        if (!authorizedMarkets[eventId][msg.sender]) revert UnauthorizedMarket();
    }

    function _requireBacked(CreditEvent storage creditEvent) internal view {
        uint256 outstandingCredit = creditEvent.freeTotal;
        _requireFunded(creditEvent);
        if (usdt.balanceOf(address(this)) < outstandingCredit) {
            revert InsufficientBacking();
        }
    }

    function _requireFunded(CreditEvent storage creditEvent) internal view {
        uint256 outstandingCredit = creditEvent.freeTotal;
        if (outstandingCredit + creditEvent.redeemedTotal + creditEvent.marketWithdrawnTotal > creditEvent.fundedUsdt) {
            revert InsufficientBacking();
        }
    }

    function _syncObservedBalance() internal {
        lastObservedUsdtBalance = usdt.balanceOf(address(this));
    }

    function _redeemable(CreditAccount memory account) internal pure returns (uint256) {
        if (account.freeCredit <= account.assignedBaseline) {
            return 0;
        }
        return account.freeCredit - account.assignedBaseline;
    }
}
