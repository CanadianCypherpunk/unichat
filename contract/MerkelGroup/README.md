# Merkle Group Contracts

Scalable community management system using Merkle Tree whitelists with hierarchical room structure for the UniChat ecosystem.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
- [Community Contract](#community-contract)
- [Room Contract](#room-contract)
- [CommunityFactory Contract](#communityfactory-contract)
- [Usage Guide](#usage-guide)
- [Function Reference](#function-reference)
- [Security](#security)
- [Integration Examples](#integration-examples)

## Overview

The Merkle Group system provides gas-efficient, large-scale community management through Merkle Tree-based membership verification. It supports thousands of members while keeping verification costs low by storing only a single Merkle Root on-chain.

### What Problem Does It Solve?

- **Scalability**: Support 10,000+ members without excessive gas costs
- **Privacy**: Don't expose entire member list on-chain
- **Flexibility**: Update membership via epoch changes
- **Hierarchy**: Large communities with smaller nested rooms
- **Token Gating**: Tier-based access control via topic tokens

### Use Cases

- NFT holder communities (different tiers by holdings)
- Token holder DAOs (voting weight tiers)
- Subscription-based groups (membership levels)
- Educational platforms (course access tiers)
- Gaming guilds (rank-based access)

## Architecture

### Three-Contract System

```
CommunityFactory (Singleton)
       ↓ creates
Community (Many instances)
       ↓ contains
Room (Many per community)
```

### Data Flow

```
Off-Chain:
1. Generate member list with tiers
2. Build Merkle Tree
3. Store tree data on IPFS
4. Deploy tree root on-chain

On-Chain:
1. User submits Merkle Proof
2. Contract verifies proof against root
3. User granted membership
4. Can join rooms, send messages, etc.
```

### Storage Efficiency

**Traditional Approach**:
- Store all member addresses on-chain
- 10,000 members = 10,000 storage slots
- ~200M gas to update member list

**Merkle Approach**:
- Store single root hash (32 bytes)
- 10,000 members = 1 storage slot
- ~5,000 gas to update root

**Savings**: ~40,000x reduction in gas costs!

## Key Concepts

### Merkle Tree Whitelist

**What is it?**
A binary tree where each leaf is a hash of member data, and each parent node is a hash of its children.

**Structure**:
```
                Root (stored on-chain)
               /     \
           Hash1      Hash2
          /    \     /    \
       Hash3  Hash4 Hash5  Hash6
       /  \   /  \   /  \   /  \
      L1  L2 L3  L4 L5  L6 L7  L8
      
L1 = keccak256(community, epoch, alice, tier1, validUntil, nonce)
L2 = keccak256(community, epoch, bob, tier2, validUntil, nonce)
...
```

**Verification**:
User provides:
- Their leaf data (address, tier, etc.)
- Merkle proof (sibling hashes to reach root)

Contract computes path and verifies it reaches the stored root.

### Epoch System

**Purpose**: Version control for membership updates

**How it works**:
1. Owner creates new Merkle Tree with updated members
2. Owner calls `setMerkleRoot(newRoot, "ipfs://...")`
3. `currentEpoch` increments
4. All members must rejoin with new proofs

**Benefits**:
- Clean membership updates
- Removes inactive members
- Adds new members
- Updates member tiers

**Example Timeline**:
```
Epoch 1: 100 members (Jan-Mar)
Epoch 2: 150 members (Apr-Jun) - added 50 new
Epoch 3: 120 members (Jul-Sep) - removed 30 inactive
```

### Tier System

**Purpose**: Classify members by asset holdings, reputation, or access level

**Tiers**: 1-7 (configurable per community)
- Tier 1: Entry level
- Tier 2-6: Progressive levels
- Tier 7: Maximum tier

**Usage**:
- Room access restrictions
- Voting weight
- Fee discounts
- Feature unlocks

**Example for NFT Community**:
- Tier 1: Hold 1-5 NFTs
- Tier 2: Hold 6-10 NFTs
- Tier 3: Hold 11-20 NFTs
- Tier 4: Hold 21-50 NFTs
- Tier 5: Hold 51-100 NFTs
- Tier 6: Hold 101-500 NFTs
- Tier 7: Hold 500+ NFTs

### Topic Token

**Purpose**: Unique identifier for community type

**Characteristics**:
- ERC20 token address
- Represents community theme (NFT collection, governance token, etc.)
- Combined with `maxTier` to form unique key

**Uniqueness Constraint**:
```solidity
// Only ONE community can exist per (topicToken, maxTier)
bytes32 key = keccak256(topicToken, maxTier);
```

**Examples**:
- BAYC NFT → Tier 7 community
- PUNK NFT → Tier 7 community
- USDC → Tier 5 stablecoin holders

## Community Contract

### Features

#### Merkle-Based Membership
- Gas-efficient verification
- Proof-based joining
- Epoch versioning
- Nonce replay protection

#### Built-in Messaging
- Two types: Plaintext & Encrypted
- On-chain storage
- Pagination support
- Per-message CID references

#### RSA Group Key Management
- Owner sets group public key
- Version control via `groupKeyEpoch`
- Key distribution via Merkle Tree + IPFS
- Members verify their encrypted keys

#### Room Management
- Create nested rooms
- EIP-1167 minimal proxy
- Configurable default parameters
- Fee-based creation

#### Red Packet Integration
- Create group red packets
- Integrated with message sending
- One-transaction flow

### Membership Lifecycle

#### 1. Off-Chain Preparation

```javascript
// Backend generates Merkle Tree
const leaves = members.map(m => 
    keccak256(
        community.address,
        currentEpoch,
        m.address,
        m.tier,
        m.validUntil,
        m.nonce
    )
);

const tree = new MerkleTree(leaves);
const root = tree.getRoot();

// Store tree data on IPFS
const ipfsData = {
    members: members.map(m => ({
        address: m.address,
        tier: m.tier,
        proof: tree.getProof(m.leaf)
    })),
    epoch: currentEpoch,
    root: root
};

const cid = await ipfs.add(JSON.stringify(ipfsData));
```

#### 2. On-Chain Root Update

```solidity
// Owner updates root
community.setMerkleRoot(
    root,
    `ipfs://${cid}`
);
// Increments currentEpoch
```

#### 3. User Joins

```solidity
// User fetches their proof from IPFS
const userData = await ipfs.get(cid);
const myData = userData.members.find(m => m.address === myAddress);

// Submit proof on-chain
await community.joinCommunity(
    myData.tier,
    currentEpoch,
    myData.validUntil,
    myData.nonce,
    myData.proof
);
```

### Messaging

#### Send Message

```solidity
// Plaintext message (if enabled)
community.sendCommunityMessage(
    0,                    // kind: 0 = plaintext
    "Hello everyone!",    // content
    ""                    // cid (optional)
);

// Encrypted message
community.sendCommunityMessage(
    1,                    // kind: 1 = encrypted
    encryptedContent,     // encrypted by frontend
    "QmEncryptedData..."  // IPFS CID (optional)
);
```

#### Query Messages

```solidity
// Get total message count
uint256 count = community.communityMessageCount();

// Get messages (paginated)
Message[] memory messages = community.getCommunityMessages(
    0,      // start index
    50      // count
);

// Get only plaintext messages
Message[] memory plaintext = community.getPlaintextMessages(0, 50);

// Get only encrypted messages
Message[] memory encrypted = community.getEncryptedMessages(0, 50);
```

### Room Creation

```solidity
// Approve UNICHAT for room creation fee
unichat.approve(communityAddr, roomCreateFee);

// Create room
address roomAddr = community.createRoom();

// Room is automatically initialized with:
// - Owner: msg.sender
// - Invite fee: community.defaultInviteFee
// - Plaintext: community.defaultPlaintextEnabled
// - Max message bytes: 2048 (fixed)
```

### Key Distribution

#### Why Key Distribution?

For encrypted group messaging, all members need the same symmetric key. The owner encrypts this key for each member using their public key and distributes via Merkle Tree.

#### Distribution Flow

```javascript
// 1. Owner generates/rotates group key
const groupKey = generateAESKey();

// 2. Fetch all active member public keys
const members = await getActiveMembers();
const encryptedKeys = await Promise.all(
    members.map(m => encryptRSA(groupKey, m.publicKey))
);

// 3. Build Merkle Tree of encrypted keys
const leaves = members.map((m, i) => 
    keccak256(m.address, encryptedKeys[i])
);
const tree = new MerkleTree(leaves);

// 4. Store encrypted keys on IPFS
const keyData = {
    members: members.map((m, i) => ({
        address: m.address,
        encryptedKey: encryptedKeys[i]
    })),
    distributionEpoch: currentDistributionEpoch + 1
};
const cid = await ipfs.add(JSON.stringify(keyData));

// 5. Submit root on-chain
await community.distributeGroupKey(
    tree.getRoot(),
    cid
);
```

#### Member Retrieves Key

```javascript
// 1. Fetch key data from IPFS
const keyData = await ipfs.get(latestKeyCid);
const myKeyData = keyData.members.find(m => m.address === myAddress);

// 2. Verify on-chain
const proof = tree.getProof(myKeyData.leaf);
const valid = await community.verifyEncryptedKey(
    distributionEpoch,
    myAddress,
    myKeyData.encryptedKey,
    proof
);

// 3. Decrypt with private key
const groupKey = await decryptRSA(
    myKeyData.encryptedKey,
    myPrivateKey
);

// 4. Use group key to decrypt messages
```

## Room Contract

### Purpose

Small private spaces within a community with customizable settings.

### Features

- **Invite-Only**: No public joining
- **Custom Fees**: Owner sets invite fee
- **Member Management**: Invite, kick, leave
- **Messaging**: Encrypted/plaintext messages
- **Group Key Rotation**: Owner manually rotates
- **Ownership Transfer**: Owner can transfer to member

### Room Lifecycle

#### 1. Creation

```solidity
// Community member creates room
address room = community.createRoom();
// Creator is automatically first member
```

#### 2. Configuration

```solidity
Room room = Room(roomAddr);

// Set invite fee
room.setInviteFee(100e18); // 100 UNICHAT

// Set fee recipient
room.setFeeRecipient(treasuryAddr);

// Configure messaging
room.setPlaintextEnabled(false); // Encrypted only
room.setMessageMaxBytes(4096);   // Increase limit
```

#### 3. Inviting Members

```solidity
// Approve invite fee
unichat.approve(roomAddr, inviteFee);

// Invite user (must be active community member)
room.invite(aliceAddress);

// Or use permit for gasless approval
room.inviteWithPermit(
    bobAddress,
    inviteFee,
    deadline,
    v, r, s
);
```

#### 4. Messaging

```solidity
// Send message
room.sendMessage(
    1,                      // kind: encrypted
    encryptedContent,
    "QmHash..."
);

// Query messages
Message[] memory messages = room.getMessages(0, 100);
```

#### 5. Member Management

```solidity
// Owner kicks member
room.kick(spammerAddress);

// Member leaves voluntarily
room.leave();

// Key epoch increments after member changes
```

### Key Rotation

```solidity
// Owner rotates group key
room.rotateEpoch(metadataHash);
// Increments groupKeyEpoch

// Frontend:
// 1. Detects epoch change
// 2. Fetches new key distribution
// 3. Decrypts with private key
// 4. Uses new key for messages
```

## CommunityFactory Contract

### Purpose

Create unique communities with `(topicToken, maxTier)` constraint.

### Features

- **Uniqueness Enforcement**: Prevents duplicate communities
- **EIP-1167 Clones**: Gas-efficient deployment
- **Batch Queries**: Check multiple communities at once
- **Metadata Retrieval**: Get community info efficiently

### Usage

#### Create Community

```solidity
// Only factory owner can create communities
address community = factory.createCommunity(
    communityOwner,
    topicToken,
    7,              // maxTier
    "BAYC Holders",
    "QmAvatar..."
);
```

#### Query Communities

```solidity
// Get community by key
address community = factory.getCommunityByTokenTier(topicToken, maxTier);

// Get all communities
uint256 total = factory.getAllCommunitiesCount();
address[] memory communities = factory.getCommunities(0, 100);

// Get communities by topic
address[] memory baycCommunities = factory.getCommunitiesByTopic(baycToken);

// Batch get metadata
address[] memory addrs = [community1, community2, community3];
CommunityMetadata[] memory metadata = factory.batchGetCommunityMetadata(addrs);
```

#### Batch Eligibility Check

```solidity
// Check if user eligible for multiple communities
bool[] memory eligible = factory.batchCheckEligibility(
    userAddr,
    [community1, community2],
    [tier1, tier2],
    [epoch1, epoch2],
    [validUntil1, validUntil2],
    [nonce1, nonce2],
    [proof1, proof2]
);
```

## Usage Guide

### Complete Deployment

```solidity
// 1. Deploy implementations
Community communityImpl = new Community();
Room roomImpl = new Room();

// 2. Deploy factory
CommunityFactory factory = new CommunityFactory(
    unichatToken,
    treasury,
    50e18,          // Room creation fee
    address(communityImpl),
    address(roomImpl)
);

// 3. Create first community
address community = factory.createCommunity(
    ownerAddr,
    nftToken,
    7,
    "NFT Holders",
    "QmAvatar..."
);
```

### Member Journey

```javascript
// 1. User checks eligibility (off-chain)
const eligible = await community.eligible(
    userAddr,
    tier,
    epoch,
    validUntil,
    nonce,
    proof
);

if (!eligible) {
    console.log("Not eligible for this community");
    return;
}

// 2. User joins
await community.joinCommunity(
    tier,
    epoch,
    validUntil,
    nonce,
    proof
);

// 3. User creates room
await unichat.approve(community.address, roomCreateFee);
const roomAddr = await community.createRoom();

// 4. User invites others to room
const room = Room.at(roomAddr);
await unichat.approve(roomAddr, inviteFee);
await room.invite(friendAddr);

// 5. Send messages
await room.sendMessage(1, encryptedMsg, "");
```

### Owner Operations

```solidity
// Update Merkle Root
community.setMerkleRoot(newRoot, "ipfs://Qm...");

// Distribute keys
community.distributeGroupKey(keyRoot, "ipfs://Qm...");

// Direct invite (bypasses Merkle)
community.inviteMember(vipAddr, 7);

// Set room defaults
community.setDefaultRoomParams(
    10e18,  // Default invite fee
    true    // Default plaintext enabled
);

// Configure messaging
community.setCommunityPlaintextEnabled(false);
community.setCommunityMessageMaxBytes(4096);

// Pause/unpause
community.pause();
community.unpause();
```

## Function Reference

### Community - Membership

#### `joinCommunity()`
```solidity
function joinCommunity(
    uint256 _maxTier,
    uint256 epoch,
    uint256 validUntil,
    bytes32 nonce,
    bytes32[] calldata proof
) external whenNotPaused
```

#### `inviteMember()`
```solidity
function inviteMember(
    address account,
    uint256 _maxTier
) external onlyOwner whenNotPaused
```

#### `isActiveMember()`
```solidity
function isActiveMember(
    address account
) external view returns (bool)
```

### Community - Messaging

#### `sendCommunityMessage()`
```solidity
function sendCommunityMessage(
    uint8 kind,
    string calldata content,
    string calldata cid
) external onlyActiveMember whenNotPaused
```

#### `sendRedPacketMessage()`
```solidity
function sendRedPacketMessage(
    address token,
    uint256 totalAmount,
    uint256 totalShares,
    bool isRandom,
    uint256[] calldata shareAmounts,
    uint256 expiryDuration,
    uint8 msgKind,
    string calldata memo
) external onlyActiveMember whenNotPaused returns (uint256 packetId)
```

### Community - Room Management

#### `createRoom()`
```solidity
function createRoom()
    external
    onlyActiveMember
    whenNotPaused
    returns (address room)
```

#### `setDefaultRoomParams()`
```solidity
function setDefaultRoomParams(
    uint256 _defaultInviteFee,
    bool _defaultPlaintextEnabled
) external onlyOwner
```

### Room - Member Management

#### `invite()`
```solidity
function invite(
    address user
) external whenNotPaused
```

#### `kick()`
```solidity
function kick(
    address user
) external onlyOwner whenNotPaused
```

#### `leave()`
```solidity
function leave()
    external
    onlyMember
    whenNotPaused
```

### Room - Messaging

#### `sendMessage()`
```solidity
function sendMessage(
    uint8 kind,
    string calldata content,
    string calldata cid
) external onlyMember whenNotPaused
```

## Security

### Merkle Proof Security

**Nonce Replay Protection**: Each proof can only be used once  
**Expiry Enforcement**: `validUntil` timestamp checked  
**Epoch Binding**: Proof tied to specific epoch

### Access Control

**Owner Powers** (Community):
- Update Merkle Root
- Invite members directly
- Distribute keys
- Configure settings
- Pause/unpause

**Owner Powers** (Room):
- Set fees
- Kick members
- Configure messaging
- Rotate keys
- Transfer ownership

**Member Powers**:
- Join (with proof)
- Send messages
- Create rooms
- Invite to rooms
- Leave voluntarily

### Gas Considerations

**Merkle Verification**: ~5,000-10,000 gas  
**Join Community**: ~100,000 gas  
**Create Room**: ~150,000 gas (clone)  
**Send Message**: ~80,000-120,000 gas

## Integration Examples

### Frontend: Merkle Proof Generation

```javascript
import { MerkleTree } from 'merkletreejs';
import keccak256 from 'keccak256';

// Generate leaf
function generateLeaf(community, epoch, user, tier, validUntil, nonce) {
    return keccak256(
        ethers.solidityPacked(
            ['address', 'uint256', 'address', 'uint256', 'uint256', 'bytes32'],
            [community, epoch, user, tier, validUntil, nonce]
        )
    );
}

// Generate proof
function generateProof(members, userAddress) {
    const leaves = members.map(m => generateLeaf(...m));
    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    
    const userLeaf = generateLeaf(...getUserData(userAddress));
    const proof = tree.getProof(userLeaf);
    
    return proof.map(x => '0x' + x.data.toString('hex'));
}
```

### Backend: Member List Management

```javascript
// Update member list
async function updateCommunityMembers(communityAddr, newMembers) {
    // Generate Merkle Tree
    const leaves = newMembers.map(m => generateLeaf(...m));
    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    const root = '0x' + tree.getRoot().toString('hex');
    
    // Store on IPFS
    const ipfsData = {
        members: newMembers.map((m, i) => ({
            address: m.address,
            tier: m.tier,
            validUntil: m.validUntil,
            nonce: m.nonce,
            proof: tree.getProof(leaves[i]).map(x => '0x' + x.data.toString('hex'))
        })),
        epoch: currentEpoch + 1,
        root: root
    };
    
    const cid = await ipfs.add(JSON.stringify(ipfsData));
    
    // Submit on-chain
    const tx = await community.setMerkleRoot(root, `ipfs://${cid}`);
    await tx.wait();
    
    return { root, cid, epoch: currentEpoch + 1 };
}
```

## License

MIT License

---

**Contract Version**: 1.0.0  
**Solidity**: ^0.8.24  
**Dependencies**: OpenZeppelin Contracts v5.x  
**Pattern**: EIP-1167 Minimal Proxy
