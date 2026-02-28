// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IUniChatRegistry_Group {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function platformTreasury() external view returns (address);
    function getReferrer(bytes32 code) external view returns (address);
    function anyTokenBuyValidator() external view returns (address);
    function USDT() external view returns (address);
}

interface IAnyTokenBuyValidator {
    function isEligible(address user, address groupToken, address group) external view returns (bool);
}

/**
 * @title RedPacketGroup
 * @notice Single group instance: main group + subgroups + entry fee split (9/21/70) + red packets (entry/normal/scheduled) + joinAt gate + rate limit/mute/fine/vote + BigOwner withdraw
 */
contract RedPacketGroup is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Registry roles must match UniChatRegistry
    bytes32 public constant BIG_OWNER_ROLE = keccak256("BIG_OWNER_ROLE");
    bytes32 public constant OWNER_ROLE     = keccak256("OWNER_ROLE");

    // Entry split (bps)
    uint16 public constant BPS_OWNER = 900;   // 9%
    uint16 public constant BPS_REF   = 2100;  // 21%
    uint16 public constant BPS_POOL  = 7000;  // 70%
    uint16 public constant BPS_DENOM = 10_000;

    // Governance thresholds
    uint16 public constant MAIN_THRESHOLD_BPS = 5100; // 51%
    uint16 public constant SUB_THRESHOLD_BPS  = 7500; // 75%

    // Time constants
    uint64 public constant WEEK = 7 days;
    uint64 public constant SIX_MONTHS = 180 days;
    uint64 public constant FOUR_YEARS = 1460 days; // 4*365d
    uint64 public constant DAY = 24 hours;

    uint256 public constant MAX_MESSAGE_BYTES = 280;

    // Custom Errors
    error NotMainOwner();
    error NotBigOwner();
    error NoAuth();
    error SubgroupNotExists();
    error NotSubOwner();
    error NotMember();
    error AlreadyInitialized();
    error ZeroAddress();
    error FeeZero();
    error AlreadyMember();
    error NotEligible();
    error NeedGroupToken();
    error BadContent();
    error BadSubgroup();
    error NotInSubgroup();
    error UnpaidFine();
    error ZeroUser();
    error ZeroOwner();
    error ZeroTo();
    error ZeroSubOwner();
    error UserNotMember();
    error UserNotInSubgroup();
    error FineZero();
    error AmountZero();
    error NoDue();
    error ZeroToken();
    error PacketEmpty();
    error AlreadyClaimed();
    error JoinAtGate();
    error NotInPacketSubgroup();
    error ElectionNotAllowed();
    error ElectionActive();
    error ZeroCandidate();
    error CandidateNotMember();
    error NoElection();
    error Voted();
    error SubElectionActive();
    error CandidateNotInSubgroup();
    error DecayOutOfRange();
    error ScheduleInactive();
    error ScheduleDone();
    error TooEarly();
    error ScheduleAmountZero();
    error InsufficientScheduleBalance();
    error SharesZero();
    error AmountLessThanShares();
    error GloballyMuted();
    error Muted();
    error MessageLimitExceeded();
    error IndexOutOfBounds();

    enum PacketKind { ENTRY, NORMAL, SCHEDULE }
    enum MessageLimitType { NONE, DAILY, WEEKLY } // 0=unlimited, 1=daily, 2=weekly

    struct Member {
        bool   exists;
        uint64 joinAt;
        uint32 subgroupId; // 0 = no subgroup
    }

    struct Subgroup {
        bool    exists;
        address owner;
        uint32  memberCount;
    }

    struct Packet {
        PacketKind kind;
        address token;

        uint64  createdAt;
        uint32  targetSubgroupId; // 0 = whole group
        uint32  sharesTotal;

        uint256 totalAmount;
        uint256 remainingAmount;
        uint32  remainingShares;
    }

    struct Message {
        address from;        // Sender address
        string content;     // Message content
        uint64 timestamp;   // Timestamp when sent
        uint32 subgroupId;  // Subgroup ID (0 for main group messages)
    }

    // Core config
    IUniChatRegistry_Group public registry;
    address public entryToken;      // Use groupToken as entry fee token
    address public groupToken;      // token required by token-gating (checked by validator or balance>0)
    uint256 public entryFeeAmount;  // adjustable amount, token fixed
    uint64  public createdAt;
    MessageLimitType public mainMessageLimitType; // Main group message limit type
    uint32 public mainMessageLimitCount;          // Maximum messages in time period (0 means unlimited)

    // Owners
    address public mainOwner;

    // Init guard
    bool private _initialized;

    // Members
    uint32 public memberCount;
    mapping(address => Member) public members;
    address[] public memberList; // Member address list

    // Subgroups
    uint32 public subgroupCount;
    mapping(uint32 => Subgroup) public subgroups;

    // Messaging limit / mute
    mapping(address => uint64) public lastMainMessageAt;
    mapping(address => uint64) public globalMuteUntil;
    mapping(uint32 => mapping(address => uint64)) public subgroupMuteUntil;

    // Record each member's message count in current time period and the start time of that period
    struct MessageCount {
        uint32 count;      // Message count in current time period
        uint64 periodStart; // Start timestamp of current time period
    }
    mapping(address => MessageCount) public mainMessageCounts;

    // Messages storage
    Message[] public mainMessages;                                    // Main group messages array

    // Fines (only in subgroup, in USDT)
    mapping(uint32 => mapping(address => uint256)) public fineDueUsdt;

    // Packets
    uint256 public nextPacketId = 1;
    mapping(uint256 => Packet) public packets;
    mapping(uint256 => mapping(address => bool)) public claimed;
    
    // Packet claim details
    mapping(uint256 => address[]) public packetClaimers;
    mapping(uint256 => mapping(address => uint256)) public packetClaimAmounts;

    // Main election
    bool    public mainElectionActive;
    uint256 public mainElectionId;
    uint64  public nextMainElectionAllowedAt;
    uint64  public mainElectionStartedAt;
    address public mainElectionCandidate;
    uint32  public mainElectionYesVotes;
    uint32  public mainElectionSnapshotMembers;
    mapping(uint256 => mapping(address => bool)) public mainElectionVoted;

    // Subgroup election
    struct SubElectionState {
        bool    active;
        uint256 id;
        uint64  startedAt;
        address candidate;
        uint32  yesVotes;
        uint32  snapshotMembers;
    }
    mapping(uint32 => SubElectionState) public subElections;
    mapping(uint32 => mapping(uint256 => mapping(address => bool))) public subElectionVoted;

    // Scheduled plan
    struct SchedulePlan {
        bool    active;
        address token;
        uint32  remaining;     // 365
        uint64  interval;      // 24h
        uint64  nextTime;      // next executable time
        uint256 currentAmount; // current round amount
        uint16  decayBps;      // 0.1%~99% => 10~9900
    }
    SchedulePlan public schedule;

    // Group settings (group name, economic model, group rules, announcement)
    string public groupName;      // Group name
    string public economicModel;  // Economic model
    string public groupRules;     // Group rules
    string public announcement;   // Announcement

    // Referral leaderboard
    mapping(address => uint256) public referralCounts; // Record number of referrals each referrer invited in this group
    address[] public referrerList; // Referrer list (for leaderboard queries)

    // Events
    event Initialized(address indexed registry, address indexed mainOwner, address indexed groupToken, address entryToken, uint256 entryFee);
    event EntryFeeUpdated(uint256 newEntryFee);

    event SubgroupCreated(uint32 indexed subgroupId, address indexed subgroupOwner);
    event SubgroupOwnerUpdated(uint32 indexed subgroupId, address indexed newOwner);

    event Joined(address indexed user, uint32 indexed subgroupId, bytes32 indexed referralCode, uint256 feePaid);
    event EntrySplit(uint256 ownerAmount, uint256 refAmount, uint256 poolAmount, address refRecipient, address ownerRecipientA, address ownerRecipientB);

    event PacketCreated(uint256 indexed packetId, PacketKind kind, address indexed token, uint32 indexed targetSubgroupId, uint32 shares, uint256 amount);
    event Claimed(uint256 indexed packetId, address indexed user, uint256 amount);

    event MainMessage(address indexed from, string content);
    event SubMessage(uint32 indexed subgroupId, address indexed from, string content);

    event GlobalMute(address indexed user, uint64 untilTs);
    event SubgroupMute(uint32 indexed subgroupId, address indexed user, uint64 untilTs);

    event FineIssued(uint32 indexed subgroupId, address indexed user, uint256 amountUsdt);
    event FinePaid(uint32 indexed subgroupId, address indexed user, uint256 amountUsdt, uint256 remainingDue);

    event MainElectionStarted(uint256 indexed electionId, address indexed candidate, uint32 snapshotMembers);
    event MainElectionVoted(uint256 indexed electionId, address indexed voter);
    event MainOwnerChangedByVote(address indexed newOwner);

    event SubElectionStarted(uint32 indexed subgroupId, uint256 indexed electionId, address indexed candidate, uint32 snapshotMembers);
    event SubElectionVoted(uint32 indexed subgroupId, uint256 indexed electionId, address indexed voter);
    event SubOwnerChangedByVote(uint32 indexed subgroupId, address indexed newOwner);

    event ScheduleConfigured(address indexed token, uint256 initialAmount, uint16 decayBps);
    event ScheduleTick(uint256 indexed packetId, uint256 amount, uint32 shares, uint32 remainingRounds, uint256 nextAmount, uint64 nextTime);
    event ScheduleStopped();

    event BigOwnerMainOwnerAppointed(address indexed newOwner);
    event BigOwnerWithdraw(address indexed token, address indexed to, uint256 amount);

    event MainMessageLimitUpdated(MessageLimitType limitType, uint32 limitCount);

    event GroupNameUpdated(string newGroupName);
    event EconomicModelUpdated(string newEconomicModel);
    event GroupRulesUpdated(string newGroupRules);
    event AnnouncementUpdated(string newAnnouncement);

    event ReferralCountIncremented(address indexed referrer, uint256 newCount);

    // -------------------------
    // Modifiers
    // -------------------------
    modifier onlyMainOwner() {
        if (msg.sender != mainOwner) revert NotMainOwner();
        _;
    }

    modifier onlyBigOwner() {
        if (!registry.hasRole(BIG_OWNER_ROLE, msg.sender)) revert NotBigOwner();
        _;
    }

    modifier onlyMainOwnerOrBigOwner() {
        if (msg.sender != mainOwner && !registry.hasRole(BIG_OWNER_ROLE, msg.sender)) revert NoAuth();
        _;
    }

    modifier onlySubgroupOwner(uint32 subgroupId) {
        if (!subgroups[subgroupId].exists) revert SubgroupNotExists();
        if (msg.sender != subgroups[subgroupId].owner) revert NotSubOwner();
        _;
    }

    modifier onlyMember() {
        if (!members[msg.sender].exists) revert NotMember();
        _;
    }

    // -------------------------
    // Init (for clones)
    // -------------------------
    function initialize(address registry_, address mainOwner_, address groupToken_, uint256 entryFee_, string calldata groupName_, string calldata groupRules_) external {
        if (_initialized) revert AlreadyInitialized();
        if (registry_ == address(0) || mainOwner_ == address(0) || groupToken_ == address(0)) revert ZeroAddress();
        if (entryFee_ == 0) revert FeeZero();

        _initialized = true;

        registry = IUniChatRegistry_Group(registry_);
        entryToken = groupToken_;  // Entry fee uses groupToken
        mainOwner = mainOwner_;
        groupToken = groupToken_;
        entryFeeAmount = entryFee_;
        groupName = groupName_;
        groupRules = groupRules_;

        createdAt = uint64(block.timestamp);
        nextMainElectionAllowedAt = createdAt + SIX_MONTHS;
        mainMessageLimitType = MessageLimitType.WEEKLY; // Default weekly
        mainMessageLimitCount = 1; // Default 1 message per week (maintain backward compatibility)
        
        // Initialize packet ID (state variable initial value is not set when clone is deployed)
        nextPacketId = 1;

        // Automatically add creator as member (no entry fee required)
        members[mainOwner_] = Member({
            exists: true,
            joinAt: createdAt,
            subgroupId: 0
        });
        memberCount = 1;
        memberList.push(mainOwner_);

        emit Initialized(registry_, mainOwner_, groupToken_, entryToken, entryFee_);
        emit EntryFeeUpdated(entryFee_);
        emit Joined(mainOwner_, 0, bytes32(0), 0); // Creator join event, feePaid = 0
    }

    // -------------------------
    // Views / ranks
    // -------------------------
    function getMainRank() external view returns (string memory) {
        uint32 n = memberCount;
        if (n >= 10_000) return string(unicode"Core Leader");
        if (n >= 5_000)  return string(unicode"DAO Lieutenant General");
        if (n >= 3_000)  return string(unicode"DAO Major General");
        if (n >= 1_000)  return string(unicode"Thousand Commander Group");
        if (n >= 500)    return string(unicode"Regiment Leader Group");
        if (n >= 100)    return string(unicode"Centurion Group");
        if (n >= 50)     return string(unicode"Squad Leader Group");
        return string(unicode"Starting Group");
    }

    // -------------------------
    // Admin ops
    // -------------------------
    /**
     * @notice Set main group message limit
     * @param limitType Limit type: 0=unlimited, 1=daily, 2=weekly
     * @param limitCount Maximum messages in time period (0 means unlimited, only valid when limitType!=NONE)
     */
    function setMainMessageLimit(MessageLimitType limitType, uint32 limitCount) external onlyMainOwner {
        mainMessageLimitType = limitType;
        mainMessageLimitCount = limitCount;
        emit MainMessageLimitUpdated(limitType, limitCount);
    }

    /**
     * @notice Set group name
     * @param newGroupName New group name
     */
    function setGroupName(string calldata newGroupName) external onlyMainOwner {
        groupName = newGroupName;
        emit GroupNameUpdated(newGroupName);
    }

    /**
     * @notice Set group settings (group name, economic model, group rules, announcement, entry fee)
     * @param newGroupName New group name (empty string means no update)
     * @param newEconomicModel New economic model content (empty string means no update)
     * @param newGroupRules New group rules content (empty string means no update)
     * @param newAnnouncement New announcement content (empty string means no update)
     * @param newEntryFee New entry fee (0 means no update)
     */
    function setGroupSettings(
        string calldata newGroupName,
        string calldata newEconomicModel,
        string calldata newGroupRules,
        string calldata newAnnouncement,
        uint256 newEntryFee
    ) external onlyMainOwner {
        if (bytes(newGroupName).length > 0) {
            groupName = newGroupName;
            emit GroupNameUpdated(newGroupName);
        }
        if (bytes(newEconomicModel).length > 0) {
            economicModel = newEconomicModel;
            emit EconomicModelUpdated(newEconomicModel);
        }
        if (bytes(newGroupRules).length > 0) {
            groupRules = newGroupRules;
            emit GroupRulesUpdated(newGroupRules);
        }
        if (bytes(newAnnouncement).length > 0) {
            announcement = newAnnouncement;
            emit AnnouncementUpdated(newAnnouncement);
        }
        if (newEntryFee > 0) {
            entryFeeAmount = newEntryFee;
            emit EntryFeeUpdated(newEntryFee);
        }
    }

    // BigOwner: appoint main owner directly (PRD #9)
    function bigOwnerAppointMainOwner(address newOwner) external onlyBigOwner {
        if (newOwner == address(0)) revert ZeroOwner();
        if (!members[newOwner].exists) revert NotMember();
        mainOwner = newOwner;
        emit BigOwnerMainOwnerAppointed(newOwner);
    }

    // BigOwner: withdraw any token balance (PRD #9)
    function bigOwnerWithdrawToken(address token, address to, uint256 amount) external onlyBigOwner nonReentrant {
        if (to == address(0)) revert ZeroTo();
        IERC20(token).safeTransfer(to, amount);
        emit BigOwnerWithdraw(token, to, amount);
    }

    // -------------------------
    // Subgroups
    // -------------------------
    function createSubgroup(address subgroupOwner) external onlyMainOwner returns (uint32 subgroupId) {
        if (subgroupOwner == address(0)) revert ZeroSubOwner();
        subgroupId = ++subgroupCount;
        subgroups[subgroupId] = Subgroup({exists: true, owner: subgroupOwner, memberCount: 0});
        emit SubgroupCreated(subgroupId, subgroupOwner);
    }

    function setSubgroupOwner(uint32 subgroupId, address newOwner) external onlyMainOwner {
        if (!subgroups[subgroupId].exists) revert SubgroupNotExists();
        if (newOwner == address(0)) revert ZeroOwner();
        subgroups[subgroupId].owner = newOwner;
        emit SubgroupOwnerUpdated(subgroupId, newOwner);
    }

    // -------------------------
    // Join (entry split 9/31/60, subgroup split 4.5/4.5 if subgroup invite)
    // -------------------------
    function join(uint32 subgroupId, bytes32 referralCode) external nonReentrant {
        if (members[msg.sender].exists) revert AlreadyMember();

        // Token-gating: prioritize validator; otherwise require balance > 0
        address validator = registry.anyTokenBuyValidator();
        if (validator != address(0)) {
            if (!IAnyTokenBuyValidator(validator).isEligible(msg.sender, groupToken, address(this))) revert NotEligible();
        } else {
            if (IERC20(groupToken).balanceOf(msg.sender) == 0) revert NeedGroupToken();
        }

        uint256 fee = entryFeeAmount;
        IERC20(entryToken).safeTransferFrom(msg.sender, address(this), fee);

        // record membership first (so they are included in packet shares)
        uint32 assignedSub = 0;
        if (subgroupId != 0 && subgroups[subgroupId].exists) {
            assignedSub = subgroupId;
        }
        members[msg.sender] = Member({exists: true, joinAt: uint64(block.timestamp), subgroupId: assignedSub});
        memberCount += 1;
        memberList.push(msg.sender);
        if (assignedSub != 0) {
            subgroups[assignedSub].memberCount += 1;
        }

        // compute split
        uint256 ownerAmt = (fee * BPS_OWNER) / BPS_DENOM;
        uint256 refAmt   = (fee * BPS_REF) / BPS_DENOM;
        uint256 poolAmt  = fee - ownerAmt - refAmt; // ensure sum=fee

        // owner split
        address ownerA = mainOwner;
        address ownerB = address(0);

        if (assignedSub != 0 && subgroups[assignedSub].exists) {
            ownerB = subgroups[assignedSub].owner;
            uint256 a = ownerAmt / 2;
            uint256 b = ownerAmt - a;
            if (a > 0) IERC20(entryToken).safeTransfer(ownerA, a);
            if (b > 0) IERC20(entryToken).safeTransfer(ownerB, b);
        } else {
            if (ownerAmt > 0) IERC20(entryToken).safeTransfer(ownerA, ownerAmt);
        }

        // referral / platform
        address referrer = registry.getReferrer(referralCode);
        address refRecipient = referrer;
        if (refRecipient == address(0)) {
            refRecipient = registry.platformTreasury(); // system entry => platform gets 21%
        } else {
            // Increment referrer's invitation count in this group
            if (referralCounts[referrer] == 0) {
                // First invitation, add to list
                referrerList.push(referrer);
            }
            referralCounts[referrer] += 1;
            emit ReferralCountIncremented(referrer, referralCounts[referrer]);
        }
        if (refAmt > 0) IERC20(entryToken).safeTransfer(refRecipient, refAmt);

        // create entry packet in pool (60%) for whole group, shares = current memberCount
        _createPacket(PacketKind.ENTRY, entryToken, 0, memberCount, poolAmt, msg.sender, "");

        emit Joined(msg.sender, assignedSub, referralCode, fee);
        emit EntrySplit(ownerAmt, refAmt, poolAmt, refRecipient, ownerA, ownerB);
    }

    // -------------------------
    // Messaging
    // -------------------------
    function sendMainMessage(string calldata content) external onlyMember {
        _requireNotMutedMain(msg.sender);
        bytes memory b = bytes(content);
        if (b.length == 0 || b.length > MAX_MESSAGE_BYTES) revert BadContent();

        // Check message count limit
        _checkAndUpdateMessageCount(msg.sender);

        // Store message
        mainMessages.push(Message({
            from: msg.sender,
            content: content,
            timestamp: uint64(block.timestamp),
            subgroupId: 0
        }));

        emit MainMessage(msg.sender, content);
    }

    function sendSubMessage(uint32 subgroupId, string calldata content) external onlyMember {
        if (subgroupId == 0 || !subgroups[subgroupId].exists) revert BadSubgroup();
        if (members[msg.sender].subgroupId != subgroupId) revert NotInSubgroup();

        _requireNotMutedSub(subgroupId, msg.sender);

        // fine gate (subgroup only)
        if (fineDueUsdt[subgroupId][msg.sender] != 0) revert UnpaidFine();

        bytes memory b = bytes(content);
        if (b.length == 0 || b.length > MAX_MESSAGE_BYTES) revert BadContent();

        emit SubMessage(subgroupId, msg.sender, content);
    }

    // -------------------------
    // Mute (no kick, no delete)
    // -------------------------
    function setGlobalMute(address user, uint64 untilTs) external onlyMainOwnerOrBigOwner {
        if (user == address(0)) revert ZeroUser();
        globalMuteUntil[user] = untilTs;
        emit GlobalMute(user, untilTs);
    }

    function setSubgroupMute(uint32 subgroupId, address user, uint64 untilTs) external onlySubgroupOwner(subgroupId) {
        if (user == address(0)) revert ZeroUser();
        subgroupMuteUntil[subgroupId][user] = untilTs;
        emit SubgroupMute(subgroupId, user, untilTs);
    }

    // -------------------------
    // Fine (subgroup only)
    // -------------------------
    function issueFine(uint32 subgroupId, address user, uint256 amountUsdt) external onlySubgroupOwner(subgroupId) {
        if (user == address(0)) revert ZeroUser();
        if (!members[user].exists) revert UserNotMember();
        if (members[user].subgroupId != subgroupId) revert UserNotInSubgroup();
        if (amountUsdt == 0) revert FineZero();

        fineDueUsdt[subgroupId][user] += amountUsdt;
        emit FineIssued(subgroupId, user, amountUsdt);
    }

    function payFine(uint32 subgroupId, uint256 amountUsdt) external nonReentrant onlyMember {
        if (subgroupId == 0 || !subgroups[subgroupId].exists) revert BadSubgroup();
        if (members[msg.sender].subgroupId != subgroupId) revert NotInSubgroup();
        if (amountUsdt == 0) revert AmountZero();

        uint256 due = fineDueUsdt[subgroupId][msg.sender];
        if (due == 0) revert NoDue();

        uint256 pay = amountUsdt > due ? due : amountUsdt;

        // Pay directly to subgroup owner (policy choice)
        // Fines use USDT, not entryToken (groupToken)
        IERC20(registry.USDT()).safeTransferFrom(msg.sender, subgroups[subgroupId].owner, pay);

        fineDueUsdt[subgroupId][msg.sender] = due - pay;
        emit FinePaid(subgroupId, msg.sender, pay, due - pay);
    }

    // -------------------------
    // Red packets (normal)
    // -------------------------
    function createNormalPacketAll(address token, uint256 amount, string calldata message) external nonReentrant onlyMember returns (uint256 packetId) {
        if (token == address(0)) revert ZeroToken();
        if (amount == 0) revert AmountZero();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        packetId = _createPacket(PacketKind.NORMAL, token, 0, memberCount, amount, msg.sender, message);
    }

    function createNormalPacketSubgroup(address token, uint256 amount, uint32 subgroupId, string calldata message) external nonReentrant onlyMember returns (uint256 packetId) {
        if (token == address(0)) revert ZeroToken();
        if (amount == 0) revert AmountZero();
        if (subgroupId == 0 || !subgroups[subgroupId].exists) revert BadSubgroup();
        if (members[msg.sender].subgroupId != subgroupId) revert NotInSubgroup();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        packetId = _createPacket(PacketKind.NORMAL, token, subgroupId, subgroups[subgroupId].memberCount, amount, msg.sender, message);
    }

    // -------------------------
    // Claim (joinAt barrier)
    // -------------------------
    function claimPacket(uint256 packetId) external nonReentrant onlyMember {
        Packet storage p = packets[packetId];
        if (p.remainingShares == 0) revert PacketEmpty();
        if (claimed[packetId][msg.sender]) revert AlreadyClaimed();

        Member memory m = members[msg.sender];
        if (m.joinAt > p.createdAt) revert JoinAtGate();

        // subgroup gating
        if (p.targetSubgroupId != 0) {
            if (m.subgroupId != p.targetSubgroupId) revert NotInPacketSubgroup();
            if (fineDueUsdt[p.targetSubgroupId][msg.sender] != 0) revert UnpaidFine();
        }

        claimed[packetId][msg.sender] = true;

        uint256 amount = _drawAmount(packetId, p);
        IERC20(p.token).safeTransfer(msg.sender, amount);

        // Record claim details
        packetClaimAmounts[packetId][msg.sender] = amount;
        packetClaimers[packetId].push(msg.sender);

        emit Claimed(packetId, msg.sender, amount);
    }

    // -------------------------
    // Governance - Main group election
    // -------------------------
    function startMainElection(address candidate) external onlyMember {
        if (block.timestamp < nextMainElectionAllowedAt) revert ElectionNotAllowed();
        if (mainElectionActive) revert ElectionActive();
        if (candidate == address(0)) revert ZeroCandidate();
        if (!members[candidate].exists) revert CandidateNotMember();

        mainElectionActive = true;
        mainElectionId += 1;
        mainElectionStartedAt = uint64(block.timestamp);
        mainElectionCandidate = candidate;
        mainElectionYesVotes = 0;
        mainElectionSnapshotMembers = memberCount;

        emit MainElectionStarted(mainElectionId, candidate, memberCount);
    }

    function voteMainElection() external onlyMember {
        if (!mainElectionActive) revert NoElection();
        if (mainElectionVoted[mainElectionId][msg.sender]) revert Voted();

        mainElectionVoted[mainElectionId][msg.sender] = true;
        mainElectionYesVotes += 1;

        emit MainElectionVoted(mainElectionId, msg.sender);

        // immediate finalize if >=51%
        if (_reached(mainElectionYesVotes, mainElectionSnapshotMembers, MAIN_THRESHOLD_BPS)) {
            mainOwner = mainElectionCandidate;
            mainElectionActive = false;

            nextMainElectionAllowedAt = uint64(block.timestamp) + FOUR_YEARS;

            emit MainOwnerChangedByVote(mainOwner);
        }
    }

    // -------------------------
    // Governance - Subgroup election
    // -------------------------
    function startSubElection(uint32 subgroupId, address candidate) external onlyMember {
        if (subgroupId == 0 || !subgroups[subgroupId].exists) revert BadSubgroup();
        if (members[msg.sender].subgroupId != subgroupId) revert NotInSubgroup();

        SubElectionState storage e = subElections[subgroupId];
        if (e.active) revert SubElectionActive();
        if (candidate == address(0)) revert ZeroCandidate();
        if (!members[candidate].exists || members[candidate].subgroupId != subgroupId) revert CandidateNotInSubgroup();

        e.active = true;
        e.id += 1;
        e.startedAt = uint64(block.timestamp);
        e.candidate = candidate;
        e.yesVotes = 0;
        e.snapshotMembers = subgroups[subgroupId].memberCount;

        emit SubElectionStarted(subgroupId, e.id, candidate, e.snapshotMembers);
    }

    function voteSubElection(uint32 subgroupId) external onlyMember {
        if (subgroupId == 0 || !subgroups[subgroupId].exists) revert BadSubgroup();
        if (members[msg.sender].subgroupId != subgroupId) revert NotInSubgroup();

        SubElectionState storage e = subElections[subgroupId];
        if (!e.active) revert NoElection();
        if (subElectionVoted[subgroupId][e.id][msg.sender]) revert Voted();

        subElectionVoted[subgroupId][e.id][msg.sender] = true;
        e.yesVotes += 1;

        emit SubElectionVoted(subgroupId, e.id, msg.sender);

        if (_reached(e.yesVotes, e.snapshotMembers, SUB_THRESHOLD_BPS)) {
            subgroups[subgroupId].owner = e.candidate;
            e.active = false;
            emit SubOwnerChangedByVote(subgroupId, e.candidate);
        }
    }

    // -------------------------
    // Scheduled red packets (main owner config; anyone can tick)
    // -------------------------
    function configureSchedule(address token, uint256 initialAmount, uint16 decayBps) external onlyMainOwner {
        if (token == address(0)) revert ZeroToken();
        if (initialAmount == 0) revert AmountZero();
        if (decayBps < 10 || decayBps > 9900) revert DecayOutOfRange();

        schedule = SchedulePlan({
            active: true,
            token: token,
            remaining: 365,
            interval: DAY,
            nextTime: uint64(block.timestamp), // allow immediate tick
            currentAmount: initialAmount,
            decayBps: decayBps
        });

        emit ScheduleConfigured(token, initialAmount, decayBps);
    }

    function stopSchedule() external onlyMainOwner {
        schedule.active = false;
        emit ScheduleStopped();
    }

    /**
     * @notice Requires external executor to call periodically (keeper/cron/anyone)
     */
    function tickSchedule() external nonReentrant returns (uint256 packetId) {
        if (!schedule.active) revert ScheduleInactive();
        if (schedule.remaining == 0) revert ScheduleDone();
        if (block.timestamp < schedule.nextTime) revert TooEarly();

        uint256 amt = schedule.currentAmount;
        if (amt == 0) revert ScheduleAmountZero();
        // require enough balance in contract
        if (IERC20(schedule.token).balanceOf(address(this)) < amt) revert InsufficientScheduleBalance();

        packetId = _createPacket(PacketKind.SCHEDULE, schedule.token, 0, memberCount, amt, address(this), "");

        // update plan
        schedule.remaining -= 1;
        schedule.nextTime = uint64(block.timestamp) + schedule.interval;

        uint256 nextAmt = (amt * (BPS_DENOM - schedule.decayBps)) / BPS_DENOM;
        schedule.currentAmount = nextAmt;

        // auto stop when rounds finished or next amount becomes 0
        if (schedule.remaining == 0 || nextAmt == 0) {
            schedule.active = false;
        }

        emit ScheduleTick(packetId, amt, memberCount, schedule.remaining, nextAmt, schedule.nextTime);
    }

    /**
     * @notice Pre-deposit tokens for scheduled red packets (can also directly transfer to contract address)
     */
    function depositToken(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert ZeroToken();
        if (amount == 0) revert AmountZero();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    // -------------------------
    // Internal helpers
    // -------------------------
    function _createPacket(PacketKind kind, address token, uint32 targetSubgroupId, uint32 shares, uint256 amount, address creator, string memory message)
        internal
        returns (uint256 packetId)
    {
        if (shares == 0) revert SharesZero();
        if (amount == 0) revert AmountZero();

        // to avoid "min 1" impossible cases in smallest unit
        if (amount < shares) revert AmountLessThanShares();

        packetId = nextPacketId++;
        packets[packetId] = Packet({
            kind: kind,
            token: token,
            createdAt: uint64(block.timestamp),
            targetSubgroupId: targetSubgroupId,
            sharesTotal: shares,
            totalAmount: amount,
            remainingAmount: amount,
            remainingShares: shares
        });

        emit PacketCreated(packetId, kind, token, targetSubgroupId, shares, amount);
        
        // Send packet message (bypass message limit and mute checks)
        _sendPacketMessage(packetId, kind, message, creator);
    }

    function _drawAmount(uint256 packetId, Packet storage p) internal returns (uint256) {
        uint32 rs = p.remainingShares;
        uint256 ra = p.remainingAmount;

        uint256 amount;
        if (rs == 1) {
            amount = ra;
        } else {
            uint256 base = ra / rs;
            // base might be 0 for small ra; but we already require ra >= rs
            uint256 max = base * 2;
            if (max == 0) {
                amount = 1;
            } else {
                uint256 rnd = uint256(
                    keccak256(
                        abi.encodePacked(
                            block.prevrandao,
                            block.timestamp,
                            msg.sender,
                            packetId,
                            ra,
                            rs
                        )
                    )
                );
                amount = (rnd % max) + 1; // [1, max]
                if (amount > ra) amount = ra; // just in case
            }
        }

        // update state
        p.remainingAmount = ra - amount;
        p.remainingShares = rs - 1;

        return amount;
    }

    function _reached(uint32 yesVotes, uint32 snapshotMembers, uint16 thresholdBps) internal pure returns (bool) {
        if (snapshotMembers == 0) return false;
        return uint256(yesVotes) * BPS_DENOM >= uint256(snapshotMembers) * thresholdBps;
    }

    function _requireNotMutedMain(address user) internal view {
        if (block.timestamp < globalMuteUntil[user]) revert GloballyMuted();
    }

    function _requireNotMutedSub(uint32 subgroupId, address user) internal view {
        uint64 g = globalMuteUntil[user];
        uint64 s = subgroupMuteUntil[subgroupId][user];
        uint64 untilTs = g >= s ? g : s;
        if (block.timestamp < untilTs) revert Muted();
    }

    /**
     * @notice Get start timestamp of current time period
     */
    function _getPeriodStart(MessageLimitType limitType) internal view returns (uint64) {
        if (limitType == MessageLimitType.DAILY) {
            // 0:00 UTC each day
            return uint64((block.timestamp / DAY) * DAY);
        } else if (limitType == MessageLimitType.WEEKLY) {
            // Start of week (using Monday 0:00 as baseline)
            uint64 daysSinceEpoch = uint64(block.timestamp / DAY);
            uint64 daysOffset = daysSinceEpoch % 7; // 0=Monday, 6=Sunday
            return uint64((daysSinceEpoch - daysOffset) * DAY);
        }
        return 0;
    }

    /**
     * @notice Check and update message count
     */
    function _checkAndUpdateMessageCount(address user) internal {
        if (mainMessageLimitType == MessageLimitType.NONE || mainMessageLimitCount == 0) {
            return; // Unlimited
        }

        uint64 currentPeriodStart = _getPeriodStart(mainMessageLimitType);
        MessageCount storage count = mainMessageCounts[user];

        // If entering new time period, reset count
        if (count.periodStart != currentPeriodStart) {
            count.count = 0;
            count.periodStart = currentPeriodStart;
        }

        // Check if limit exceeded
        if (count.count >= mainMessageLimitCount) revert MessageLimitExceeded();

        // Increment count
        count.count += 1;
    }

    /**
     * @notice Convert uint256 to string (for packetId)
     */
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        while (_i != 0) {
            bstr[--len] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }

    /**
     * @notice Send packet message (bypass message limit and mute checks)
     * @notice ENTRY type message format: packetId | {"groupType":"redpacket","msg":"Good luck and prosperity"}
     * @notice Other types message format: packetId | message
     */
    function _sendPacketMessage(
        uint256 packetId,
        PacketKind kind,
        string memory message,
        address sender
    ) internal {
        string memory packetIdStr = _uint2str(packetId);
        string memory content;
        
        if (kind == PacketKind.ENTRY) {
            // ENTRY type uses fixed format
            content = string(abi.encodePacked(
                packetIdStr,
                " | {\"groupType\":\"redpacket\",\"msg\":\"Good luck and prosperity\"}"
            ));
        } else {
            // Other types keep original format
            content = string(abi.encodePacked(packetIdStr, " | ", message));
        }
        
        // Store message directly, no limit or mute checks
        mainMessages.push(Message({
            from: sender,
            content: content,
            timestamp: uint64(block.timestamp),
            subgroupId: 0
        }));
        
        emit MainMessage(sender, content);
    }

    // ========== View Getters (with named return values for frontend/testing convenience) ==========

    /**
     * @notice Get member information
     */
    function getMember(address addr) external view returns (
        bool exists,
        uint64 joinAt,
        uint32 subgroupId
    ) {
        Member storage m = members[addr];
        return (m.exists, m.joinAt, m.subgroupId);
    }

    /**
     * @notice Get subgroup information
     */
    function getSubgroup(uint32 subgroupId) external view returns (
        bool exists,
        address owner,
        uint32 subgroupMemberCount
    ) {
        Subgroup storage s = subgroups[subgroupId];
        return (s.exists, s.owner, s.memberCount);
    }

    /**
     * @notice Get packet information
     */
    function getPacket(uint256 packetId) external view returns (
        PacketKind kind,
        address token,
        uint64 packetCreatedAt,
        uint32 targetSubgroupId,
        uint32 sharesTotal,
        uint256 totalAmount,
        uint256 remainingAmount,
        uint32 remainingShares
    ) {
        Packet storage p = packets[packetId];
        return (
            p.kind,
            p.token,
            p.createdAt,
            p.targetSubgroupId,
            p.sharesTotal,
            p.totalAmount,
            p.remainingAmount,
            p.remainingShares
        );
    }

    /**
     * @notice Get scheduled packet plan
     */
    function getSchedulePlan() external view returns (
        bool active,
        address token,
        uint32 remaining,
        uint64 interval,
        uint64 nextTime,
        uint256 currentAmount,
        uint16 decayBps
    ) {
        return (
            schedule.active,
            schedule.token,
            schedule.remaining,
            schedule.interval,
            schedule.nextTime,
            schedule.currentAmount,
            schedule.decayBps
        );
    }

    /**
     * @notice Get group settings (group name, economic model, group rules, announcement)
     */
    function getGroupSettings() external view returns (
        string memory groupName_,
        string memory economicModel_,
        string memory groupRules_,
        string memory announcement_
    ) {
        return (groupName, economicModel, groupRules, announcement);
    }

    /**
     * @notice Get member list length
     */
    function memberListLength() external view returns (uint256) {
        return memberList.length;
    }

    /**
     * @notice Get member address by index
     * @param index Index position (starting from 0)
     */
    function getMemberByIndex(uint256 index) external view returns (address) {
        if (index >= memberList.length) revert IndexOutOfBounds();
        return memberList[index];
    }

    /**
     * @notice Batch get member list (pagination)
     * @param offset Starting index
     * @param limit Maximum return count (recommend not exceeding 100 to avoid high gas)
     * @return members_ Member address array
     * @return count Actual returned member count
     */
    function getMembers(uint256 offset, uint256 limit) external view returns (
        address[] memory members_,
        uint256 count
    ) {
        uint256 total = memberList.length;
        if (offset >= total) {
            return (new address[](0), 0);
        }

        uint256 maxLimit = limit > 100 ? 100 : limit; // Limit maximum return count
        uint256 end = offset + maxLimit;
        if (end > total) {
            end = total;
        }

        uint256 resultCount = end - offset;
        members_ = new address[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            members_[i] = memberList[offset + i];
        }

        return (members_, resultCount);
    }

    /**
     * @notice Get total main group message count
     */
    function mainMessageCount() external view returns (uint256) {
        return mainMessages.length;
    }


    /**
     * @notice Get main group messages with pagination
     * @param offset Starting index
     * @param limit Maximum return count (recommend not exceeding 100 to avoid high gas)
     * @return messages Message array
     * @return count Actual returned message count
     */
    function getMainMessages(uint256 offset, uint256 limit) external view returns (
        Message[] memory messages,
        uint256 count
    ) {
        uint256 total = mainMessages.length;
        if (offset >= total) {
            return (new Message[](0), 0);
        }

        uint256 maxLimit = limit > 100 ? 100 : limit; // Limit maximum return count
        uint256 end = offset + maxLimit;
        if (end > total) {
            end = total;
        }

        uint256 resultCount = end - offset;
        messages = new Message[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            messages[i] = mainMessages[offset + i];
        }

        return (messages, resultCount);
    }

    /**
     * @notice Get packet claim count
     */
    function getPacketClaimCount(uint256 packetId) external view returns (uint256) {
        return packetClaimers[packetId].length;
    }

    /**
     * @notice Query packet claimers list with pagination
     * @param packetId Packet ID
     * @param offset Starting index
     * @param limit Maximum return count (recommend not exceeding 100 to avoid high gas)
     * @return claimers Claimer address array
     * @return count Actual returned claimer count
     */
    function getPacketClaimers(uint256 packetId, uint256 offset, uint256 limit) external view returns (
        address[] memory claimers,
        uint256 count
    ) {
        address[] storage claimersList = packetClaimers[packetId];
        uint256 total = claimersList.length;
        if (offset >= total) {
            return (new address[](0), 0);
        }

        uint256 maxLimit = limit > 100 ? 100 : limit;
        uint256 end = offset + maxLimit;
        if (end > total) {
            end = total;
        }

        uint256 resultCount = end - offset;
        claimers = new address[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            claimers[i] = claimersList[offset + i];
        }

        return (claimers, resultCount);
    }

    /**
     * @notice Query claim amount for a user in a packet
     * @param packetId Packet ID
     * @param claimer Claimer address
     * @return amount Claim amount, returns 0 if not claimed
     */
    function getPacketClaimDetail(uint256 packetId, address claimer) external view returns (uint256 amount) {
        return packetClaimAmounts[packetId][claimer];
    }

    /**
     * @notice Packet claim detail struct
     */
    struct ClaimDetail {
        address claimer;
        uint256 amount;
    }

    /**
     * @notice Query packet claim details with pagination (returns claimer address and amount)
     * @param packetId Packet ID
     * @param offset Starting index
     * @param limit Maximum return count (recommend not exceeding 100 to avoid high gas)
     * @return details Claim details array
     * @return count Actual returned detail count
     */
    function getPacketClaimDetails(uint256 packetId, uint256 offset, uint256 limit) external view returns (
        ClaimDetail[] memory details,
        uint256 count
    ) {
        address[] storage claimersList = packetClaimers[packetId];
        uint256 total = claimersList.length;
        if (offset >= total) {
            return (new ClaimDetail[](0), 0);
        }

        uint256 maxLimit = limit > 100 ? 100 : limit;
        uint256 end = offset + maxLimit;
        if (end > total) {
            end = total;
        }

        uint256 resultCount = end - offset;
        details = new ClaimDetail[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            address claimer = claimersList[offset + i];
            details[i] = ClaimDetail({
                claimer: claimer,
                amount: packetClaimAmounts[packetId][claimer]
            });
        }

        return (details, resultCount);
    }

    /**
     * @notice Query referral count for a referrer in this group
     * @param referrer Referrer address
     * @return count Referral count
     */
    function getReferralCount(address referrer) external view returns (uint256) {
        return referralCounts[referrer];
    }

    /**
     * @notice Get referrer list length
     */
    function referrerListLength() external view returns (uint256) {
        return referrerList.length;
    }

    /**
     * @notice Get referrer address by index
     * @param index Index position (starting from 0)
     */
    function getReferrerByIndex(uint256 index) external view returns (address) {
        if (index >= referrerList.length) revert IndexOutOfBounds();
        return referrerList[index];
    }

    /**
     * @notice Leaderboard struct
     */
    struct ReferralRank {
        address referrer;
        uint256 count;
    }

    /**
     * @notice Internal sort function (using selection sort, descending by referral count)
     * @param ranks Leaderboard array to sort
     */
    function _sortReferralRanks(ReferralRank[] memory ranks) internal pure {
        uint256 n = ranks.length;
        for (uint256 i = 0; i < n - 1; i++) {
            uint256 maxIdx = i;
            for (uint256 j = i + 1; j < n; j++) {
                if (ranks[j].count > ranks[maxIdx].count) {
                    maxIdx = j;
                }
            }
            if (maxIdx != i) {
                // Swap
                ReferralRank memory temp = ranks[i];
                ranks[i] = ranks[maxIdx];
                ranks[maxIdx] = temp;
            }
        }
    }

    /**
     * @notice Get referral leaderboard with pagination (sorted on-chain, descending by referral count)
     * @param offset Starting index (post-sort index)
     * @param limit Maximum return count (recommend not exceeding 100 to avoid high gas)
     * @return ranks Leaderboard array (contains referrer address and referral count, sorted descending)
     * @return count Actual returned count
     */
    function getReferralLeaderboard(uint256 offset, uint256 limit) external view returns (
        ReferralRank[] memory ranks,
        uint256 count
    ) {
        uint256 total = referrerList.length;
        if (total == 0) {
            return (new ReferralRank[](0), 0);
        }

        // Build complete leaderboard data
        ReferralRank[] memory allRanks = new ReferralRank[](total);
        for (uint256 i = 0; i < total; i++) {
            address referrer = referrerList[i];
            allRanks[i] = ReferralRank({
                referrer: referrer,
                count: referralCounts[referrer]
            });
        }

        // On-chain sort (descending by referral count)
        _sortReferralRanks(allRanks);

        // Pagination
        if (offset >= total) {
            return (new ReferralRank[](0), 0);
        }

        uint256 maxLimit = limit > 100 ? 100 : limit; // Limit maximum return count
        uint256 end = offset + maxLimit;
        if (end > total) {
            end = total;
        }

        uint256 resultCount = end - offset;
        ranks = new ReferralRank[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            ranks[i] = allRanks[offset + i];
        }

        return (ranks, resultCount);
    }

}
