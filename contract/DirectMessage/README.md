# DirectMessage Contract

On-chain peer-to-peer messaging with RSA public key registration, blacklist management, and red packet integration for the UniChat ecosystem.

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Usage Guide](#usage-guide)
- [Function Reference](#function-reference)
- [RSA Encryption Guide](#rsa-encryption-guide)
- [Red Packet Integration](#red-packet-integration)
- [Events Reference](#events-reference)
- [Security Considerations](#security-considerations)
- [Integration Examples](#integration-examples)

## Overview

The DirectMessage contract provides a fully on-chain solution for private conversations between two addresses. All message history is permanently stored on the blockchain, providing censorship-resistant, verifiable communication with optional end-to-end encryption via client-side RSA.

### What Problem Does It Solve?

- **Decentralized Chat**: No centralized server can censor or lose your messages
- **Verifiable History**: All conversations stored permanently and provably
- **Public Key Infrastructure**: Discover encryption keys for any user on-chain
- **User Control**: Manage your own blacklist and conversation access
- **Token Integration**: Send payments inline with messages seamlessly

### Use Cases

- Private business negotiations with verifiable records
- Secure communication for privacy-focused applications
- Token transfers with accompanying messages/memos
- Decentralized marketplace communications
- Legal agreements with immutable message trails
- Censorship-resistant messaging

## Key Features

### 1. On-Chain Message Storage

**Permanent Record**: Every message is stored forever on the blockchain

**Message Structure**:
```solidity
struct Message {
    address sender;      // Who sent it
    address recipient;   // Who receives it
    uint40 timestamp;    // When it was sent (block timestamp)
    string content;      // Message text (max 1024 bytes)
}
```

**Conversation ID**: Messages indexed by sorted address pair
```solidity
conversationId = keccak256(sort(addressA, addressB))
// Same ID regardless of who queries (alice→bob = bob→alice)
```

**Benefits**:
- No message server can go down
- Cannot be censored or deleted
- Cryptographically verifiable
- Queryable by anyone (public blockchain)
- Paginated retrieval for efficiency

**Trade-offs**:
- All content is public unless encrypted
- Storage costs gas (1KB ≈ 80,000 gas)
- Cannot delete or edit messages

### 2. RSA Public Key Registry

**Purpose**: Enable end-to-end encryption without trusted key servers

**How It Works**:
1. User generates RSA key pair (client-side, private key never leaves device)
2. User registers public key on-chain via `registerPublicKey()`
3. Other users query public key via `getPublicKeyOrDefault()`
4. Encrypt messages client-side before sending on-chain
5. Recipient decrypts with their private key client-side

**Key Features**:
- **Maximum Key Size**: 2048 bytes (supports standard RSA keys)
- **Default Fallback**: Platform default key for users who haven't registered
- **Batch Queries**: Retrieve multiple keys in one call
- **Format Agnostic**: Supports PEM, Base64, or custom formats
- **Updateable**: Users can rotate keys anytime

**Storage**:
```solidity
mapping(address => string) public publicKeys;
string private _defaultPublicKey;
```

**Important**: Contract only stores PUBLIC keys. Private keys must NEVER be shared or sent on-chain.

### 3. Blacklist System

**Purpose**: User-controlled communication access

**Characteristics**:
- **Mutual Enforcement**: Both parties must not block each other to communicate
- **Enumerable**: Query all blocked addresses for a user
- **Dynamic**: Block/unblock at any time
- **Historical Tracking**: Maintains history even after unblock

**Block Effects**:
```
If Alice blocks Bob:
- Bob cannot send messages to Alice ❌
- Alice cannot send messages to Bob ❌
- Existing messages remain viewable ✓
- No retroactive deletion ✓
```

**Storage**:
```solidity
// Active blocks
mapping(address => mapping(address => bool)) private _blocked;

// Historical list (for enumeration)
mapping(address => address[]) private _blockedList;
```

### 4. Peer Management

**Purpose**: Track conversation partners for easy discovery

**Auto-Registration**: First message between two addresses creates peer relationship

**Features**:
- Query all conversation partners: `peersOf(user)`
- Bidirectional tracking (both users added to each other's list)
- Persistent (remains even if conversation inactive)
- Enables "contacts list" functionality in UI

**Use Cases**:
- Display active conversations in chat app
- Export contact list
- Bulk operations on peers
- Social graph analysis

### 5. Message Statistics

**Purpose**: Rate limiting, spam detection, and analytics

**Functions**:
```solidity
// Messages received TODAY (Beijing time UTC+8)
countReceivedTodayBetween(me, peer)

// Messages in custom time range from specific peer
countReceivedInRangeBetween(recipient, peer, startTs, endTs)

// Total messages from ALL peers in time range
countReceivedInRange(recipient, startTs, endTs)
```

**Use Cases**:
- Implement daily message limits (anti-spam)
- User activity metrics
- Engagement analytics
- Rate limiting enforcement (external)

**Time Handling**:
- Timestamps stored as `uint40` (saves gas)
- Supports timezone-aware queries
- Range queries prevent iteration over full history

### 6. Red Packet Integration

**Purpose**: Send tokens with messages in one transaction

**How It Works**:
1. User approves tokens to RedPacket contract (NOT DirectMessage)
2. User calls `sendRedPacketMessage()` on DirectMessage
3. DirectMessage creates personal red packet via RedPacket contract
4. DirectMessage sends special formatted message with packet info
5. Recipient sees message with claimable red packet

**Message Format**:
```
RP|v1|{packetId}|p|{tokenAddress}|{memo}

Example:
RP|v1|12345|p|0x1234...5678|Happy Birthday! 🎂
```

**Benefits**:
- Atomic operation (packet + message)
- Gift giving with personal message
- Payment with memo/invoice
- Verifiable token transfers

## Architecture

### Contract Components

```
DirectMessage Contract
│
├── Message Storage
│   ├── Conversation mapping (address pair → messages[])
│   ├── Message structs with metadata
│   └── Pagination logic
│
├── RSA Key Registry
│   ├── User public keys (address → key)
│   ├── Default key fallback
│   └── Batch query support
│
├── Blacklist System
│   ├── Block status mapping
│   ├── Historical block list
│   └── Mutual block enforcement
│
├── Peer Management
│   ├── Peer lists (address → addresses[])
│   ├── Peer flags (first message detection)
│   └── Discovery functions
│
├── Statistics Tracking
│   ├── Time range counters
│   ├── Per-peer counters
│   └── Global counters
│
└── Red Packet Integration
    ├── IUniChatRedPacket interface
    ├── Atomic create-and-send
    └── Message encoding
```

### Data Flow

#### Sending a Message

```
User calls sendMessage(to, content)
         ↓
[1] Validate recipient (not zero address)
         ↓
[2] Validate content (1-1024 bytes)
         ↓
[3] Check blacklist (mutual check)
    - require(!_blocked[to][from])
    - require(!_blocked[from][to])
         ↓
[4] Update peer lists (if first message)
    - Add to to's peer list
    - Add from to from's peer list
         ↓
[5] Create Message struct
    - sender: msg.sender
    - recipient: to
    - timestamp: block.timestamp
    - content: content
         ↓
[6] Store in conversation
    - conversationId = keccak256(sort(from, to))
    - _conversations[conversationId].push(message)
         ↓
[7] Emit MessageSent event
         ↓
Done ✓
```

#### Querying Messages

```
getMessages(alice, bob, start, count)
         ↓
[1] Compute conversationId
    - keccak256(sort(alice, bob))
         ↓
[2] Get message array
    - messages = _conversations[conversationId]
         ↓
[3] Validate start index
    - require(start <= messages.length)
         ↓
[4] Calculate end index
    - end = min(start + count, messages.length)
         ↓
[5] Copy messages to return array
    - for i in [start, end): out[i] = messages[i]
         ↓
[6] Return messages[]
```

## Usage Guide

### Deployment

```solidity
// Deploy with owner and optional default public key
DirectMessage dm = new DirectMessage(
    ownerAddress,
    "-----BEGIN PUBLIC KEY-----\nMIIBIj..." // Optional default RSA key
);

// Later: Set red packet contract (one-time)
dm.setRedPacket(redPacketContractAddress);
```

### Sending Messages

#### Basic Text Message

```solidity
DirectMessage dm = DirectMessage(contractAddress);

// Send message (costs ~80k gas for 1KB message)
dm.sendMessage(
    recipientAddress,
    "Hello! How are you today?"
);
```

#### With Encryption (Client-Side)

```javascript
// Frontend code
const DirectMessage = new ethers.Contract(dmAddress, dmABI, signer);

// 1. Get recipient's public key
const recipientPubKey = await DirectMessage.getPublicKeyOrDefault(
    recipientAddress
);

// 2. Encrypt message client-side
const encrypted = await crypto.subtle.encrypt(
    {
        name: "RSA-OAEP",
        hash: "SHA-256"
    },
    recipientPubKey,
    new TextEncoder().encode(plaintextMessage)
);

const encryptedBase64 = btoa(String.fromCharCode(...new Uint8Array(encrypted)));

// 3. Send encrypted content on-chain
await DirectMessage.sendMessage(recipientAddress, encryptedBase64);
```

#### With Red Packet

```solidity
// 1. Approve tokens to RedPacket contract (NOT DirectMessage!)
IERC20(tokenAddress).approve(redPacketAddress, amount);

// 2. Send red packet with message
uint256 packetId = dm.sendRedPacketMessage(
    tokenAddress,        // Token to send
    1000e18,            // Amount (including tax if any)
    recipientAddress,    // Who can claim
    86400,              // Expiry: 24 hours (in seconds)
    "Happy Birthday!"   // Memo/greeting
);

// This atomically:
// - Creates personal red packet in RedPacket contract
// - Sends formatted message in DirectMessage
// - Returns packet ID for tracking
```

### Reading Messages

#### Get Message Count

```solidity
uint256 totalMessages = dm.messageCount(aliceAddress, bobAddress);
console.log("Total messages in conversation:", totalMessages);
```

#### Read Messages (Paginated)

```solidity
// Get first 10 messages
Message[] memory messages = dm.getMessages(
    aliceAddress,
    bobAddress,
    0,      // Start at beginning
    10      // Retrieve 10 messages
);

// Process messages
for (uint i = 0; i < messages.length; i++) {
    console.log("From:", messages[i].sender);
    console.log("To:", messages[i].recipient);
    console.log("Time:", messages[i].timestamp);
    console.log("Content:", messages[i].content);
    console.log("---");
}

// Get next 10 messages
Message[] memory nextBatch = dm.getMessages(
    aliceAddress,
    bobAddress,
    10,     // Start at index 10
    10      // Retrieve 10 more
);
```

#### Load Full Conversation

```javascript
// Frontend: Load all messages with pagination
async function loadConversation(userA, userB) {
    const PAGE_SIZE = 50;
    const allMessages = [];
    
    const total = await dm.messageCount(userA, userB);
    
    for (let offset = 0; offset < total; offset += PAGE_SIZE) {
        const batch = await dm.getMessages(userA, userB, offset, PAGE_SIZE);
        allMessages.push(...batch);
    }
    
    return allMessages;
}
```

### RSA Key Management

#### Register Your Public Key

```javascript
// Generate key pair (client-side)
const keyPair = await crypto.subtle.generateKey(
    {
        name: "RSA-OAEP",
        modulusLength: 2048,
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: "SHA-256"
    },
    true,
    ["encrypt", "decrypt"]
);

// Export public key
const exportedKey = await crypto.subtle.exportKey("spki", keyPair.publicKey);
const pemKey = convertToPEM(exportedKey);

// Register on-chain
await dm.registerPublicKey(pemKey);

// Store private key securely (local storage, encrypted)
storePrivateKey(keyPair.privateKey);
```

#### Query Public Keys

```solidity
// Get specific user's key (reverts if not registered)
string memory key = dm.getPublicKey(userAddress);

// Get with fallback to default (recommended)
string memory key = dm.getPublicKeyOrDefault(userAddress);

// Batch query multiple users
address[] memory users = [alice, bob, charlie, dave];
string[] memory keys = dm.getPublicKeysOrDefault(users);
```

#### Owner: Set Default Key

```solidity
// Only contract owner can set default
string memory platformKey = "-----BEGIN PUBLIC KEY-----\n...";
dm.setDefaultPublicKey(platformKey);

// Query current default
string memory defaultKey = dm.defaultPublicKey();
```

### Blacklist Management

#### Block a User

```solidity
// Block spammer
dm.blockAddress(spammerAddress);

// Now:
// - Spammer cannot message you
// - You cannot message spammer
// - Existing messages still visible
```

#### Unblock a User

```solidity
// Unblock after resolving issue
dm.unblockAddress(formerSpammer);

// Communication can resume
```

#### Check Block Status

```solidity
// Check if Alice blocked Bob
bool isBlocked = dm.isBlocked(aliceAddress, bobAddress);

// Check mutual block
bool aliceBlockedBob = dm.isBlocked(aliceAddress, bobAddress);
bool bobBlockedAlice = dm.isBlocked(bobAddress, aliceAddress);
bool mutualBlock = aliceBlockedBob || bobBlockedAlice;
```

#### List Blocked Users

```solidity
// Get all currently blocked addresses
address[] memory blockedUsers = dm.blockedOf(myAddress);

console.log("You have blocked", blockedUsers.length, "users");
for (uint i = 0; i < blockedUsers.length; i++) {
    console.log("Blocked:", blockedUsers[i]);
}
```

### Message Statistics

#### Today's Messages

```solidity
// Count messages received TODAY from specific peer
// (Beijing time UTC+8)
uint256 todayCount = dm.countReceivedTodayBetween(
    myAddress,
    peerAddress
);

if (todayCount >= DAILY_LIMIT) {
    console.log("Daily message limit reached");
}
```

#### Custom Time Range

```solidity
// Count messages in last 7 days from peer
uint40 startTs = uint40(block.timestamp - 7 days);
uint40 endTs = uint40(block.timestamp);

uint256 weekCount = dm.countReceivedInRangeBetween(
    myAddress,
    peerAddress,
    startTs,
    endTs
);

// Count from all peers
uint256 totalWeekCount = dm.countReceivedInRange(
    myAddress,
    startTs,
    endTs
);
```

### Peer Discovery

```solidity
// Get all conversation partners
address[] memory peers = dm.peersOf(myAddress);

console.log("You have conversations with", peers.length, "users:");
for (uint i = 0; i < peers.length; i++) {
    uint256 msgCount = dm.messageCount(myAddress, peers[i]);
    console.log("Peer:", peers[i], "| Messages:", msgCount);
}
```

## Function Reference

### Messaging Functions

#### `sendMessage()`
```solidity
function sendMessage(
    address to,
    string calldata content
) external
```
Send a message to another address.

**Parameters**:
- `to`: Recipient address (cannot be zero)
- `content`: Message text (1-1024 bytes)

**Requirements**:
- Recipient not zero address
- Content length between 1 and 1024 bytes
- Sender and recipient must not block each other

**Effects**:
- Creates peer relationship if first message
- Stores message on-chain
- Emits `MessageSent` event

**Gas**: ~80,000-120,000 (depends on content length)

#### `messageCount()`
```solidity
function messageCount(
    address a,
    address b
) external view returns (uint256)
```
Get total number of messages in conversation.

#### `getMessages()`
```solidity
function getMessages(
    address a,
    address b,
    uint256 start,
    uint256 count
) external view returns (Message[] memory out)
```
Retrieve messages with pagination.

**Parameters**:
- `start`: Starting index (0-based)
- `count`: Number of messages to retrieve

**Returns**: Array of messages (may be less than `count` if reaching end)

#### `peersOf()`
```solidity
function peersOf(
    address user
) external view returns (address[] memory)
```
List all conversation partners.

### Blacklist Functions

#### `blockAddress()`
```solidity
function blockAddress(
    address target
) external
```
Add address to your blacklist.

**Effects**:
- Prevents `target` from messaging you
- Prevents you from messaging `target`
- Adds to enumerable blocked list

#### `unblockAddress()`
```solidity
function unblockAddress(
    address target
) external
```
Remove address from your blacklist.

**Requires**: `target` currently blocked

#### `isBlocked()`
```solidity
function isBlocked(
    address owner_,
    address target
) external view returns (bool)
```
Check if `owner_` has blocked `target`.

#### `blockedOf()`
```solidity
function blockedOf(
    address owner_
) external view returns (address[] memory active)
```
Get list of all currently blocked addresses.

### RSA Key Functions

#### `registerPublicKey()`
```solidity
function registerPublicKey(
    string calldata publicKey
) external
```
Register or update your RSA public key.

**Requirements**:
- Key length: 1-2048 bytes
- Must be valid text

**Emits**: `PublicKeyRegistered` event

#### `getPublicKey()`
```solidity
function getPublicKey(
    address user
) external view returns (string memory)
```
Get registered public key.

**Reverts**: If user hasn't registered key

#### `getPublicKeyOrDefault()`
```solidity
function getPublicKeyOrDefault(
    address user
) public view returns (string memory)
```
Get public key with fallback to default.

**Recommended**: Use this instead of `getPublicKey()`

#### `getPublicKeysOrDefault()`
```solidity
function getPublicKeysOrDefault(
    address[] calldata users
) external view returns (string[] memory)
```
Batch query public keys.

#### `setDefaultPublicKey()`
```solidity
function setDefaultPublicKey(
    string calldata newDefault
) external onlyOwner
```
Set contract's default public key (owner only).

#### `defaultPublicKey()`
```solidity
function defaultPublicKey()
    external view
    returns (string memory)
```
Query current default public key.

### Statistics Functions

#### `countReceivedTodayBetween()`
```solidity
function countReceivedTodayBetween(
    address me,
    address peer
) external view returns (uint256)
```
Count messages received today (Beijing time UTC+8) from peer.

#### `countReceivedInRangeBetween()`
```solidity
function countReceivedInRangeBetween(
    address recipient,
    address peer,
    uint40 startTs,
    uint40 endTs
) external view returns (uint256)
```
Count messages from peer in time range.

#### `countReceivedInRange()`
```solidity
function countReceivedInRange(
    address recipient,
    uint40 startTs,
    uint40 endTs
) external view returns (uint256 total)
```
Count total messages from all peers in time range.

### Red Packet Functions

#### `setRedPacket()`
```solidity
function setRedPacket(
    address redPacket_
) external onlyOwner
```
Set red packet contract (one-time, owner only).

#### `sendRedPacketMessage()`
```solidity
function sendRedPacketMessage(
    address token,
    uint256 totalAmount,
    address recipient,
    uint256 expiryDuration,
    string calldata memo
) external returns (uint256 packetId)
```
Create personal red packet and send message atomically.

**Requirements**:
- Red packet contract set
- Tokens approved to red packet contract
- Same requirements as `sendMessage()`

**Returns**: Red packet ID

## RSA Encryption Guide

### Client-Side Encryption Flow

```javascript
// === SENDER ===

// 1. Get recipient's public key
const recipientPubKey = await dm.getPublicKeyOrDefault(recipientAddr);

// 2. Import key for crypto API
const importedKey = await crypto.subtle.importKey(
    "spki",
    pemToArrayBuffer(recipientPubKey),
    {
        name: "RSA-OAEP",
        hash: "SHA-256"
    },
    false,
    ["encrypt"]
);

// 3. Encrypt plaintext message
const plaintext = "Secret message!";
const encrypted = await crypto.subtle.encrypt(
    { name: "RSA-OAEP" },
    importedKey,
    new TextEncoder().encode(plaintext)
);

// 4. Convert to base64
const encryptedBase64 = btoa(
    String.fromCharCode(...new Uint8Array(encrypted))
);

// 5. Send encrypted content
await dm.sendMessage(recipientAddr, encryptedBase64);

// === RECIPIENT ===

// 1. Read encrypted message
const messages = await dm.getMessages(senderAddr, myAddr, 0, 10);
const encryptedContent = messages[0].content;

// 2. Decode base64
const encryptedBytes = Uint8Array.from(
    atob(encryptedContent),
    c => c.charCodeAt(0)
);

// 3. Import private key
const privateKey = await loadPrivateKey(); // From secure storage

// 4. Decrypt
const decrypted = await crypto.subtle.decrypt(
    { name: "RSA-OAEP" },
    privateKey,
    encryptedBytes
);

// 5. Get plaintext
const plaintext = new TextDecoder().decode(decrypted);
console.log("Decrypted:", plaintext);
```

### Security Best Practices

**Key Generation**:
- Generate client-side only
- Never send private key anywhere
- Use strong randomness
- 2048-bit minimum key size

**Key Storage**:
- Encrypt private key before storing
- Use secure local storage
- Separate encryption/signing keys
- Implement key rotation

**Message Encryption**:
- Always encrypt sensitive content
- Verify recipient key before encrypting
- Use authenticated encryption
- Consider Perfect Forward Secrecy (PFS)

## Red Packet Integration

### Setup

```solidity
// Owner configures red packet integration
dm.setRedPacket(redPacketContractAddress);
```

### User Sends Red Packet

```javascript
const token = "0x..."; // USDT address
const amount = ethers.parseUnits("100", 6); // 100 USDT
const recipient = "0x...";
const expiry = 86400; // 24 hours
const memo = "Happy Birthday! 🎂";

// 1. Approve tokens to RedPacket contract
const tokenContract = new ethers.Contract(token, erc20ABI, signer);
await tokenContract.approve(redPacketAddress, amount);

// 2. Send red packet with message
const tx = await dm.sendRedPacketMessage(
    token,
    amount,
    recipient,
    expiry,
    memo
);
const receipt = await tx.wait();

// 3. Extract packet ID from events
const packetId = receipt.events.find(
    e => e.event === "PersonalPacketCreated"
).args.id;

console.log("Red packet created:", packetId);
```

### Frontend Parsing

```javascript
function parseMessage(content) {
    // Check for red packet format
    const rpPattern = /^RP\|v1\|(\d+)\|p\|(0x[a-fA-F0-9]{40})\|(.*)$/;
    const match = content.match(rpPattern);
    
    if (match) {
        return {
            type: 'redpacket',
            packetId: match[1],
            tokenAddress: match[2],
            memo: match[3]
        };
    }
    
    return {
        type: 'text',
        content: content
    };
}

// Display in UI
const message = await dm.getMessage(...);
const parsed = parseMessage(message.content);

if (parsed.type === 'redpacket') {
    showRedPacketUI(parsed.packetId, parsed.tokenAddress, parsed.memo);
} else {
    showTextMessage(parsed.content);
}
```

## Events Reference

### MessageSent
```solidity
event MessageSent(
    bytes32 indexed convoId,
    address indexed from,
    address indexed to,
    uint40 timestamp,
    string content
);
```
Emitted when a message is sent.

### Blocked
```solidity
event Blocked(
    address indexed owner,
    address indexed target
);
```
Emitted when user blocks an address.

### Unblocked
```solidity
event Unblocked(
    address indexed owner,
    address indexed target
);
```
Emitted when user unblocks an address.

### PublicKeyRegistered
```solidity
event PublicKeyRegistered(
    address indexed user,
    string publicKey
);
```
Emitted when user registers/updates their public key.

### DefaultPublicKeyUpdated
```solidity
event DefaultPublicKeyUpdated(
    string publicKey
);
```
Emitted when owner updates default public key.

## Security Considerations

### On-Chain Data Privacy

⚠️ **IMPORTANT**: All data stored on-chain is PUBLIC.

**Publicly Visible**:
- Message content (unless encrypted)
- Sender and recipient addresses
- Timestamps
- Conversation patterns

**Privacy Recommendations**:
- Always encrypt sensitive content client-side
- Use separate addresses for anonymous communication
- Consider metadata leakage (timing, frequency)
- Never send private keys or sensitive data unencrypted

### Access Control

**No Admin Override**: Contract owner cannot:
- Read, modify, or delete messages
- Access private keys
- Unblock users on behalf of others

**User-Controlled**: Only you can:
- Block/unblock addresses
- Register your public key
- Access your conversations (public blockchain)

### Attack Vectors & Mitigations

#### Spam Attacks
**Risk**: Malicious users flood you with unwanted messages

**Mitigations**:
- Use blacklist to block spammers
- Implement rate limiting using statistics functions
- Require payment/stake to send first message (external)

#### Front-Running
**Risk**: MEV bots see messages in mempool before inclusion

**Mitigations**:
- Encrypt all sensitive content
- Use Flashbots or private RPCs
- Accept as inherent blockchain property

#### Storage Bloat
**Risk**: Large messages increase gas costs

**Mitigations**:
- 1KB message limit enforced
- Gas costs naturally limit spam
- Use IPFS for large content (store hash on-chain)

#### Key Compromise
**Risk**: Private key leaked, past messages decrypted

**Mitigations**:
- Implement key rotation
- Use Perfect Forward Secrecy (ephemeral keys)
- Separate signing key from encryption key

### Best Practices

**For Users**:
- Encrypt all sensitive messages
- Backup private keys securely
- Rotate keys periodically
- Use blacklist proactively

**For Developers**:
- Implement proper key management
- Provide encryption warnings in UI
- Cache blockchain data (events)
- Validate message format
- Rate limit message sending

## Integration Examples

### React Frontend Example

```jsx
import { ethers } from 'ethers';
import { useEffect, useState } from 'react';

function ChatComponent({ peerAddress }) {
    const [messages, setMessages] = useState([]);
    const [newMessage, setNewMessage] = useState('');
    
    const dm = new ethers.Contract(DM_ADDRESS, DM_ABI, signer);
    
    // Load conversation
    useEffect(() => {
        async function loadMessages() {
            const count = await dm.messageCount(myAddress, peerAddress);
            const msgs = await dm.getMessages(myAddress, peerAddress, 0, count);
            setMessages(msgs);
        }
        loadMessages();
    }, [peerAddress]);
    
    // Send message
    async function sendMessage() {
        // Encrypt if recipient has public key
        const pubKey = await dm.getPublicKeyOrDefault(peerAddress);
        const content = pubKey ? await encrypt(newMessage, pubKey) : newMessage;
        
        await dm.sendMessage(peerAddress, content);
        setNewMessage('');
    }
    
    // Listen for new messages
    useEffect(() => {
        const filter = dm.filters.MessageSent(null, null, myAddress);
        dm.on(filter, (convoId, from, to, timestamp, content) => {
            if (from === peerAddress) {
                setMessages(prev => [...prev, {
                    sender: from,
                    content: content,
                    timestamp: timestamp
                }]);
            }
        });
        
        return () => dm.removeAllListeners(filter);
    }, [peerAddress]);
    
    return (
        <div>
            <div className="messages">
                {messages.map((msg, i) => (
                    <div key={i}>
                        <strong>{msg.sender}:</strong> {msg.content}
                    </div>
                ))}
            </div>
            <input 
                value={newMessage}
                onChange={e => setNewMessage(e.target.value)}
            />
            <button onClick={sendMessage}>Send</button>
        </div>
    );
}
```

### Backend Indexer

```javascript
// Index all messages for fast queries
const provider = new ethers.JsonRpcProvider(RPC_URL);
const dm = new ethers.Contract(DM_ADDRESS, DM_ABI, provider);

// Listen to all messages
dm.on("MessageSent", async (convoId, from, to, timestamp, content) => {
    await db.messages.insert({
        conversationId: convoId,
        from: from,
        to: to,
        timestamp: parseInt(timestamp),
        content: content,
        isRedPacket: content.startsWith("RP|v1|"),
        createdAt: new Date()
    });
    
    console.log(`New message: ${from} → ${to}`);
});
```

## License

MIT License - see contract file for full text.

---

**Contract Version**: 1.0.0  
**Solidity**: ^0.8.24  
**Dependencies**: OpenZeppelin Contracts v5.x  
**Network Compatibility**: All EVM-compatible chains
