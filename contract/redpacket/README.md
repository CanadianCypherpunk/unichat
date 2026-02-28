# UniChat Red Packet Contract

A comprehensive token distribution system supporting personal and group red packets with a recommendation-based token whitelist mechanism.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Red Packet Types](#red-packet-types)
- [Token Recommendation System](#token-recommendation-system)
- [Usage Guide](#usage-guide)
- [Function Reference](#function-reference)
- [Chat Contract Integration](#chat-contract-integration)
- [Security](#security)
- [Events](#events)

## Overview

The UniChatRedPacket contract provides a flexible red packet (lucky money) distribution system for the UniChat ecosystem. It supports both personal (1-to-1) and group red packets with equal or random distribution algorithms.

### What Problem Does It Solve?

- **Token Distribution**: Efficient way to distribute tokens to individuals or groups
- **Quality Control**: Only recommended tokens can be used (reduces scam risk)
- **Platform Revenue**: Optional tax system generates platform income
- **Group Integration**: Seamless integration with chat and community contracts
- **Expiry Management**: Automatic refund of unclaimed packets

### Use Cases

- Birthday/holiday gifts between friends
- Community rewards and airdrops
- Marketing campaigns and giveaways
- DAO member incentives
- Game rewards and prizes

## Architecture

### Contract Components

```
UniChatRedPacket
├── Red Packet Management
│   ├── Personal packets (1 recipient)
│   ├── Group packets (N shares)
│   ├── Equal distribution
│   └── Random distribution
│
├── Token Recommendation System
│   ├── Core tokens (owner-managed)
│   ├── Regular tokens (stake-based)
│   ├── IPFS icon storage
│   └── Enable/disable mechanism
│
├── Tax System
│   ├── Per-token tax rates
│   ├── Treasury routing
│   └── Distributable calculation
│
└── Chat Integration
    ├── DirectMessage support
    ├── Community support
    └── Create-on-behalf functionality
```

### Data Structures

#### RedPacket Struct
```solidity
struct RedPacket {
    uint256 id;
    address creator;
    address token;
    uint256 totalAmount;       // Including tax
    uint256 distributable;     // After tax
    uint256 totalShares;       // Fixed to 1 for personal
    uint256 claimedShares;
    uint256 claimedAmount;
    PacketType packetType;     // Personal or Group
    PacketStatus status;       // Active, Exhausted, Refunded
    uint256 createdAt;
    uint256 expiryTime;
    address personalRecipient; // For personal packets
    address groupContract;     // For group packets
    bool isRandom;            // Random or equal distribution
}
```

#### Token Info Struct
```solidity
struct RecommendedTokenInfo {
    bool isRecommended;
    string iconCid;           // IPFS CID
    address submitter;        // Who staked
    uint256 stakedUnichat;    // Stake amount
    bool isCore;              // Core token flag
}
```

## Red Packet Types

### Personal Red Packets

**Purpose**: Send tokens directly to one recipient

**Characteristics**:
- Single share (totalShares = 1)
- Specific recipient address
- Not random (full amount to recipient)
- Expires after set duration

**Use Cases**:
- Birthday gifts
- Thank you payments
- Personal rewards
- Direct transfers with message

**Creation**:
```solidity
uint256 packetId = redPacket.createPersonalPacket(
    token,           // ERC20 token address
    1000e18,         // Total amount (including tax)
    recipientAddr,   // Who can claim
    86400           // Expiry: 24 hours
);
```

**Claiming**:
```solidity
// Only recipient can claim
redPacket.claimPersonalPacket(packetId);
```

### Group Red Packets (Equal)

**Purpose**: Distribute tokens equally among group members

**Characteristics**:
- Multiple shares (N shares)
- Equal amount per share
- First-come-first-served
- Requires group membership

**Distribution Formula**:
```
perShare = distributableAmount / totalShares
remainder = distributableAmount % totalShares
// Remainder refunded to creator on expiry
```

**Example**:
- Total: 1000 tokens
- Shares: 10
- Each share: 100 tokens
- Any 10 group members can claim 100 tokens each

**Creation**:
```solidity
uint256 packetId = redPacket.createGroupPacket(
    token,
    1000e18,         // Total amount
    10,              // 10 shares
    false,           // Not random
    groupContract,   // Community/Group address
    [],              // Empty for equal distribution
    3600            // Expiry: 1 hour
);
```

### Group Red Packets (Random)

**Purpose**: Create excitement with random amounts

**Characteristics**:
- Pre-allocated random amounts
- Off-chain randomness generation
- On-chain sequential distribution
- Sum of shares ≤ distributable amount

**How It Works**:
1. Frontend generates random distribution off-chain
2. Pass amounts array to contract
3. Contract validates sum ≤ distributable
4. Members claim in order, getting next amount in array

**Example Allocation**:
```javascript
// Frontend generates random amounts
const amounts = [150, 80, 200, 120, 100, 90, 110, 70, 50, 30];
// Total: 1000 tokens, 10 shares

// First claimer gets 150
// Second claimer gets 80
// Third claimer gets 200
// ... and so on
```

**Creation**:
```solidity
uint256[] memory randomAmounts = [150e18, 80e18, 200e18, ...];

uint256 packetId = redPacket.createGroupPacket(
    token,
    1000e18,
    10,              // 10 shares
    true,            // Random distribution
    groupContract,
    randomAmounts,   // Pre-allocated amounts
    3600
);
```

**Advantages**:
- Excitement factor (luck involved)
- Gamification
- Encourages faster claiming
- Still fair (everyone gets something)

## Token Recommendation System

### Purpose

Only tokens in the recommendation list can create red packets. This:
- Reduces scam tokens
- Ensures quality
- Generates platform revenue (from token listings)
- Provides curated token list for users

### Core Tokens

**Definition**: High-quality, well-known tokens managed by platform owner

**Examples**: WBTC, WETH, USDT, USDC, WBNB, DAI

**How to Add**:
```solidity
// Only owner can add core tokens
redPacket.setCoreToken(
    wbtcAddress,
    true,           // Set as core
    "QmHash..."     // IPFS icon CID
);
```

**Benefits**:
- No staking required
- Instant listing
- Higher trust level
- Platform endorsement

### Regular Tokens

**Definition**: Any token added by community via staking

**Staking Requirement**: 
- Must stake `stakeUnichatAmount` UNICHAT tokens
- Stake goes to treasury (not refundable)
- Permanent listing (unless disabled by owner)

**How to Add**:
```solidity
// Anyone can add by staking UNICHAT
unichat.approve(redPacketAddr, stakeAmount);
redPacket.recommendToken(
    myTokenAddress,
    "QmIconHash..."  // IPFS icon CID
);
```

**Token Information Storage**:
- `isRecommended`: true
- `iconCid`: IPFS hash for token icon
- `submitter`: Address that staked
- `stakedUnichat`: Amount staked
- `isCore`: false

### Token States

1. **Not Listed**: Cannot create red packets
2. **Recommended & Enabled**: Can create red packets
3. **Recommended & Disabled**: Temporarily disabled by owner
   - Existing packets can still be claimed
   - New packets cannot be created

### Managing Tokens

**Update Icon** (Owner):
```solidity
redPacket.updateRecommendedTokenIcon(token, "QmNewHash...");
```

**Disable Token** (Owner):
```solidity
redPacket.disableToken(token);
// Blocks new red packet creation
```

**Enable Token** (Owner):
```solidity
redPacket.enableToken(token);
// Allows red packet creation again
```

## Tax System

### Purpose

Generate platform revenue while providing red packet service.

### Configuration

**Per-Token Tax Rates**:
```solidity
// Owner sets tax rate (in basis points)
redPacket.setDefaultTaxRate(
    tokenAddress,
    100            // 1% (100 bps)
);
```

**Basis Points**:
- 1 bps = 0.01%
- 100 bps = 1%
- 10000 bps = 100%
- Max: 10000 (100%)

### Tax Calculation

```solidity
taxAmount = (totalAmount * taxRate) / 10000
distributable = totalAmount - taxAmount
```

**Example**:
- User sends 1000 tokens
- Tax rate: 2% (200 bps)
- Tax collected: 20 tokens → treasury
- Distributable: 980 tokens → red packet recipients

### No Tax Scenario

If `taxRate = 0`:
- `distributable = totalAmount`
- No deduction
- Full amount distributed

## Usage Guide

### Setup & Deployment

```solidity
// Deploy contract
UniChatRedPacket redPacket = new UniChatRedPacket(
    unichatTokenAddress,
    treasuryAddress,
    360000,              // Default expiry: 100 hours
    10000e18            // Stake amount: 10,000 UNICHAT
);

// Set core tokens
redPacket.setCoreToken(usdtAddress, true, "QmUSDT...");
redPacket.setCoreToken(wethAddress, true, "QmWETH...");

// Set tax rates
redPacket.setDefaultTaxRate(usdtAddress, 100); // 1%
redPacket.setDefaultTaxRate(wethAddress, 50);  // 0.5%
```

### Creating Red Packets

#### Personal Packet

```solidity
// 1. Approve tokens
IERC20(token).approve(address(redPacket), 1000e18);

// 2. Create packet
uint256 packetId = redPacket.createPersonalPacket(
    token,
    1000e18,         // Total amount
    bobAddress,      // Recipient
    86400           // 24 hour expiry
);

// Returns packet ID for tracking
```

#### Group Packet (Equal)

```solidity
// 1. Approve tokens
IERC20(token).approve(address(redPacket), 5000e18);

// 2. Create packet
uint256 packetId = redPacket.createGroupPacket(
    token,
    5000e18,         // Total amount
    20,              // 20 shares
    false,           // Equal distribution
    communityAddr,   // Group contract
    [],              // Empty for equal
    7200            // 2 hour expiry
);
```

#### Group Packet (Random)

```javascript
// Frontend: Generate random amounts
function generateRandomAmounts(total, shares) {
    const amounts = [];
    let remaining = total;
    
    for (let i = 0; i < shares - 1; i++) {
        const max = remaining - (shares - i - 1);
        const amount = Math.floor(Math.random() * max) + 1;
        amounts.push(amount);
        remaining -= amount;
    }
    amounts.push(remaining); // Last share gets remainder
    
    return shuffle(amounts); // Shuffle for randomness
}

const amounts = generateRandomAmounts(5000e18, 20);
```

```solidity
// On-chain: Create packet
uint256 packetId = redPacket.createGroupPacket(
    token,
    5000e18,
    20,
    true,            // Random distribution
    communityAddr,
    amounts,         // Pre-allocated amounts
    7200
);
```

### Claiming Red Packets

#### Personal Packet

```solidity
// Check packet details
RedPacket memory packet = redPacket.getPacket(packetId);
require(packet.personalRecipient == msg.sender);
require(block.timestamp <= packet.expiryTime);
require(!redPacket.hasClaimed(packetId, msg.sender));

// Claim
redPacket.claimPersonalPacket(packetId);
```

#### Group Packet

```solidity
// Must be group member
require(IGroup(groupContract).isActiveMember(msg.sender));

// Claim
redPacket.claimGroupPacket(packetId);
// Automatically gets next share (equal or random)
```

### Refunding Expired Packets

```solidity
// Anyone can trigger refund after expiry
RedPacket memory packet = redPacket.getPacket(packetId);
require(block.timestamp > packet.expiryTime);
require(packet.status == PacketStatus.Active);

// Refund remaining to creator
redPacket.refundExpiredPacket(packetId);
```

### Querying Packets

```solidity
// Get packet details
RedPacket memory packet = redPacket.getPacket(packetId);

// Get random amounts (for random packets)
uint256[] memory amounts = redPacket.getRandomShareAmounts(packetId);

// Get claim records
ClaimRecord[] memory records = redPacket.getClaimRecordsPaged(
    packetId,
    0,      // offset
    100     // limit
);

// Check if user claimed
bool claimed = redPacket.hasClaimed(packetId, userAddress);
```

### Managing Recommended Tokens

#### Add Regular Token

```solidity
// User adds token by staking
IERC20(unichat).approve(address(redPacket), stakeAmount);
redPacket.recommendToken(
    myTokenAddress,
    "QmIconCID..."
);
```

#### Query Tokens

```solidity
// Check if token is recommended
bool recommended = redPacket.isTokenRecommended(tokenAddr);

// Get token info
RecommendedTokenInfo memory info = redPacket.recommendedTokens(tokenAddr);

// Get all recommended tokens
(address[] memory tokens, RecommendedTokenInfo[] memory infos) 
    = redPacket.getAllRecommendedTokenInfos();

// Paginated query
address[] memory tokens = redPacket.getRecommendedTokensPaged(0, 50);
```

## Function Reference

### Red Packet Creation

#### `createPersonalPacket()`
```solidity
function createPersonalPacket(
    address token,
    uint256 totalAmount,
    address recipient,
    uint256 expiryDuration
) external nonReentrant returns (uint256 packetId)
```
Create personal red packet. User must approve tokens first.

#### `createGroupPacket()`
```solidity
function createGroupPacket(
    address token,
    uint256 totalAmount,
    uint256 totalShares,
    bool isRandom,
    address groupContract,
    uint256[] calldata shareAmounts,
    uint256 expiryDuration
) external nonReentrant returns (uint256 packetId)
```
Create group red packet. For random: `shareAmounts` must have length = `totalShares`.

### Chat Integration

#### `createPersonalPacketFor()`
```solidity
function createPersonalPacketFor(
    address creator,
    address token,
    uint256 totalAmount,
    address recipient,
    uint256 expiryDuration
) external nonReentrant onlyChatContract returns (uint256 packetId)
```
Chat contracts create personal packet on behalf of user.

#### `createGroupPacketFor()`
```solidity
function createGroupPacketFor(
    address creator,
    address token,
    uint256 totalAmount,
    uint256 totalShares,
    bool isRandom,
    address groupContract,
    uint256[] calldata shareAmounts,
    uint256 expiryDuration
) external nonReentrant onlyChatContract returns (uint256 packetId)
```
Chat contracts create group packet on behalf of user.

### Claiming

#### `claimPersonalPacket()`
```solidity
function claimPersonalPacket(
    uint256 packetId
) external nonReentrant onlyExistingPacket(packetId)
```

#### `claimGroupPacket()`
```solidity
function claimGroupPacket(
    uint256 packetId
) external nonReentrant onlyExistingPacket(packetId)
```

### Management

#### `refundExpiredPacket()`
```solidity
function refundExpiredPacket(
    uint256 packetId
) external nonReentrant onlyExistingPacket(packetId)
```

#### `ownerWithdrawToken()`
```solidity
function ownerWithdrawToken(
    address token,
    uint256 amount
) external onlyOwner nonReentrant
```
Emergency withdrawal by owner.

### Token Recommendation

#### `recommendToken()`
```solidity
function recommendToken(
    address token,
    string calldata iconCid
) external nonReentrant
```

#### `setCoreToken()`
```solidity
function setCoreToken(
    address token,
    bool isCore,
    string calldata iconCid
) external onlyOwner
```

#### `updateRecommendedTokenIcon()`
```solidity
function updateRecommendedTokenIcon(
    address token,
    string calldata iconCid
) external onlyOwner
```

#### `disableToken()` / `enableToken()`
```solidity
function disableToken(address token) external onlyOwner
function enableToken(address token) external onlyOwner
```

### Configuration

#### `setDefaultTaxRate()`
```solidity
function setDefaultTaxRate(
    address token,
    uint16 rate
) external onlyOwner
```

#### `setTreasury()`
```solidity
function setTreasury(address newTreasury) external onlyOwner
```

#### `setDefaultExpiryDuration()`
```solidity
function setDefaultExpiryDuration(
    uint256 newDuration
) external onlyOwner
```

#### `setChatContract()`
```solidity
function setChatContract(
    address chat,
    bool allowed
) external onlyOwner
```

## Chat Contract Integration

### Purpose

Allow chat contracts to create red packets on behalf of users for seamless UX.

### Setup

```solidity
// Owner whitelists chat contracts
redPacket.setChatContract(directMessageAddr, true);
redPacket.setChatContract(communityAddr, true);
```

### Usage in DirectMessage

```solidity
// DirectMessage contract code
function sendRedPacketMessage(
    address token,
    uint256 totalAmount,
    address recipient,
    uint256 expiryDuration,
    string calldata memo
) external returns (uint256 packetId) {
    // Create packet (funds from msg.sender)
    packetId = redPacket.createPersonalPacketFor(
        msg.sender,
        token,
        totalAmount,
        recipient,
        expiryDuration
    );
    
    // Send message with packet info
    _sendMessage(msg.sender, recipient, encodePacketMessage(packetId, memo));
}
```

### Usage in Community

```solidity
// Community contract code
function sendRedPacketMessage(
    address token,
    uint256 totalAmount,
    uint256 totalShares,
    bool isRandom,
    uint256[] calldata shareAmounts,
    uint256 expiryDuration,
    string calldata memo
) external returns (uint256 packetId) {
    // Create group packet (funds from msg.sender)
    packetId = redPacket.createGroupPacketFor(
        msg.sender,
        token,
        totalAmount,
        totalShares,
        isRandom,
        address(this),
        shareAmounts,
        expiryDuration
    );
    
    // Broadcast message with packet info
    _sendCommunityMessage(msg.sender, encodePacketMessage(packetId, memo));
}
```

## Security

### Implemented Protections

**Reentrancy Guard**: All external calls protected  
**Token Validation**: Only recommended tokens allowed  
**Expiry Enforcement**: Cannot claim expired packets  
**Group Membership**: Verified via group contract  
**Status Checks**: Prevents double claiming

### Potential Risks

**Random Distribution Gaming**: Early claimers see remaining amounts  
*Mitigation*: Off-chain randomness, accept as feature

**Token Price Volatility**: Value changes during packet lifetime  
*Mitigation*: Short expiry durations recommended

**Scam Tokens in Whitelist**: Malicious tokens listed via staking  
*Mitigation*: Owner disable function, due diligence

## Events

```solidity
event PersonalPacketCreated(uint256 indexed id, address indexed creator, address indexed token, address recipient, uint256 totalAmount, uint256 distributable, uint256 expiryTime);

event GroupPacketCreated(uint256 indexed id, address indexed creator, address indexed token, address groupContract, uint256 totalAmount, uint256 distributable, uint256 totalShares, bool isRandom, uint256 expiryTime);

event PersonalPacketClaimed(uint256 indexed id, address indexed claimer, uint256 amount);

event GroupPacketClaimed(uint256 indexed id, address indexed claimer, uint256 amount);

event PacketRefunded(uint256 indexed id, address indexed creator, uint256 amount);

event RecommendedTokenAdded(address indexed token, address indexed submitter, string iconCid, uint256 stakedAmount, bool isCore);
```

## License

MIT License

---

**Contract Version**: 1.0.0  
**Solidity**: ^0.8.24  
**Dependencies**: OpenZeppelin Contracts v5.x
