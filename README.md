<div align="right">
  <a href="./README.md"><strong>English</strong></a> ·
  <a href="./README.zh-CN.md">简体中文</a>
</div>

<h1 align="center">UniChat Smart Contracts</h1>

<p align="center">
  A comprehensive suite of blockchain-based communication and community management contracts for building decentralized social platforms.
</p>

<p align="center">
  <a href="./README.md">
    <img alt="Language: English" src="https://img.shields.io/badge/Language-English-blue">
  </a>
  <a href="./README.zh-CN.md">
    <img alt="语言：简体中文" src="https://img.shields.io/badge/%E8%AF%AD%E8%A8%80-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-red">
  </a>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Contract Modules](#contract-modules)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Core Features](#core-features)
- [Quick Start](#quick-start)
- [Deployment Guide](#deployment-guide)
- [Use Case Examples](#use-case-examples)
- [Security](#security)
- [Contributing](#contributing)

## Overview

UniChat is a modular smart contract ecosystem designed for Web3 social applications. It provides the building blocks for token-gated communities, on-chain messaging, economic incentive systems, and decentralized governance.

### Design Philosophy

**Modularity**: Each contract module solves a specific problem and can be used independently or combined.

**Scalability**: Gas-efficient designs using Merkle Trees and minimal proxies to support thousands of users.

**Flexibility**: Configurable parameters allow customization for different use cases.

**Security**: Built on battle-tested OpenZeppelin libraries with comprehensive access controls.

### What Can You Build?

- **Token-Gated Communities**: Require users to hold specific tokens to join
- **DAO Communication Platforms**: On-chain messaging with governance integration
- **NFT Holder Communities**: Different access levels based on NFT holdings
- **Social Finance (SoFi) Apps**: Combine chat with token rewards and distributions
- **Decentralized Discord/Telegram**: Censorship-resistant group communication

## Contract Modules

### 🎁 RedPacketGroup
**Purpose**: Token-gated communities with economic models

Token-gated group management featuring entry fee distribution (9% owner, 21% referrer, 70% pool), subgroup hierarchies, red packet rewards, on-chain governance voting, and comprehensive moderation tools.

**Key Features**:
- Entry fee split (9% owner / 21% referrer / 70% red packets)
- Three red packet types (Entry, Normal, Scheduled)
- Democratic governance (51% main, 75% subgroup voting)
- Subgroup management with independent owners
- Rate limiting, muting, and fine system
- Referral tracking and leaderboards

**Ideal For**: Investment clubs, DAO communities, gaming guilds, subscription groups

**Documentation**: [contract/RedPacketGroup/README.md](./contract/RedPacketGroup/README.md)

---

### 📨 DirectMessage
**Purpose**: Private 1-to-1 encrypted messaging

On-chain peer-to-peer messaging contract storing conversation history permanently on the blockchain. Features RSA public key registry for end-to-end encryption, blacklist management, message statistics, and seamless red packet integration.

**Key Features**:
- On-chain message storage (max 1KB per message)
- RSA public key registry with default fallback
- Blacklist system (mutual block checks)
- Message statistics by time period
- Red packet integration (send tokens with messages)
- Conversation partner tracking

**Ideal For**: Decentralized messaging apps, negotiation platforms, verifiable communication

**Documentation**: [contract/DirectMessage/README.md](./contract/DirectMessage/README.md)

---

### 🏘️ MerkelGroup
**Purpose**: Scalable communities with Merkle Tree whitelists

Large-scale community management using Merkle Tree-based whitelist verification for gas efficiency. Supports thousands of members with tier-based access control, nested room structure, encrypted group messaging, and distributed key management.

**Key Features**:
- Merkle Tree whitelist (gas-efficient)
- Epoch-based membership updates
- Tier system (1-7 asset-based levels)
- Nested room architecture (large community → small rooms)
- RSA group key distribution
- Encrypted/plaintext messaging

**Ideal For**: NFT holder communities, tiered memberships, educational platforms, large DAOs

**Documentation**: [contract/MerkelGroup/README.md](./contract/MerkelGroup/README.md)

---

### 🧧 RedPacket
**Purpose**: Standalone token distribution system

Flexible red packet contract for personal and group token distributions. Features a recommendation-based token whitelist (stake UNICHAT to list tokens), configurable platform tax system, equal/random distribution algorithms, and chat contract integration.

**Key Features**:
- Personal red packets (1-to-1 transfers)
- Group red packets (equal or random distribution)
- Token whitelist via UNICHAT staking
- Configurable tax rates per token
- Expiry and refund mechanism
- Chat contract integration

**Ideal For**: Token airdrops, community rewards, marketing campaigns, gaming rewards

**Documentation**: [contract/RedPacket/README.md](./contract/RedPacket/README.md)

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────┐
│           UniChat Smart Contract Suite          │
└─────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ RedPacketGrp │ │ MerkleGroup  │ │DirectMessage │
│   Ecosystem  │ │   Ecosystem  │ │   Contract   │
└──────────────┘ └──────────────┘ └──────────────┘
        │               │               │
        ├─Registry      ├─Factory       └─RSA Keys
        ├─Factory       ├─Community         Blacklist
        └─Group         └─Room              Messages
                                            
                ┌──────────────┐
                │  RedPacket   │
                │  Contract    │
                └──────────────┘
                     (Shared)
```

### Integration Patterns

#### Pattern 1: Standalone Modules
```
DirectMessage (P2P Chat)
    ↓ optional
RedPacket (Token Gifts)
```
Simple peer-to-peer messaging with optional token transfers.

#### Pattern 2: Community + Red Packets
```
MerkleGroup Community
    ├─> Members (Merkle verified)
    ├─> Rooms (nested chats)
    └─> RedPacket (group rewards)
```
Large communities with rewards and nested discussions.

#### Pattern 3: Economic Group
```
RedPacketGroup
    ├─> Token Gating
    ├─> Entry Fees → Red Packets
    ├─> Governance Voting
    └─> Subgroups
```
Token-gated communities with built-in economics.

#### Pattern 4: Full Integration
```
MerkleGroup Community
    ├─> DirectMessage (P2P between members)
    ├─> RedPacket (airdrops)
    └─> Rooms
            ├─> Group RedPackets
            └─> Private discussions
```
Complete social platform with all features.

## Technology Stack

### Smart Contract Layer

- **Solidity**: ^0.8.24 - ^0.8.28
  - Modern language features
  - Custom errors for gas efficiency
  - Packed structs for storage optimization

- **OpenZeppelin Contracts**: v5.x
  - `Ownable`: Single-owner access control
  - `AccessControl`: Role-based permissions
  - `ReentrancyGuard`: Reentrancy protection
  - `Pausable`: Emergency pause functionality
  - `SafeERC20`: Safe token interactions
  - `MerkleProof`: Whitelist verification

### Design Patterns

- **EIP-1167 Minimal Proxy**: Gas-efficient cloning
  - Used in: GroupFactory, CommunityFactory
  - Savings: ~90% deployment gas
  
- **Factory Pattern**: Standardized contract creation
  - Predictable addresses
  - Consistent initialization
  - Registry integration

- **Merkle Tree Verification**: Scalable whitelists
  - O(log n) verification gas
  - Single root storage
  - Privacy-preserving

### Storage Optimization

**Packed Structs**:
```solidity
struct Member {
    bool exists;        // 1 byte
    uint64 joinAt;      // 8 bytes  
    uint32 subgroupId;  // 4 bytes
}                       // Total: 13 bytes (one slot)
```

**Dynamic Arrays with Pagination**:
- Prevent unbounded loops
- Gas-efficient queries
- Frontend-friendly

**Mapping-Based Storage**:
- O(1) lookups
- No iteration needed
- Minimal gas cost

## Core Features

### Communication

#### On-Chain Messaging
- **Permanent Storage**: Messages stored forever on blockchain
- **Pagination**: Efficient retrieval of large conversation histories
- **Content Types**: Plaintext and encrypted messages
- **Size Limits**: 280-2048 bytes depending on contract
- **Metadata**: IPFS CID references for rich content

#### Encryption Support
- **RSA Public Keys**: On-chain key registry
- **Client-Side Encryption**: Privacy-preserving
- **Key Rotation**: Update keys without losing history
- **Group Keys**: Distributed via Merkle Trees

#### Moderation Tools
- **Blacklists**: User-controlled blocking
- **Rate Limiting**: Prevent spam (daily/weekly limits)
- **Muting**: Temporary silencing by admins
- **Fines**: Economic penalties (in USDT)
- **Kick/Ban**: Remove disruptive members

### Token Economics

#### Entry Fees
```
New Member Payment: 100 tokens
├─> 9% → Group Owner(s)
├─> 21% → Referrer (or platform)
└─> 70% → Red Packet Pool
    └─> Distributed to existing members
```

#### Red Packets
1. **Entry Packets**: Auto-created on join (70% of entry fee)
2. **Normal Packets**: User-created, any token, any amount
3. **Scheduled Packets**: Daily automated distribution (365 days)

#### Distribution Algorithms
- **Random**: Pre-allocated amounts with excitement factor
- **Equal**: Fair distribution to all claimers
- **Sequential**: First-come-first-served claiming

#### Token Whitelist
- **Core Tokens**: Platform-approved (USDT, WETH, etc.)
- **Community Tokens**: Added via UNICHAT staking
- **Tax System**: Configurable platform fee per token

### Access Control

#### Token Gating
- **Balance Check**: Must hold group token
- **Validator Contract**: Custom eligibility logic
- **Minimum Holdings**: Configurable thresholds
- **Multi-Token Support**: Different tokens per group

#### Merkle Tree Whitelists
- **Gas Efficient**: Single root verification
- **Privacy**: No exposed member list
- **Updatable**: Epoch-based refresh
- **Tiered Access**: 1-7 membership levels

#### Governance
- **Main Elections**: 51% member vote required
- **Subgroup Elections**: 75% vote threshold  
- **Cooldown Periods**: 6 months / 4 years
- **Immediate Finalization**: Auto-execute on threshold

### Hierarchy & Organization

#### RedPacketGroup Structure
```
Main Group (unlimited members)
├─> Subgroup 1 (subset of members)
├─> Subgroup 2 (subset of members)
└─> Subgroup N (subset of members)

Entry Fee Split:
- Main only: 9% main owner
- With subgroup: 4.5% main + 4.5% subgroup
```

#### MerkleGroup Structure
```
Community (10,000+ members)
├─> Room 1 (10-50 members)
├─> Room 2 (10-50 members)
└─> Room N (10-50 members)

Access: Community membership → Room invites
```

## Quick Start

### Prerequisites

```bash
# Install Node.js and pnpm
node --version  # v18+
pnpm --version  # v8+

# Install Hardhat or Foundry
pnpm add --save-dev hardhat
# or
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```bash
# Clone repository
git clone <repository-url>
cd unichat

# Install dependencies
pnpm install

# Compile contracts
pnpm hardhat compile
# or
forge build
```

### Run Tests

```bash
# Hardhat
pnpm hardhat test

# Foundry
forge test
```

### Deploy Contracts

```bash
# Configure network in hardhat.config.js
# Add private key to .env

# Deploy to testnet
pnpm hardhat run scripts/deploy.js --network sepolia

# Verify on Etherscan
pnpm hardhat verify --network sepolia <CONTRACT_ADDRESS>
```

## Deployment Guide

### 1. RedPacketGroup Deployment

```solidity
// Step 1: Deploy Registry
UniChatRegistry registry = new UniChatRegistry(
    unichatToken,
    usdtToken,
    bigOwner,
    platformOwner,
    treasury
);

// Step 2: Deploy Group Implementation
RedPacketGroup implementation = new RedPacketGroup();

// Step 3: Deploy Factory
GroupFactory factory = new GroupFactory(
    address(registry),
    address(implementation)
);

// Step 4: Configure Registry
registry.setGroupFactory(address(factory));

// Step 5: Whitelist Tokens
registry.approveTokenListing(myToken, true);

// Step 6: Create Group
address group = factory.createGroup(
    myToken,
    100e18,
    "My Community",
    "Be respectful"
);
```

### 2. MerkleGroup Deployment

```solidity
// Step 1: Deploy Implementations
Community communityImpl = new Community();
Room roomImpl = new Room();

// Step 2: Deploy Factory
CommunityFactory factory = new CommunityFactory(
    unichatToken,
    treasury,
    50e18,  // Room creation fee
    address(communityImpl),
    address(roomImpl)
);

// Step 3: Create Community
address community = factory.createCommunity(
    ownerAddr,
    topicToken,
    7,  // maxTier
    "NFT Holders",
    "QmAvatar..."
);

// Step 4: Set Merkle Root
Community(community).setMerkleRoot(root, "ipfs://...");
```

### 3. RedPacket Deployment

```solidity
// Deploy RedPacket Contract
UniChatRedPacket redPacket = new UniChatRedPacket(
    unichatToken,
    treasury,
    360000,      // 100 hours default expiry
    10000e18     // 10k UNICHAT stake amount
);

// Configure Core Tokens
redPacket.setCoreToken(usdtAddr, true, "QmUSDT...");
redPacket.setCoreToken(wethAddr, true, "QmWETH...");

// Set Tax Rates
redPacket.setDefaultTaxRate(usdtAddr, 100);  // 1%
redPacket.setDefaultTaxRate(wethAddr, 50);   // 0.5%

// Whitelist Chat Contracts
redPacket.setChatContract(directMessageAddr, true);
redPacket.setChatContract(communityAddr, true);
```

### 4. DirectMessage Deployment

```solidity
// Deploy with default RSA key
DirectMessage dm = new DirectMessage(
    platformOwner,
    defaultRSAPublicKey
);

// Link to RedPacket
dm.setRedPacket(address(redPacket));
```

## Use Case Examples

### Example 1: Investment DAO

```
Components: RedPacketGroup + RedPacket

Setup:
- Group Token: DAO governance token
- Entry Fee: 1000 DAO tokens
- Subgroups: VIP (high holders), Research, Trading

Features:
- Entry fees create immediate rewards for existing members
- Subgroup fines for violating trading rules  
- Scheduled daily rewards from treasury
- Governance voting for treasury management
```

### Example 2: NFT Community

```
Components: MerkleGroup + RedPacket

Setup:
- Topic Token: NFT collection address
- Tiers: 1-5 based on NFT holdings
- Rooms: Different NFT rarity discussions

Features:
- Merkle whitelist (only NFT holders)
- Tier-based room access
- Red packet airdrops to holders
- Encrypted discussion rooms
```

### Example 3: P2P Marketplace

```
Components: DirectMessage + RedPacket

Setup:
- User A lists item
- User B negotiates via DirectMessage
- Payment via personal red packet
- Transaction proof on-chain

Features:
- Permanent negotiation records
- Integrated payment
- Dispute resolution via message history
```

### Example 4: Gaming Guild

```
Components: RedPacketGroup + MerkleGroup

Setup:
- RedPacketGroup: Main guild (entry fees)
- MerkleGroup Communities: Per-game groups
- Subgroups: Teams/squads

Features:
- Entry fees fund prize pools
- Game-specific rooms
- Random red packet tournaments
- Performance-based tier upgrades
```

## Security

### Audit Status

⚠️ **Pre-Audit**: These contracts have not been audited. Use at your own risk.

**Recommended Steps Before Mainnet**:
1. Professional security audit
2. Extensive testnet deployment
3. Bug bounty program
4. Gradual rollout with limits

### Security Features

#### Access Control
- **Role-Based**: OWNER, BIG_OWNER, member roles
- **Modifiers**: `onlyOwner`, `onlyMember`, etc.
- **Checks**: Zero address, amount validations

#### Reentrancy Protection
- **nonReentrant**: All external token interactions
- **Checks-Effects-Interactions**: Pattern followed
- **State Updates First**: Before external calls

#### Input Validation
- **Address Checks**: No zero addresses
- **Amount Checks**: No zero amounts (where applicable)
- **Array Bounds**: Pagination limits
- **Status Checks**: Packet status, membership status

#### Emergency Controls
- **Pausable**: Owner can pause in emergency
- **BIG_OWNER**: Platform admin override powers
- **Withdrawal**: Owner emergency withdrawal function

### Common Vulnerabilities Addressed

✅ **Reentrancy**: ReentrancyGuard on all token transfers  
✅ **Integer Overflow**: Solidity 0.8+ built-in checks  
✅ **Access Control**: Comprehensive role checks  
✅ **Front-Running**: Accept as blockchain nature  
✅ **Denial of Service**: Pagination prevents unbounded loops  

### Best Practices for Users

**Group Owners**:
- Set reasonable entry fees
- Monitor scheduled packets
- Active moderation
- Clear group rules

**Members**:
- Verify group legitimacy
- Understand economic model
- Secure your private keys
- Report suspicious activity

**Developers**:
- Thorough testing on testnets
- Monitor for vulnerabilities
- Keep dependencies updated
- Follow upgrade procedures

## Contributing

We welcome contributions! Here's how you can help:

### Areas for Contribution

- **Testing**: Write comprehensive test suites
- **Documentation**: Improve guides and examples
- **Optimization**: Gas optimization suggestions
- **Security**: Report vulnerabilities
- **Features**: Propose and implement new features

### Contribution Process

1. **Fork Repository**: Create your fork on GitHub
2. **Create Branch**: `git checkout -b feature/amazing-feature`
3. **Write Tests**: Ensure 100% coverage for new code
4. **Follow Style**: Match existing code style
5. **Commit**: Use conventional commits (feat/fix/docs)
6. **Test**: Run full test suite
7. **Pull Request**: Submit with clear description

### Code Style

```solidity
// Good
function createPacket(
    address token,
    uint256 amount
) external nonReentrant returns (uint256 packetId) {
    require(amount > 0, "ZeroAmount");
    // ...
}

// Use custom errors
error ZeroAmount();
function createPacket(...) external {
    if (amount == 0) revert ZeroAmount();
}
```

### Testing Standards

- Unit tests for all functions
- Integration tests for multi-contract flows
- Edge case coverage
- Gas optimization tests
- Security-focused tests

## License

MIT License - See individual contract files for details.

Copyright (c) 2024 UniChat

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.

## Links & Resources

- **Documentation**: See individual contract READMEs
- **GitHub**: <repository-url>
- **Website**: <project-website>
- **Discord**: <discord-invite>
- **Twitter**: <twitter-handle>

## Roadmap

### Phase 1: Core Contracts ✅
- [x] RedPacketGroup system
- [x] MerkleGroup system
- [x] RedPacket contract
- [x] DirectMessage contract

### Phase 2: Enhancements (Q2 2024)
- [ ] NFT-gated groups
- [ ] Multi-token entry fees
- [ ] Advanced governance modules
- [ ] Reputation system

### Phase 3: Scaling (Q3 2024)
- [ ] Layer 2 deployment (Arbitrum, Optimism)
- [ ] Cross-chain messaging
- [ ] Mobile-optimized flows
- [ ] Gasless transactions (meta-transactions)

### Phase 4: Ecosystem (Q4 2024)
- [ ] DAO treasury management
- [ ] Automated market makers
- [ ] AI-powered moderation
- [ ] Analytics dashboard

## Support

- **Issues**: Report bugs on GitHub Issues
- **Security**: security@unichat.io (for vulnerabilities)
- **Documentation**: This README and contract docs
- **Community**: Join our Discord

---

**Built with ❤️ for Web3 Social**

**Version**: 1.0.0  
**Last Updated**: 2024  
**Network Compatibility**: All EVM-compatible chains
