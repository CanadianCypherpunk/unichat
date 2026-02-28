// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGroup {
    function isActiveMember(address account) external view returns (bool);
}

/**
 * @title UniChatRedPacket
 * @notice Token red packet contract: supports personal red packets / group red packets, only tokens in the "recommended token list" can create red packets.
 *
 * Key rules:
 * - Only tokens in the recommended token list can create red packets.
 * - The only way to add tokens to the recommended list:
 *      - Regular tokens: any address stakes stakeUnichatAmount UNICHAT tokens;
 *      - Core tokens (WBTC/WETH/USDT/USDC/WBNB etc.): only Owner can add via setCoreToken, no staking required.
 * - Group red packets: groupContract needs to implement isActiveMember(account).
 * - Random red packets: amounts are pre-allocated off-chain, on-chain only handles sequential distribution.
 */
contract UniChatRedPacket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========================================
    //              Enums & Structs
    // ========================================

    enum PacketType {
        Personal,
        Group
    }

    enum PacketStatus {
        Active,
        Exhausted,
        Refunded
    }

    struct RedPacket {
        uint256 id;
        address creator;
        address token;
        uint256 totalAmount;    // Total amount including tax
        uint256 distributable;  // Distributable amount (after tax deduction)
        uint256 totalShares;    // Total shares (fixed to 1 for personal red packets)
        uint256 claimedShares;  // Claimed shares
        uint256 claimedAmount;  // Total claimed amount
        PacketType packetType;
        PacketStatus status;
        uint256 createdAt;
        uint256 expiryTime;
        address personalRecipient; // Personal red packet recipient
        address groupContract;     // Group contract bound to group red packet
        bool isRandom;             // Whether group red packet is random
    }

    struct RecommendedTokenInfo {
        bool isRecommended;
        string iconCid;        // IPFS CID
        address submitter;     // Address that staked UNICHAT
        uint256 stakedUnichat; // Amount of staked UNICHAT
        bool isCore;           // Whether it's a core token (only Owner can manage)
    }

    struct ClaimRecord {
        address claimer;
        uint256 amount;
        uint256 claimedAt;
    }

    // ========================================
    //              State Variables
    // ========================================

    // Red packet ID counter
    uint256 public nextPacketId;

    // Red packet details
    mapping(uint256 => RedPacket) private _packets;

    // Whether each address has claimed for each red packet
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // Pre-allocated amounts array for random red packets: packetId => amounts[]
    mapping(uint256 => uint256[]) private _randomShareAmounts;

    // Claim records array for each red packet
    mapping(uint256 => ClaimRecord[]) private _claimRecords;

    // Recommended token information: token => info
    mapping(address => RecommendedTokenInfo) public recommendedTokens;

    // Recommended token list index
    address[] private _recommendedTokenList;

    // Recommended token index mapping: 0 means not exists, >0 means index+1
    mapping(address => uint256) private _recommendedTokenIndex;

    // Core token flag (e.g., WBTC/WETH/USDT/USDC/WBNB)
    mapping(address => bool) public isCoreToken;

    // Disabled token flag (only affects new red packet creation, old red packets can still be claimed)
    mapping(address => bool) public disabledTokens;

    // Default tax rate for each token (in basis points)
    mapping(address => uint16) public defaultTaxRate; // 100 = 1%

    // UNICHAT token address (for staking)
    address public immutable UNICHAT_TOKEN;

    // Staked UNICHAT amount (with decimals), e.g., 10000 * 10^18
    uint256 public immutable stakeUnichatAmount;

    // Treasury address for receiving tax / staking fees
    address public treasury;

    // Default expiry duration (in seconds), e.g., 100 hours = 100 * 3600
    uint256 public defaultExpiryDuration;

    /// @notice Chat contracts (Community / DirectMessage) that can create red packets on behalf of users
    mapping(address => bool) public isChatContract;

    // ========================================
    //                   Events
    // ========================================

    event PersonalPacketCreated(
        uint256 indexed id,
        address indexed creator,
        address indexed token,
        address recipient,
        uint256 totalAmount,
        uint256 distributable,
        uint256 expiryTime
    );

    event GroupPacketCreated(
        uint256 indexed id,
        address indexed creator,
        address indexed token,
        address groupContract,
        uint256 totalAmount,
        uint256 distributable,
        uint256 totalShares,
        bool isRandom,
        uint256 expiryTime
    );

    event PersonalPacketClaimed(
        uint256 indexed id,
        address indexed claimer,
        uint256 amount
    );

    event GroupPacketClaimed(
        uint256 indexed id,
        address indexed claimer,
        uint256 amount
    );

    event PacketRefunded(
        uint256 indexed id,
        address indexed creator,
        uint256 amount
    );

    event RecommendedTokenAdded(
        address indexed token,
        address indexed submitter,
        string iconCid,
        uint256 stakedAmount,
        bool isCore
    );

    event RecommendedTokenUpdated(
        address indexed token,
        string iconCid
    );

    event CoreTokenSet(address indexed token, bool isCore);

    event TokenDisabled(address indexed token);
    event TokenEnabled(address indexed token);

    event DefaultTaxRateSet(address indexed token, uint16 rate);
    event TreasuryUpdated(address indexed newTreasury);
    event DefaultExpiryDurationUpdated(uint256 newDuration);

    event OwnerTokenWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /// @notice Chat contract whitelist update event
    event ChatContractUpdated(address indexed chat, bool allowed);

    // ========================================
    //                Constructor
    // ========================================

    constructor(
        address unichatToken_,
        address treasury_,
        uint256 defaultExpiryDuration_,
        uint256 stakeUnichatAmount_
    ) Ownable(msg.sender) {
        require(unichatToken_ != address(0), "UNICHAT zero");
        require(treasury_ != address(0), "Treasury zero");
        require(defaultExpiryDuration_ > 0, "Expiry zero");
        require(stakeUnichatAmount_ > 0, "Stake amount zero");

        UNICHAT_TOKEN = unichatToken_;
        treasury = treasury_;
        defaultExpiryDuration = defaultExpiryDuration_;
        stakeUnichatAmount = stakeUnichatAmount_;
        nextPacketId = 1;
    }

    // ========================================
    //            Modifiers & Internal Utils
    // ========================================

    modifier onlyExistingPacket(uint256 packetId) {
        require(_packets[packetId].creator != address(0), "Packet not found");
        _;
    }

    /// @notice Only whitelisted chat contracts can call
    modifier onlyChatContract() {
        require(isChatContract[msg.sender], "NotChatContract");
        _;
    }

    function _ensureRecommendedAndEnabled(address token) internal view {
        RecommendedTokenInfo storage info = recommendedTokens[token];
        require(info.isRecommended, "Token not recommended");
        require(!disabledTokens[token], "Token disabled");
    }

    function _computeExpiry(uint256 expiryDuration) internal view returns (uint256) {
        uint256 duration = expiryDuration == 0 ? defaultExpiryDuration : expiryDuration;
        require(duration > 0, "Invalid duration");
        return block.timestamp + duration;
    }

    function _collectAndDistributeTax(
        address token,
        address from,
        uint256 totalAmount
    ) internal returns (uint256 distributable) {
        require(totalAmount > 0, "Zero amount");

        IERC20(token).safeTransferFrom(from, address(this), totalAmount);

        uint16 rate = defaultTaxRate[token];
        if (rate > 0) {
            require(rate <= 10_000, "Tax too high");
            uint256 taxAmount = (totalAmount * rate) / 10_000;
            distributable = totalAmount - taxAmount;

            if (taxAmount > 0) {
                IERC20(token).safeTransfer(treasury, taxAmount);
            }
        } else {
            distributable = totalAmount;
        }
    }

    function _updateStatusIfExhausted(RedPacket storage packet) internal {
        if (
            packet.claimedShares == packet.totalShares &&
            packet.claimedAmount == packet.distributable
        ) {
            packet.status = PacketStatus.Exhausted;
        }
    }

    function _removeFromRecommendedList(address token) internal {
        uint256 index = _recommendedTokenIndex[token];
        if (index == 0) {
            return; // Not in the list
        }
        
        uint256 actualIndex = index - 1; // Convert to 0-based index
        uint256 lastIndex = _recommendedTokenList.length - 1;
        
        if (actualIndex != lastIndex) {
            // Use swap method to delete: move the last element to current position
            address lastToken = _recommendedTokenList[lastIndex];
            _recommendedTokenList[actualIndex] = lastToken;
            _recommendedTokenIndex[lastToken] = index; // Update the index of the last element
        }
        
        // Remove the last element
        _recommendedTokenList.pop();
        delete _recommendedTokenIndex[token];
    }

    // ========================================
    //           Create Red Packet Interfaces
    // ========================================

    /**
     * @notice Create personal red packet (always 1 share, non-random).
     * @param token Token address (must be in recommended list)
     * @param totalAmount Total amount including tax (creator needs to approve in advance)
     * @param recipient Personal red packet recipient address
     * @param expiryDuration Red packet validity duration (in seconds), 0 = use contract default
     */
    function createPersonalPacket(
        address token,
        uint256 totalAmount,
        address recipient,
        uint256 expiryDuration
    ) external nonReentrant returns (uint256 packetId) {
        return _createPersonalPacket(msg.sender, token, totalAmount, recipient, expiryDuration);
    }

    /**
     * @notice Chat contract creates "personal red packet" on behalf of user
     * @dev Funds are deducted from creator address, creator is written to RedPacket.creator field
     * @param creator The actual red packet creator (funds deducted from here)
     * @param token Token address (must be in recommended list)
     * @param totalAmount Total amount including tax (creator needs to approve to red packet contract in advance)
     * @param recipient Personal red packet recipient address
     * @param expiryDuration Red packet validity duration (in seconds), 0 = use contract default
     */
    function createPersonalPacketFor(
        address creator,
        address token,
        uint256 totalAmount,
        address recipient,
        uint256 expiryDuration
    ) external nonReentrant onlyChatContract returns (uint256 packetId) {
        require(creator != address(0), "Creator zero");
        return _createPersonalPacket(creator, token, totalAmount, recipient, expiryDuration);
    }

    /**
     * @notice Internal function: create personal red packet
     * @dev Extract core logic for reuse by createPersonalPacket and createPersonalPacketFor
     */
    function _createPersonalPacket(
        address creator,
        address token,
        uint256 totalAmount,
        address recipient,
        uint256 expiryDuration
    ) internal returns (uint256 packetId) {
        require(recipient != address(0), "Recipient zero");
        _ensureRecommendedAndEnabled(token);

        uint256 distributable = _collectAndDistributeTax(
            token,
            creator,
            totalAmount
        );

        uint256 expiryTime = _computeExpiry(expiryDuration);

        packetId = nextPacketId++;
        RedPacket storage packet = _packets[packetId];

        packet.id = packetId;
        packet.creator = creator;
        packet.token = token;
        packet.totalAmount = totalAmount;
        packet.distributable = distributable;
        packet.totalShares = 1;
        packet.claimedShares = 0;
        packet.claimedAmount = 0;
        packet.packetType = PacketType.Personal;
        packet.status = PacketStatus.Active;
        packet.createdAt = block.timestamp;
        packet.expiryTime = expiryTime;
        packet.personalRecipient = recipient;
        packet.groupContract = address(0);
        packet.isRandom = false;

        emit PersonalPacketCreated(
            packetId,
            creator,
            token,
            recipient,
            totalAmount,
            distributable,
            expiryTime
        );
    }

    /**
     * @notice Create group red packet (equal or random).
     * @param token Token address (must be in recommended list)
     * @param totalAmount Total amount including tax (needs to approve in advance)
     * @param totalShares Number of shares (each address can claim at most 1 share)
     * @param isRandom Whether it's a random red packet
     * @param groupContract Group contract address (needs to implement isActiveMember)
     * @param shareAmounts When isRandom is true, off-chain pre-allocated amounts array, length must equal totalShares;
     *                     Only requires sum(shareAmounts) <= distributable, excess amount will be refunded to creator upon expiry.
     * @param expiryDuration Validity duration (in seconds), 0 = use default value
     */
    function createGroupPacket(
        address token,
        uint256 totalAmount,
        uint256 totalShares,
        bool isRandom,
        address groupContract,
        uint256[] calldata shareAmounts,
        uint256 expiryDuration
    ) external nonReentrant returns (uint256 packetId) {
        return _createGroupPacket(msg.sender, token, totalAmount, totalShares, isRandom, groupContract, shareAmounts, expiryDuration);
    }

    /**
     * @notice Chat contract creates "group red packet" on behalf of user
     * @dev Funds are deducted from creator address, creator is written to RedPacket.creator field
     * @param creator The actual red packet creator (funds deducted from here)
     * @param token Token address (must be in recommended list)
     * @param totalAmount Total amount including tax (creator needs to approve to red packet contract in advance)
     * @param totalShares Number of shares (each address can claim at most 1 share)
     * @param isRandom Whether it's a random red packet
     * @param groupContract Group contract address (needs to implement isActiveMember)
     * @param shareAmounts When isRandom is true, off-chain pre-allocated amounts array
     * @param expiryDuration Validity duration (in seconds), 0 = use default value
     */
    function createGroupPacketFor(
        address creator,
        address token,
        uint256 totalAmount,
        uint256 totalShares,
        bool isRandom,
        address groupContract,
        uint256[] calldata shareAmounts,
        uint256 expiryDuration
    ) external nonReentrant onlyChatContract returns (uint256 packetId) {
        require(creator != address(0), "Creator zero");
        return _createGroupPacket(creator, token, totalAmount, totalShares, isRandom, groupContract, shareAmounts, expiryDuration);
    }

    /**
     * @notice Internal function: create group red packet
     * @dev Extract core logic for reuse by createGroupPacket and createGroupPacketFor
     */
    function _createGroupPacket(
        address creator,
        address token,
        uint256 totalAmount,
        uint256 totalShares,
        bool isRandom,
        address groupContract,
        uint256[] calldata shareAmounts,
        uint256 expiryDuration
    ) internal returns (uint256 packetId) {
        require(groupContract != address(0), "Group zero");
        require(totalShares > 0, "Shares zero");
        _ensureRecommendedAndEnabled(token);

        uint256 distributable = _collectAndDistributeTax(
            token,
            creator,
            totalAmount
        );

        uint256 expiryTime = _computeExpiry(expiryDuration);

        packetId = nextPacketId++;
        RedPacket storage packet = _packets[packetId];

        packet.id = packetId;
        packet.creator = creator;
        packet.token = token;
        packet.totalAmount = totalAmount;
        packet.distributable = distributable;
        packet.totalShares = totalShares;
        packet.claimedShares = 0;
        packet.claimedAmount = 0;
        packet.packetType = PacketType.Group;
        packet.status = PacketStatus.Active;
        packet.createdAt = block.timestamp;
        packet.expiryTime = expiryTime;
        packet.personalRecipient = address(0);
        packet.groupContract = groupContract;
        packet.isRandom = isRandom;

        if (isRandom) {
            require(shareAmounts.length == totalShares, "Invalid shares length");
            uint256 sumShares;
            for (uint256 i = 0; i < shareAmounts.length; i++) {
                require(shareAmounts[i] > 0, "Share zero");
                sumShares += shareAmounts[i];
            }
            require(sumShares <= distributable, "Sum shares exceeds distributable");

            uint256[] storage arr = _randomShareAmounts[packetId];
            for (uint256 i = 0; i < shareAmounts.length; i++) {
                arr.push(shareAmounts[i]);
            }
        } else {
            require(shareAmounts.length == 0, "shareAmounts must be empty");
            // For equal red packets, amount per share = distributable / totalShares
            // Remainder will be refunded to creator via refundExpiredPacket upon expiry
        }

        emit GroupPacketCreated(
            packetId,
            creator,
            token,
            groupContract,
            totalAmount,
            distributable,
            totalShares,
            isRandom,
            expiryTime
        );
    }

    // ========================================
    //           Claim Red Packet Interfaces
    // ========================================

    /**
     * @notice Claim personal red packet.
     *         Rules: msg.sender must equal personalRecipient, and must not have claimed before.
     */
    function claimPersonalPacket(
        uint256 packetId
    ) external nonReentrant onlyExistingPacket(packetId) {
        RedPacket storage packet = _packets[packetId];

        require(packet.packetType == PacketType.Personal, "Not personal");
        require(packet.status == PacketStatus.Active, "Not active");
        require(block.timestamp <= packet.expiryTime, "Expired");
        require(!hasClaimed[packetId][msg.sender], "Already claimed");
        require(msg.sender == packet.personalRecipient, "Not recipient");
        require(packet.totalShares == 1, "Invalid shares");

        hasClaimed[packetId][msg.sender] = true;
        packet.claimedShares = 1;

        uint256 amount = packet.distributable;
        packet.claimedAmount = amount;
        packet.status = PacketStatus.Exhausted;

        // Record claim details
        _claimRecords[packetId].push(
            ClaimRecord({
                claimer: msg.sender,
                amount: amount,
                claimedAt: block.timestamp
            })
        );

        IERC20(packet.token).safeTransfer(msg.sender, amount);

        emit PersonalPacketClaimed(packetId, msg.sender, amount);
    }

    /**
     * @notice Claim group red packet.
     *         Rules: caller must be an active group member, each address can only claim once per red packet.
     */
    function claimGroupPacket(
        uint256 packetId
    ) external nonReentrant onlyExistingPacket(packetId) {
        RedPacket storage packet = _packets[packetId];

        require(packet.packetType == PacketType.Group, "Not group");
        require(packet.status == PacketStatus.Active, "Not active");
        require(block.timestamp <= packet.expiryTime, "Expired");
        require(!hasClaimed[packetId][msg.sender], "Already claimed");
        require(packet.claimedShares < packet.totalShares, "No shares left");
        require(packet.groupContract != address(0), "Group not set");

        // Verify group membership
        require(
            IGroup(packet.groupContract).isActiveMember(msg.sender),
            "Not group member"
        );

        uint256 amount;
        if (!packet.isRandom) {
            uint256 perShare = packet.distributable / packet.totalShares;
            require(perShare > 0, "Per share is zero");
            amount = perShare;
        } else {
            uint256 shareIndex = packet.claimedShares; // 0-based
            uint256[] storage shares = _randomShareAmounts[packetId];
            require(shareIndex < shares.length, "No more random shares");
            amount = shares[shareIndex];
        }

        hasClaimed[packetId][msg.sender] = true;
        packet.claimedShares += 1;
        packet.claimedAmount += amount;

        _updateStatusIfExhausted(packet);

        // Record claim details
        _claimRecords[packetId].push(
            ClaimRecord({
                claimer: msg.sender,
                amount: amount,
                claimedAt: block.timestamp
            })
        );

        IERC20(packet.token).safeTransfer(msg.sender, amount);

        emit GroupPacketClaimed(packetId, msg.sender, amount);
    }

    // ========================================
    //        Expired Refund / Owner Withdraw
    // ========================================

    /**
     * @notice Anyone can trigger expired red packet refund, remaining balance returned to creator.
     *         Conditions: current time > expiryTime and status is Active, and there is remaining distributable - claimedAmount.
     */
    function refundExpiredPacket(
        uint256 packetId
    ) external nonReentrant onlyExistingPacket(packetId) {
        RedPacket storage packet = _packets[packetId];

        require(packet.status == PacketStatus.Active, "Not refundable");
        require(block.timestamp > packet.expiryTime, "Not expired");

        uint256 remaining = packet.distributable - packet.claimedAmount;
        require(remaining > 0, "No remaining");

        packet.status = PacketStatus.Refunded;

        IERC20(packet.token).safeTransfer(packet.creator, remaining);

        emit PacketRefunded(packetId, packet.creator, remaining);
    }

    /**
     * @notice Owner can withdraw any amount of any token from the contract (high privilege).
     */
    function ownerWithdrawToken(
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        IERC20(token).safeTransfer(msg.sender, amount);
        emit OwnerTokenWithdrawn(token, msg.sender, amount);
    }

    // ========================================
    //      Recommended Tokens / Admin Logic
    // ========================================

    /**
     * @notice Regular tokens join recommended list by staking stakeUnichatAmount UNICHAT tokens.
     *         Not applicable to tokens marked as core tokens.
     */
    function recommendToken(
        address token,
        string calldata iconCid
    ) external nonReentrant {
        require(token != address(0), "Token zero");
        require(!isCoreToken[token], "Core token only by owner");

        RecommendedTokenInfo storage info = recommendedTokens[token];
        require(!info.isRecommended, "Already recommended");

        IERC20(UNICHAT_TOKEN).safeTransferFrom(
            msg.sender,
            treasury,
            stakeUnichatAmount
        );

        info.isRecommended = true;
        info.iconCid = iconCid;
        info.submitter = msg.sender;
        info.stakedUnichat = stakeUnichatAmount;
        info.isCore = false;

        // Maintain array index
        _recommendedTokenList.push(token);
        _recommendedTokenIndex[token] = _recommendedTokenList.length;

        emit RecommendedTokenAdded(
            token,
            msg.sender,
            iconCid,
            stakeUnichatAmount,
            false
        );
    }

    /**
     * @notice Owner sets/cancels a token as core token.
     *         If set as core, automatically marked as recommended token, can set/update iconCid, no UNICHAT staking required.
     */
    function setCoreToken(
        address token,
        bool isCore,
        string calldata iconCid
    ) external onlyOwner {
        require(token != address(0), "Token zero");

        isCoreToken[token] = isCore;

        RecommendedTokenInfo storage info = recommendedTokens[token];
        info.isCore = isCore;

        if (isCore) {
            info.isRecommended = true;
            info.iconCid = iconCid;
            info.submitter = owner();
            
            // If token is not in recommended list, add to array
            if (_recommendedTokenIndex[token] == 0) {
                _recommendedTokenList.push(token);
                _recommendedTokenIndex[token] = _recommendedTokenList.length;
            }
            
            // Core tokens don't need UNICHAT staking
            emit RecommendedTokenAdded(
                token,
                owner(),
                iconCid,
                0,
                true
            );
        } else {
            // Remove from recommended list
            _removeFromRecommendedList(token);
            emit CoreTokenSet(token, false);
        }
    }

    /**
     * @notice Owner updates iconCid of a recommended token (including core tokens).
     */
    function updateRecommendedTokenIcon(
        address token,
        string calldata iconCid
    ) external onlyOwner {
        RecommendedTokenInfo storage info = recommendedTokens[token];
        require(info.isRecommended, "Not recommended");

        info.iconCid = iconCid;
        emit RecommendedTokenUpdated(token, iconCid);
    }

    /**
     * @notice Owner disables a token (only affects new red packet creation).
     */
    function disableToken(address token) external onlyOwner {
        disabledTokens[token] = true;
        emit TokenDisabled(token);
    }

    /**
     * @notice Owner enables a token.
     */
    function enableToken(address token) external onlyOwner {
        disabledTokens[token] = false;
        emit TokenEnabled(token);
    }

    /**
     * @notice Owner sets default tax rate for a token (in basis points, 100 = 1%).
     */
    function setDefaultTaxRate(
        address token,
        uint16 rate
    ) external onlyOwner {
        require(rate <= 10_000, "Rate too high");
        defaultTaxRate[token] = rate;
        emit DefaultTaxRateSet(token, rate);
    }

    /**
     * @notice Owner updates treasury address.
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Treasury zero");
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    /**
     * @notice Owner updates default expiry duration (in seconds).
     */
    function setDefaultExpiryDuration(
        uint256 newDuration
    ) external onlyOwner {
        require(newDuration > 0, "Duration zero");
        defaultExpiryDuration = newDuration;
        emit DefaultExpiryDurationUpdated(newDuration);
    }

    /**
     * @notice Owner sets chat contract whitelist (Community / DirectMessage)
     * @param chat Chat contract address
     * @param allowed Whether allowed
     */
    function setChatContract(address chat, bool allowed) external onlyOwner {
        require(chat != address(0), "Chat zero");
        isChatContract[chat] = allowed;
        emit ChatContractUpdated(chat, allowed);
    }

    // ========================================
    //                 View Functions
    // ========================================

    /**
     * @notice Get red packet details.
     */
    function getPacket(
        uint256 packetId
    ) external view onlyExistingPacket(packetId) returns (RedPacket memory) {
        return _packets[packetId];
    }

    /**
     * @notice Get pre-allocated amounts array for a random red packet (only meaningful for random red packets).
     */
    function getRandomShareAmounts(
        uint256 packetId
    ) external view returns (uint256[] memory) {
        return _randomShareAmounts[packetId];
    }

    /**
     * @notice Check whether a token is in the recommended list.
     */
    function isTokenRecommended(
        address token
    ) external view returns (bool) {
        return recommendedTokens[token].isRecommended;
    }

    /**
     * @notice Paginated query of red packet claim records.
     * @param packetId Red packet ID
     * @param offset Offset
     * @param limit Items per page
     * @return result Claim records array
     */
    function getClaimRecordsPaged(
        uint256 packetId,
        uint256 offset,
        uint256 limit
    ) external view onlyExistingPacket(packetId) returns (ClaimRecord[] memory result) {
        ClaimRecord[] storage all = _claimRecords[packetId];
        uint256 len = all.length;
        
        if (offset >= len) {
            return new ClaimRecord[](0);
        }
        
        uint256 end = offset + limit;
        if (end > len) {
            end = len;
        }
        
        uint256 size = end - offset;
        result = new ClaimRecord[](size);
        
        for (uint256 i = 0; i < size; i++) {
            result[i] = all[offset + i];
        }
    }

    /**
     * @notice Paginated query of recommended token list.
     * @param offset Offset
     * @param limit Items per page
     * @return tokens Token address array
     */
    function getRecommendedTokensPaged(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory tokens) {
        uint256 len = _recommendedTokenList.length;
        
        if (offset >= len) {
            return new address[](0);
        }
        
        uint256 end = offset + limit;
        if (end > len) {
            end = len;
        }
        
        uint256 size = end - offset;
        tokens = new address[](size);
        
        for (uint256 i = 0; i < size; i++) {
            tokens[i] = _recommendedTokenList[offset + i];
        }
    }

    /**
     * @notice Get complete information of all recommended tokens.
     * @return tokens Token address array
     * @return infos Recommended token information array
     */
    function getAllRecommendedTokenInfos()
        external
        view
        returns (address[] memory tokens, RecommendedTokenInfo[] memory infos)
    {
        uint256 len = _recommendedTokenList.length;
        tokens = new address[](len);
        infos = new RecommendedTokenInfo[](len);
        
        for (uint256 i = 0; i < len; i++) {
            address token = _recommendedTokenList[i];
            tokens[i] = token;
            infos[i] = recommendedTokens[token];
        }
    }
}
