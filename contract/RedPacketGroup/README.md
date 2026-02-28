# UniChat Red Packet Group Contracts

A comprehensive on-chain group management system with red packet (lucky money) distribution, governance, and messaging features built for the UniChat ecosystem.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Key Features](#key-features)
- [Economic Model](#economic-model)
- [Contract Details](#contract-details)
- [Usage Guide](#usage-guide)
- [Function Reference](#function-reference)
- [Events Reference](#events-reference)
- [Security](#security)
- [Development](#development)

## Overview

The UniChat Red Packet Group system enables token-gated communities to create and manage groups with integrated red packet distribution, governance mechanisms, and communication features. The system uses a factory pattern with minimal proxy clones (EIP-1167) for gas-efficient group creation.

### What Problem Does It Solve?

- **Community Economics**: Built-in economic model with entry fees and red packet distribution
- **Democratic Governance**: On-chain voting for leadership changes
- **Token Gating**: Ensure only token holders can join
- **Moderation Tools**: Mute, fine, and rate limiting capabilities
- **Referral Incentives**: Track and reward user acquisition

### Use Cases

- DAO communities with token-based membership
- Investment groups with fee distribution
- Gaming guilds with reward systems
- Social clubs with hierarchical structure

## Architecture

The system consists of three main contracts working together:

### 1. UniChatRegistry.sol

**Purpose**: Global configuration center and token whitelist management

**Responsibilities**:
- **Token Whitelist Management**: Controls which tokens can be used to create groups
- **Referral System**: Manages referral codes with configurable commission rates (50-80%)
- **Platform Configuration**: Treasury address, factory contract, token-gating validator
- **Group Registry**: Tracks all created groups for discovery and indexing
- **Access Control**: OWNER_ROLE and BIG_OWNER_ROLE management

**Key Functions**:
- `applyTokenListing(token, referralCode)` - Apply to add token to whitelist (pays UNICHAT fee)
- `approveTokenListing(token, allowed)` - Owner approves/revokes tokens
- `createReferral(listingShareBps, salt)` - Create referral code with custom commission
- `registerGroup(group, groupToken, creator)` - Called by factory to register new groups

**Token Listing Process**:
1. User pays listing fee (default 20,000 UNICHAT)
2. If referral code provided, distribute commission (50-80% to referrer)
3. Automatically approved and added to whitelist
4. Token can now be used to create groups

### 2. GroupFactory.sol

**Purpose**: Factory for creating group instances using minimal proxy pattern

**Responsibilities**:
- Validate group tokens against registry whitelist
- Deploy gas-efficient clones of RedPacketGroup implementation
- Initialize new groups with proper parameters
- Register groups in the registry

**Deployment Pattern**:
```
Implementation Contract (deployed once)
    ↓
Factory clones → Group Instance 1
Factory clones → Group Instance 2
Factory clones → Group Instance 3
```

**Benefits**:
- Massive gas savings (deployment ~10x cheaper)
- Easy upgrades (deploy new implementation)
- Consistent interface across all groups

### 3. RedPacketGroup.sol

**Purpose**: Core group contract with all features

**Key Components**:

#### Group Management
- Main group with unlimited members
- Multiple subgroups with separate owners
- Hierarchical ownership structure
- Member list with join timestamps

#### Red Packet System
Three types of red packets:

1. **Entry Packets**
   - Auto-created when members join
   - Amount: 70% of entry fee
   - Distributed to existing members
   - Shares: current member count

2. **Normal Packets**
   - User-created, any token
   - For whole group or specific subgroup
   - Random distribution algorithm
   - Custom greeting message

3. **Scheduled Packets**
   - Owner configures: token, initial amount, decay rate
   - Automated daily distribution (365 rounds)
   - Decay: 0.1% - 99% per round
   - Anyone can trigger via `tickSchedule()`

#### Governance System
- **Main Group Election**: 51% member votes required, 6-month cooldown
- **Subgroup Election**: 75% member votes required, no cooldown
- One-address-one-vote system
- Immediate finalization upon reaching threshold

#### Messaging System
- On-chain message storage (280 bytes max)
- Rate limiting: daily or weekly message limits
- Mute functionality: global and per-subgroup
- Message pagination for efficient queries

#### Access Control
- Token gating via balance check or validator contract
- Join time barrier for packet claims
- Fine system for subgroup violations (paid in USDT)
- Role-based permissions (OWNER, BIG_OWNER)

## Key Features

### Red Packet Distribution

#### Entry Packet Mechanism
When a new member joins:
1. Pays entry fee in group token
2. Fee split: 9% owner / 21% referrer / 70% pool
3. Pool creates entry packet for all existing members
4. Packet shares = current member count
5. Each member can claim their random share

**Random Distribution Algorithm**:
```
For each claim:
  if last share:
    amount = remaining amount
  else:
    base = remaining / remaining_shares
    max = base * 2
    amount = random(1, max)
    amount = min(amount, remaining)
```

This ensures:
- Each share gets at least something
- Last person gets exact remainder
- Randomness adds excitement

#### Normal Packets
Users can create red packets anytime:
- **Whole Group**: All members eligible
- **Subgroup Only**: Only subgroup members eligible
- **Join Time Gate**: Only members who joined before packet creation can claim
- **Custom Token**: Any ERC20 token supported

#### Scheduled Packets
Owner sets up automated distribution:
```solidity
configureSchedule(
  token,           // Distribution token
  initialAmount,   // First round amount
  decayBps         // Decay rate (10-9900 = 0.1%-99%)
)
```

Example with 1000 tokens, 1% daily decay:
- Day 1: 1000 tokens
- Day 2: 990 tokens
- Day 3: 980.1 tokens
- ... continues for 365 days or until amount becomes 0

### Governance

#### Main Owner Election
**Requirements**:
- 6 months must pass since group creation
- 4 years cooldown after successful election
- Candidate must be a member
- 51% of members must vote yes

**Process**:
1. Any member calls `startMainElection(candidate)`
2. Members vote via `voteMainElection()`
3. Automatic finalization at 51% threshold
4. New owner takes effect immediately

**Use Cases**:
- Community-driven leadership changes
- Founder succession planning
- Response to inactive owners

#### Subgroup Owner Election
**Requirements**:
- Candidate must be subgroup member
- 75% of subgroup members must vote yes
- No cooldown period

**Process**:
1. Subgroup member calls `startSubElection(subgroupId, candidate)`
2. Subgroup members vote via `voteSubElection(subgroupId)`
3. Automatic finalization at 75% threshold

### Subgroup System

**Purpose**: Create specialized sub-communities within main group

**Features**:
- Independent ownership (can be different from main owner)
- Private red packets for subgroup only
- Separate mute permissions
- Fine system (subgroup violations)
- Entry fee split with main owner (50/50)

**Example Structure**:
```
Main Group (1000 members)
  ├── VIP Subgroup (50 members) - High rollers
  ├── Trading Subgroup (200 members) - Market discussion
  └── Gaming Subgroup (100 members) - Play-to-earn
```

### Messaging & Moderation

#### Message Rate Limiting
**Configuration** (per group):
- `NONE`: Unlimited messages
- `DAILY`: X messages per UTC day
- `WEEKLY`: X messages per week (Monday 00:00 UTC)

**Implementation**:
- Automatic period reset
- Per-user tracking
- Configurable limits

#### Mute System
**Global Mute** (Main owner or BIG_OWNER):
- Affects all groups and subgroups
- Set expiry timestamp
- User completely silenced until expiry

**Subgroup Mute** (Subgroup owner):
- Only affects specific subgroup
- Separate from global mute
- Combined check: max(global, subgroup) expiry

#### Fine System
**Purpose**: Economic penalty for subgroup violations

**Mechanism**:
1. Subgroup owner issues fine in USDT: `issueFine(subgroupId, user, amountUsdt)`
2. User cannot send subgroup messages until fine paid
3. User pays via: `payFine(subgroupId, amountUsdt)`
4. Payment goes directly to subgroup owner

**Use Cases**:
- Spam penalties
- Rule violation fines
- Coordinated FUD punishment

### Referral System

**Features**:
- Per-group referral tracking
- Automatic counting on join
- On-chain leaderboard with sorting
- Paginated queries

**Leaderboard Query**:
```solidity
getReferralLeaderboard(offset, limit)
// Returns: [{referrer: address, count: uint}]
// Sorted descending by referral count
```

**Incentives**:
- 21% of every entry fee
- Reputation building
- Community growth rewards

## Economic Model

### Entry Fee Distribution

```
User Pays: 100 tokens
├── 9%  → Owner(s)
│   ├── No Subgroup: 9% to main owner
│   └── With Subgroup: 4.5% main + 4.5% subgroup owner
├── 21% → Referrer (or platform if no referrer)
└── 70% → Entry Packet Pool
    └── Distributed to all existing members
```

### Token Flow Diagram

```
New Member (Entry Fee)
        ↓
   ┌────┴────┐
   │ Contract │
   └────┬────┘
        ├─→ 9% Owner Revenue
        ├─→ 21% Referrer Commission
        └─→ 70% Member Red Packets
              └─→ Existing members claim random shares
```

### Group Ranks

Groups earn titles based on member count:
- **Starting Group**: < 50 members
- **Squad Leader Group**: 50-99 members
- **Centurion Group**: 100-499 members
- **Regiment Leader Group**: 500-999 members
- **Thousand Commander Group**: 1,000-2,999 members
- **DAO Major General**: 3,000-4,999 members
- **DAO Lieutenant General**: 5,000-9,999 members
- **Core Leader**: 10,000+ members

Query via: `getMainRank()`

## Contract Details

### Technology Stack

- **Solidity**: ^0.8.28
- **License**: MIT
- **OpenZeppelin**: v5.x
  - ReentrancyGuard
  - SafeERC20
  - AccessControl
- **EIP-1167**: Minimal Proxy (Clones)

### Key Constants

```solidity
// Entry fee distribution (basis points)
BPS_OWNER = 900    // 9%
BPS_REF = 2100     // 21%
BPS_POOL = 7000    // 70%
BPS_DENOM = 10000  // 100%

// Governance thresholds
MAIN_THRESHOLD_BPS = 5100  // 51%
SUB_THRESHOLD_BPS = 7500   // 75%

// Time periods
WEEK = 7 days
SIX_MONTHS = 180 days
FOUR_YEARS = 1460 days
DAY = 24 hours

// Message limit
MAX_MESSAGE_BYTES = 280
```

### Storage Efficiency

**Member Storage**:
```solidity
struct Member {
    bool exists;       // 1 byte
    uint64 joinAt;     // 8 bytes
    uint32 subgroupId; // 4 bytes
}                      // Total: 13 bytes (packed)
```

**Packet Storage**:
```solidity
struct Packet {
    PacketKind kind;
    address token;
    uint64 createdAt;
    uint32 targetSubgroupId;
    uint32 sharesTotal;
    uint256 totalAmount;
    uint256 remainingAmount;
    uint32 remainingShares;
}
```

## Usage Guide

### Deployment

#### Step 1: Deploy Core Contracts

```solidity
// 1. Deploy UniChatRegistry
UniChatRegistry registry = new UniChatRegistry(
    unichatToken,  // UNICHAT token address
    usdtToken,     // USDT token address
    bigOwner,      // BIG_OWNER address
    owner,         // OWNER address
    treasury       // Platform treasury
);

// 2. Deploy RedPacketGroup implementation
RedPacketGroup implementation = new RedPacketGroup();

// 3. Deploy GroupFactory
GroupFactory factory = new GroupFactory(
    address(registry),
    address(implementation)
);

// 4. Configure registry
registry.setGroupFactory(address(factory));
```

#### Step 2: Whitelist Tokens

```solidity
// Apply for token listing (anyone can do this)
unichat.approve(address(registry), 20000e18);
registry.applyTokenListing(
    myToken,      // Token to list
    referralCode  // Optional: referral code for commission
);

// Or owner directly approves (no fee)
registry.approveTokenListing(myToken, true);
```

#### Step 3: Create Group

```solidity
// Ensure token is whitelisted
require(registry.allowedGroupTokens(groupToken));

// Create group
address group = factory.createGroup(
    groupToken,    // Token for entry fee
    100e18,        // Entry fee: 100 tokens
    "Web3 DAO",    // Group name
    "1. Be respectful\n2. No spam\n3. DYOR"  // Group rules
);
```

### User Interactions

#### Joining a Group

```solidity
// 1. Check if eligible (have token)
uint256 balance = IERC20(groupToken).balanceOf(myAddress);
require(balance > 0, "Need group token");

// 2. Approve entry fee
IERC20(entryToken).approve(groupAddress, entryFee);

// 3. Join (main group)
RedPacketGroup(groupAddress).join(
    0,            // subgroupId (0 = main group)
    referralCode  // Optional: referral code
);

// Or join specific subgroup
RedPacketGroup(groupAddress).join(
    1,            // subgroupId
    referralCode
);
```

#### Creating Red Packets

**Normal Packet for All Members**:
```solidity
// 1. Approve tokens
IERC20(token).approve(groupAddress, amount);

// 2. Create packet
uint256 packetId = group.createNormalPacketAll(
    token,      // Any ERC20 token
    1000e18,    // 1000 tokens
    "Good luck and prosperity! 🧧"
);
```

**Normal Packet for Subgroup**:
```solidity
uint256 packetId = group.createNormalPacketSubgroup(
    token,
    500e18,
    subgroupId,
    "VIP members only! 💎"
);
```

**Scheduled Packet** (Owner only):
```solidity
// Configure
group.configureSchedule(
    token,
    1000e18,   // Initial: 1000 tokens
    100        // Decay: 1% (100 bps)
);

// Anyone can trigger daily
group.tickSchedule();
```

#### Claiming Red Packets

```solidity
// Check if eligible
(bool exists, uint64 joinAt, uint32 subgroupId) = group.getMember(myAddress);
require(exists && joinAt <= packet.createdAt, "Not eligible");

// Claim
group.claimPacket(packetId);

// Query claim amount
uint256 amount = group.getPacketClaimDetail(packetId, myAddress);
```

#### Sending Messages

```solidity
// Main group message
group.sendMainMessage("Hello everyone!");

// Subgroup message
group.sendSubMessage(subgroupId, "VIP chat here");

// Query messages
(Message[] memory messages, uint256 count) = group.getMainMessages(
    0,    // offset
    100   // limit
);
```

### Admin Operations

#### Subgroup Management

```solidity
// Create subgroup
uint32 subgroupId = group.createSubgroup(subgroupOwner);

// Update subgroup owner
group.setSubgroupOwner(subgroupId, newOwner);
```

#### Moderation

```solidity
// Global mute (main owner or BIG_OWNER)
group.setGlobalMute(
    userAddress,
    block.timestamp + 7 days
);

// Subgroup mute (subgroup owner)
group.setSubgroupMute(
    subgroupId,
    userAddress,
    block.timestamp + 1 days
);

// Issue fine (subgroup owner)
group.issueFine(
    subgroupId,
    userAddress,
    100e6  // 100 USDT
);
```

#### Configuration

```solidity
// Set message limit
group.setMainMessageLimit(
    MessageLimitType.WEEKLY,  // Type: NONE, DAILY, WEEKLY
    5                         // Max 5 messages per week
);

// Update group settings
group.setGroupSettings(
    "New Group Name",
    "Economic model explanation",
    "Updated rules",
    "Important announcement",
    150e18  // New entry fee
);
```

### Governance

#### Starting Elections

```solidity
// Main owner election
group.startMainElection(candidateAddress);

// Check if allowed
uint64 nextAllowed = group.nextMainElectionAllowedAt();
require(block.timestamp >= nextAllowed, "Too early");

// Subgroup owner election
group.startSubElection(subgroupId, candidateAddress);
```

#### Voting

```solidity
// Vote in main election
group.voteMainElection();

// Vote in subgroup election
group.voteSubElection(subgroupId);

// Check election status
bool active = group.mainElectionActive();
uint32 votes = group.mainElectionYesVotes();
uint32 threshold = group.mainElectionSnapshotMembers();
// Passes at: votes >= (threshold * 5100 / 10000)
```

## Function Reference

### Group Creation & Initialization

#### `initialize()`
```solidity
function initialize(
    address registry_,
    address mainOwner_,
    address groupToken_,
    uint256 entryFee_,
    string calldata groupName_,
    string calldata groupRules_
) external
```
Initialize cloned group instance. Called by factory.

### Membership

#### `join()`
```solidity
function join(
    uint32 subgroupId,
    bytes32 referralCode
) external nonReentrant
```
Join group by paying entry fee.

**Requirements**:
- Not already a member
- Hold group token or pass validator check
- Approved entry fee amount

### Red Packets

#### `createNormalPacketAll()`
```solidity
function createNormalPacketAll(
    address token,
    uint256 amount,
    string calldata message
) external nonReentrant onlyMember returns (uint256 packetId)
```

#### `createNormalPacketSubgroup()`
```solidity
function createNormalPacketSubgroup(
    address token,
    uint256 amount,
    uint32 subgroupId,
    string calldata message
) external nonReentrant onlyMember returns (uint256 packetId)
```

#### `claimPacket()`
```solidity
function claimPacket(
    uint256 packetId
) external nonReentrant onlyMember
```

#### `configureSchedule()`
```solidity
function configureSchedule(
    address token,
    uint256 initialAmount,
    uint16 decayBps
) external onlyMainOwner
```

#### `tickSchedule()`
```solidity
function tickSchedule()
    external
    nonReentrant
    returns (uint256 packetId)
```
Anyone can call to trigger next scheduled distribution.

### Messaging

#### `sendMainMessage()`
```solidity
function sendMainMessage(
    string calldata content
) external onlyMember
```

#### `sendSubMessage()`
```solidity
function sendSubMessage(
    uint32 subgroupId,
    string calldata content
) external onlyMember
```

### Governance

#### `startMainElection()`
```solidity
function startMainElection(
    address candidate
) external onlyMember
```

#### `voteMainElection()`
```solidity
function voteMainElection() external onlyMember
```

#### `startSubElection()`
```solidity
function startSubElection(
    uint32 subgroupId,
    address candidate
) external onlyMember
```

#### `voteSubElection()`
```solidity
function voteSubElection(
    uint32 subgroupId
) external onlyMember
```

### View Functions

#### `getMember()`
```solidity
function getMember(
    address addr
) external view returns (
    bool exists,
    uint64 joinAt,
    uint32 subgroupId
)
```

#### `getMembers()`
```solidity
function getMembers(
    uint256 offset,
    uint256 limit
) external view returns (
    address[] memory members_,
    uint256 count
)
```

#### `getPacket()`
```solidity
function getPacket(
    uint256 packetId
) external view returns (
    PacketKind kind,
    address token,
    uint64 packetCreatedAt,
    uint32 targetSubgroupId,
    uint32 sharesTotal,
    uint256 totalAmount,
    uint256 remainingAmount,
    uint32 remainingShares
)
```

#### `getPacketClaimDetails()`
```solidity
function getPacketClaimDetails(
    uint256 packetId,
    uint256 offset,
    uint256 limit
) external view returns (
    ClaimDetail[] memory details,
    uint256 count
)
```

#### `getMainMessages()`
```solidity
function getMainMessages(
    uint256 offset,
    uint256 limit
) external view returns (
    Message[] memory messages,
    uint256 count
)
```

#### `getReferralLeaderboard()`
```solidity
function getReferralLeaderboard(
    uint256 offset,
    uint256 limit
) external view returns (
    ReferralRank[] memory ranks,
    uint256 count
)
```

## Events Reference

### Group Management

```solidity
event Initialized(
    address indexed registry,
    address indexed mainOwner,
    address indexed groupToken,
    address entryToken,
    uint256 entryFee
);

event Joined(
    address indexed user,
    uint32 indexed subgroupId,
    bytes32 indexed referralCode,
    uint256 feePaid
);

event EntrySplit(
    uint256 ownerAmount,
    uint256 refAmount,
    uint256 poolAmount,
    address refRecipient,
    address ownerRecipientA,
    address ownerRecipientB
);
```

### Red Packets

```solidity
event PacketCreated(
    uint256 indexed packetId,
    PacketKind kind,
    address indexed token,
    uint32 indexed targetSubgroupId,
    uint32 shares,
    uint256 amount
);

event Claimed(
    uint256 indexed packetId,
    address indexed user,
    uint256 amount
);

event ScheduleTick(
    uint256 indexed packetId,
    uint256 amount,
    uint32 shares,
    uint32 remainingRounds,
    uint256 nextAmount,
    uint64 nextTime
);
```

### Governance

```solidity
event MainElectionStarted(
    uint256 indexed electionId,
    address indexed candidate,
    uint32 snapshotMembers
);

event MainElectionVoted(
    uint256 indexed electionId,
    address indexed voter
);

event MainOwnerChangedByVote(
    address indexed newOwner
);
```

### Moderation

```solidity
event GlobalMute(
    address indexed user,
    uint64 untilTs
);

event FineIssued(
    uint32 indexed subgroupId,
    address indexed user,
    uint256 amountUsdt
);

event FinePaid(
    uint32 indexed subgroupId,
    address indexed user,
    uint256 amountUsdt,
    uint256 remainingDue
);
```

## Security

### Implemented Protections

#### Reentrancy Protection
All functions with external calls use `nonReentrant` modifier:
- `join()` - Token transfers and packet creation
- `createNormalPacket*()` - Token deposits
- `claimPacket()` - Token payouts
- `payFine()` - USDT payments
- `tickSchedule()` - Scheduled distributions

#### Access Control
- **Main Owner**: Group creator, configurable via election
- **Subgroup Owner**: Per-subgroup owner, independent permissions
- **BIG_OWNER**: Platform admin, emergency controls
- **Members Only**: Must join to interact

#### Input Validation
Every function validates:
- Zero addresses
- Zero amounts
- Array bounds
- Timestamp validity
- State consistency

#### Custom Errors
Gas-efficient error handling (vs require strings):
```solidity
error NotMainOwner();
error NotMember();
error AlreadyMember();
error PacketEmpty();
error AlreadyClaimed();
// ... 30+ custom errors
```

### Potential Risks

#### Economic Risks

1. **Entry Fee Volatility**
   - Token price fluctuation affects real entry cost
   - Mitigation: Owner can adjust `entryFeeAmount`

2. **Red Packet Gaming**
   - Early claimers get better randomness
   - Mitigation: `joinAt` barrier, predictable randomness

3. **Scheduled Packet Depletion**
   - Decay too aggressive → runs out early
   - Mitigation: Conservative decay rates, monitoring

#### Governance Risks

1. **Vote Manipulation**
   - Sybil attack: create multiple accounts
   - Mitigation: Entry fee barrier, token gating

2. **Low Participation**
   - Elections may not reach threshold
   - Mitigation: 51% is achievable, time limits

3. **Owner Abandonment**
   - Main owner becomes inactive
   - Mitigation: BIG_OWNER can appoint new owner

### Best Practices

**For Group Owners**:
- Set reasonable entry fees
- Monitor scheduled packets
- Active moderation
- Clear group rules
- Regular governance participation

**For Members**:
- Verify group legitimacy
- Understand economic model
- Participate in governance
- Report violations
- Check packet eligibility before claiming

**For Platform**:
- Audit token listings
- Monitor for scams
- Provide education
- Emergency response via BIG_OWNER

## Development

### Testing

Comprehensive test coverage recommended:

```javascript
describe("RedPacketGroup", () => {
  describe("Initialization", () => {
    it("Should initialize correctly")
    it("Should prevent double initialization")
  })
  
  describe("Membership", () => {
    it("Should allow joining with token")
    it("Should prevent joining without token")
    it("Should distribute entry fee correctly")
  })
  
  describe("Red Packets", () => {
    it("Should create entry packet on join")
    it("Should create normal packet")
    it("Should distribute randomly")
    it("Should respect join time gate")
  })
  
  describe("Governance", () => {
    it("Should start election after cooldown")
    it("Should count votes correctly")
    it("Should finalize at threshold")
  })
  
  describe("Security", () => {
    it("Should prevent reentrancy")
    it("Should validate inputs")
    it("Should respect access control")
  })
})
```

### Integration

**With Frontend**:
```javascript
// Listen to events
group.on("Joined", (user, subgroupId, referralCode, fee) => {
  console.log(`${user} joined with fee ${fee}`);
});

// Query state
const members = await group.getMembers(0, 100);
const messages = await group.getMainMessages(0, 50);
const packet = await group.getPacket(packetId);

// User actions
await token.approve(group.address, entryFee);
await group.join(0, referralCode);
await group.claimPacket(packetId);
```

**With Backend**:
- Index events for fast queries
- Cache member lists
- Monitor scheduled packets
- Alert on governance events
- Track referral stats

### Deployment Checklist

- [ ] Deploy Registry with correct token addresses
- [ ] Deploy RedPacketGroup implementation
- [ ] Deploy GroupFactory
- [ ] Configure Registry with Factory address
- [ ] Set platform treasury
- [ ] Whitelist initial tokens
- [ ] Create test group
- [ ] Verify all contracts on block explorer
- [ ] Test all user flows
- [ ] Set up monitoring

## Future Enhancements

This is part of the evolving UniChat contract ecosystem. Planned enhancements:

### Short Term
- NFT-gated groups
- Multi-token entry fees
- Advanced packet algorithms
- Reputation system integration

### Medium Term
- Cross-group interactions
- Composable governance modules
- Layer 2 deployment
- Mobile-optimized flows

### Long Term
- DAO treasury management
- Automated market makers for group tokens
- Cross-chain group portability
- AI-powered moderation

## Contributing

We welcome contributions! Areas where you can help:

- **Testing**: Write comprehensive test cases
- **Documentation**: Improve examples and guides
- **Optimization**: Gas optimization suggestions
- **Security**: Audit and report vulnerabilities
- **Integration**: Build tools and interfaces

### Contribution Process

1. Fork the repository
2. Create feature branch
3. Write tests for new features
4. Ensure all tests pass
5. Submit pull request with clear description

## License

MIT License - see [LICENSE](LICENSE) file for details.

Copyright (c) 2024 UniChat

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## Support

- **Documentation**: Check this README and inline code comments
- **Issues**: Report bugs via GitHub Issues
- **Community**: Join our Discord/Telegram
- **Email**: security@unichat.io (for security issues only)

## Disclaimer

⚠️ **IMPORTANT**: These smart contracts are provided as-is. While designed with security in mind:

- Always audit before deploying to mainnet
- Test thoroughly on testnets
- Understand the economic implications
- Use at your own risk
- No warranties or guarantees provided

The authors and contributors are not responsible for any losses incurred through the use of this software.

---

**Last Updated**: 2024  
**Version**: 1.0.0  
**Network Compatibility**: Ethereum, Polygon, BSC, Base, Arbitrum, Optimism (EVM-compatible chains)
