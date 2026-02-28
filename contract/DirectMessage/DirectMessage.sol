// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @notice Red packet contract interface (for inline red packet calls)
 */
interface IUniChatRedPacket {
    function createPersonalPacketFor(
        address creator,
        address token,
        uint256 totalAmount,
        address recipient,
        uint256 expiryDuration
    ) external returns (uint256 packetId);
}

/// @title DirectMessage - On-chain personal chat between two addresses
/// @notice Stores conversation messages between two parties on-chain with pagination support; supports blocking/unblocking and blacklist queries; RSA public key registration with default public key fallback
contract DirectMessage is Ownable {
    /// @notice Maximum bytes per message (UTF-8)
    uint32 public constant MAX_MESSAGE_BYTES = 1024; // approximately 1 KB

    // === RSA Public Key Related ===
    /// @notice Maximum bytes limit for public key (to prevent abuse and oversized strings on-chain)
    uint32 public constant MAX_PUBKEY_BYTES = 2048; // can be adjusted as needed

    /// @notice Address => RSA public key (PEM/Base64/text)
    mapping(address => string) public publicKeys;

    /// @notice Default RSA public key (fallback when user is not registered)
    string private _defaultPublicKey;

    // ======== Data Structures ========

    /// @notice A message
    struct Message {
        address sender;
        address recipient;
        uint40 timestamp; // UNIX seconds
        string content;   // UTF-8 text
    }

    // ======== Events ========

    /// @notice Message sent event (for frontend listening)
    event MessageSent(
        bytes32 indexed convoId,
        address indexed from,
        address indexed to,
        uint40 timestamp,
        string content
    );

    /// @notice An address blocks target
    event Blocked(address indexed owner, address indexed target);

    /// @notice An address unblocks target
    event Unblocked(address indexed owner, address indexed target);

    // === RSA Public Key Related Events ===
    /// @notice User registers or updates their RSA public key
    event PublicKeyRegistered(address indexed user, string publicKey);

    /// @notice Default RSA public key updated
    event DefaultPublicKeyUpdated(string publicKey);

    // ======== Storage ========

    // Conversation ID (keccak256 of two sorted addresses) -> message list
    mapping(bytes32 => Message[]) private _conversations;

    // Address book: allows each address to enumerate its conversation partners
    mapping(address => address[]) private _peers;
    mapping(address => mapping(address => bool)) private _hasPeer;

    // Blacklist (owner blocks target)
    mapping(address => mapping(address => bool)) private _blocked;

    // To support "enumerating blacklist", maintain history list and in-list flag
    mapping(address => address[]) private _blockedList;
    mapping(address => mapping(address => bool)) private _inBlockedList;

    /// @notice Red packet contract reference (for inline red packet calls)
    IUniChatRedPacket public redPacket;

    // ======== Constructor (v5 Ownable requires initialOwner) ========

    /// @param initialOwner Initial contract owner (recommended to pass multisig/Timelock)
    /// @param initialDefaultPublicKey Initial default RSA public key (can be empty)
    constructor(address initialOwner, string memory initialDefaultPublicKey)
        Ownable(initialOwner)
    {
        if (bytes(initialDefaultPublicKey).length > 0) {
            _defaultPublicKey = initialDefaultPublicKey;
            emit DefaultPublicKeyUpdated(initialDefaultPublicKey);
        }
    }

    // ======== Internal Utilities ========

    function _convoId(address a, address b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b))
                     : keccak256(abi.encodePacked(b, a));
    }

    function _countInRange(bytes32 id, address recipient, uint40 startTs, uint40 endTs)
        internal
        view
        returns (uint256 cnt)
    {
        if (endTs <= startTs) return 0;
        Message[] storage arr = _conversations[id];
        for (uint256 i = 0; i < arr.length; i++) {
            Message storage m = arr[i];
            if (m.recipient == recipient && m.timestamp >= startTs && m.timestamp < endTs) {
                unchecked { cnt++; }
            }
        }
    }

    // ======== Public Interface: Messages and Blacklist ========

    /// @notice Send a message to the recipient (content will be stored on-chain; rejected if mutually blocked)
    function sendMessage(address to, string calldata content) external {
        _sendMessage(msg.sender, to, content);
    }

    /// @notice Internal function: send message
    /// @dev Extracts core logic for reuse by sendMessage and sendRedPacketMessage
    /// @param from Message sender address
    /// @param to Message recipient address
    /// @param content Message content
    function _sendMessage(
        address from,
        address to,
        string memory content
    ) internal {
        require(to != address(0), "invalid recipient");
        uint256 len = bytes(content).length;
        require(len > 0, "empty");
        require(len <= MAX_MESSAGE_BYTES, "too long");

        // Blacklist check
        require(!_blocked[to][from], "recipient blocked you");
        require(!_blocked[from][to], "you blocked recipient");

        bytes32 id = _convoId(from, to);

        // Update address book
        if (!_hasPeer[from][to]) {
            _hasPeer[from][to] = true;
            _peers[from].push(to);
        }
        if (!_hasPeer[to][from]) {
            _hasPeer[to][from] = true;
            _peers[to].push(from);
        }

        Message memory m = Message({
            sender: from,
            recipient: to,
            timestamp: uint40(block.timestamp),
            content: content
        });

        _conversations[id].push(m);
        emit MessageSent(id, from, to, m.timestamp, content);
    }

    /// @notice Query total number of messages in conversation (a, b)
    function messageCount(address a, address b) external view returns (uint256) {
        return _conversations[_convoId(a, b)].length;
    }

    /// @notice Paginated read of messages in conversation (a, b): range [start, start+count)
    function getMessages(
        address a,
        address b,
        uint256 start,
        uint256 count
    ) external view returns (Message[] memory out) {
        bytes32 id = _convoId(a, b);
        Message[] storage arr = _conversations[id];
        uint256 len = arr.length;
        require(start <= len, "start OOB");
        uint256 end = start + count;
        if (end > len) end = len;
        uint256 n = end > start ? end - start : 0;

        out = new Message[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = arr[start + i];
        }
    }

    /// @notice List conversation partners of an address (list of peer addresses)
    function peersOf(address user) external view returns (address[] memory) {
        return _peers[user];
    }

    /// @notice Add an address to blacklist (owner=msg.sender)
    function blockAddress(address target) external {
        require(target != address(0), "invalid");
        require(!_blocked[msg.sender][target], "already");
        _blocked[msg.sender][target] = true;

        if (!_inBlockedList[msg.sender][target]) {
            _inBlockedList[msg.sender][target] = true;
            _blockedList[msg.sender].push(target);
        }
        emit Blocked(msg.sender, target);
    }

    /// @notice Remove an address from blacklist (owner=msg.sender)
    function unblockAddress(address target) external {
        require(_blocked[msg.sender][target], "not blocked");
        _blocked[msg.sender][target] = false;
        emit Unblocked(msg.sender, target);
    }

    /// @notice Query if owner has blocked target
    function isBlocked(address owner_, address target) external view returns (bool) {
        return _blocked[owner_][target];
    }

    /// @notice Return list of addresses currently in "blocked state" for owner
    function blockedOf(address owner_) external view returns (address[] memory active) {
        address[] storage hist = _blockedList[owner_];
        uint256 cnt;
        for (uint256 i = 0; i < hist.length; i++) {
            if (_blocked[owner_][hist[i]]) cnt++;
        }
        active = new address[](cnt);
        uint256 p;
        for (uint256 i = 0; i < hist.length; i++) {
            if (_blocked[owner_][hist[i]]) active[p++] = hist[i];
        }
    }

    // ======== Statistics ========

    /// @notice Count messages received by me in conversation (me, peer) "today (Beijing time, UTC+8)"
    function countReceivedTodayBetween(address me, address peer) external view returns (uint256) {
        // First shift UTC time to UTC+8, round to 1 day, then subtract 8 hours to get UTC time of 00:00 that day
        uint40 start = uint40((((block.timestamp + 8 hours) / 1 days) * 1 days) - 8 hours);
        uint40 end   = start + 1 days; // UTC time of 24:00 that day
        return _countInRange(_convoId(me, peer), me, start, end);
    }

    /// @notice Count messages received by recipient in conversation (recipient, peer) within given time range
    function countReceivedInRangeBetween(
        address recipient,
        address peer,
        uint40 startTs,
        uint40 endTs
    ) external view returns (uint256) {
        return _countInRange(_convoId(recipient, peer), recipient, startTs, endTs);
    }

    /// @notice Count total messages received by an address from all conversations within given time range
    function countReceivedInRange(
        address recipient,
        uint40 startTs,
        uint40 endTs
    ) external view returns (uint256 total) {
        if (endTs <= startTs) return 0;
        address[] storage ps = _peers[recipient];
        for (uint256 i = 0; i < ps.length; i++) {
            total += _countInRange(_convoId(recipient, ps[i]), recipient, startTs, endTs);
        }
    }

    // ======== RSA Public Key: Registration & Query & Default Fallback ========

    /// @notice Register or update my own RSA public key (recommended PEM/Base64 text)
    function registerPublicKey(string calldata publicKey) external {
        uint256 L = bytes(publicKey).length;
        require(L > 0, "empty key");
        require(L <= MAX_PUBKEY_BYTES, "key too long");
        publicKeys[msg.sender] = publicKey;
        emit PublicKeyRegistered(msg.sender, publicKey);
    }

    /// @notice Get "explicitly registered" public key of specified address (reverts if not registered)
    function getPublicKey(address user) external view returns (string memory) {
        string memory k = publicKeys[user];
        require(bytes(k).length > 0, "Public key not registered");
        return k;
    }

    /// @notice Get public key of specified address; fallback to default public key if not registered
    function getPublicKeyOrDefault(address user) public view returns (string memory) {
        string memory k = publicKeys[user];
        if (bytes(k).length == 0) {
            return _defaultPublicKey;
        }
        return k;
    }

    /// @notice Batch get public keys (with default fallback)
    function getPublicKeysOrDefault(address[] calldata users)
        external
        view
        returns (string[] memory)
    {
        string[] memory keys = new string[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            string memory k = publicKeys[users[i]];
            keys[i] = bytes(k).length == 0 ? _defaultPublicKey : k;
        }
        return keys;
    }

    /// @notice Owner only: set/update default RSA public key
    function setDefaultPublicKey(string calldata newDefault) external onlyOwner {
        require(bytes(newDefault).length > 0, "empty default");
        require(bytes(newDefault).length <= MAX_PUBKEY_BYTES, "default too long");
        _defaultPublicKey = newDefault;
        emit DefaultPublicKeyUpdated(newDefault);
    }

    /// @notice Read current default RSA public key
    function defaultPublicKey() external view returns (string memory) {
        return _defaultPublicKey;
    }

    // ======== Red Packet Contract Integration ========

    /**
     * @notice Set red packet contract address (can only be set once)
     * @dev Only owner can call
     * @param redPacket_ Red packet contract address
     */
    function setRedPacket(address redPacket_) external onlyOwner {
        require(address(redPacket) == address(0), "already set");
        require(redPacket_ != address(0), "ZeroAddr");
        redPacket = IUniChatRedPacket(redPacket_);
    }

    /**
     * @notice Complete in one transaction: create personal red packet + send a red packet message
     * @dev User must approve tokens to red packet contract in advance
     * @param token Red packet token address
     * @param totalAmount Total red packet amount
     * @param recipient Red packet recipient address
     * @param expiryDuration Expiry duration in seconds
     * @param memo Red packet greeting message
     */
    function sendRedPacketMessage(
        address token,
        uint256 totalAmount,
        address recipient,
        uint256 expiryDuration,
        string calldata memo
    ) external returns (uint256 packetId) {
        require(address(redPacket) != address(0), "RedPacket not set");
        require(recipient != address(0), "recipient zero");

        // 1. Create personal red packet, creator=msg.sender
        packetId = redPacket.createPersonalPacketFor(
            msg.sender,
            token,
            totalAmount,
            recipient,
            expiryDuration
        );

        // 2. Encode red packet message content
        string memory content = string.concat(
            "RP|v1|",
            Strings.toString(packetId),
            "|p|",
            _toHexAddress(token),
            "|",
            memo
        );

        // 3. Write to chat history
        _sendMessage(msg.sender, recipient, content);
    }

    /// @notice Convert address to hexadecimal string (with 0x prefix)
    /// @param addr Address to convert
    /// @return Hexadecimal string
    function _toHexAddress(address addr) private pure returns (string memory) {
        return Strings.toHexString(uint256(uint160(addr)), 20);
    }
}
