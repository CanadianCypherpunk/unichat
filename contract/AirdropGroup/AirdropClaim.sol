// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ICommunityClaimJoin.sol";
import "./interfaces/IOZTToken.sol";

/// @notice One-time merkle airdrop claim with permanent inviter binding and on-chain group join.
///         - leaf = keccak256(abi.encode(account))
///         - claim once per address
///         - inviter binding: first bind wins, cannot change
///         - invitees list stored on-chain, pageable by offset/limit
///         - token distribution via OZTToken.mintByClaim
contract AirdropClaim is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------- config -----------
    IOZTToken public immutable oztToken;
    uint256 public immutable claimRewardAmount;

    ICommunityClaimJoin public community;

    bytes32 private _merkleRoot;
    bool public merkleRootFrozen;
    bool public merkleRootInitialized;

    // optional anti-sybil controls
    mapping(address => bool) public blacklisted;
    uint256 public maxInviteesPerInviter; // 0 = unlimited

    /// @notice reward amount for inviter per successful invite, in token smallest unit.
    uint256 public inviterRewardAmount;

    // ----------- state -----------
    mapping(address => bool) private _claimed;

    // invitee -> inviter (immutable after set)
    mapping(address => address) private _inviterOf;

    // inviter -> invitees (on-chain enumerable)
    mapping(address => address[]) private _invitees;

    // ----------- events -----------
    event MerkleRootUpdated(bytes32 indexed newRoot);
    event MerkleRootFrozen();

    event BlacklistUpdated(address indexed account, bool blocked);
    event InviterLimitUpdated(uint256 maxInvitees);

    event CommunityUpdated(address indexed community);

    event InviterBound(address indexed invitee, address indexed inviter);
    event Claimed(address indexed claimer, uint256 amount, address indexed inviter);

    constructor(
        address initialOwner,
        address token_,
        address community_,
        bytes32 merkleRoot_
    ) Ownable(initialOwner) {
        require(token_ != address(0), "TOKEN_0");
        require(community_ != address(0), "COMMUNITY_0");

        oztToken = IOZTToken(token_);
        community = ICommunityClaimJoin(community_);

        if (merkleRoot_ != bytes32(0)) {
            _merkleRoot = merkleRoot_;
            merkleRootInitialized = true;
            emit MerkleRootUpdated(merkleRoot_);
        }

        // Default reward is fixed at 10 tokens, scaled by token decimals.
        uint8 d = IERC20Metadata(token_).decimals();
        claimRewardAmount = 10 * (10 ** uint256(d));
        inviterRewardAmount = claimRewardAmount;

        emit CommunityUpdated(community_);
    }

    // ---------------- views ----------------
    function merkleRoot() external view returns (bytes32) {
        return _merkleRoot;
    }

    function isClaimed(address account) external view returns (bool) {
        return _claimed[account];
    }

    function inviterOf(address invitee) external view returns (address) {
        return _inviterOf[invitee];
    }

    function inviteeCount(address inviter) external view returns (uint256) {
        return _invitees[inviter].length;
    }

    /// @notice Page read of invitees for an inviter.
    /// @dev Returns at most `limit` items starting from `offset`.
    function getInvitees(address inviter, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory page)
    {
        address[] storage arr = _invitees[inviter];
        uint256 len = arr.length;
        if (offset >= len || limit == 0) {
            return new address[](0);
        }

        uint256 end = offset + limit;
        if (end > len) end = len;

        uint256 size = end - offset;
        page = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            page[i] = arr[offset + i];
        }
    }

    // ---------------- admin (onlyOwner) ----------------
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        require(newRoot != bytes32(0), "ROOT_0");
        require(!merkleRootInitialized, "ROOT_ALREADY_SET");
        require(!merkleRootFrozen, "ROOT_FROZEN");
        _merkleRoot = newRoot;
        merkleRootInitialized = true;
        emit MerkleRootUpdated(newRoot);
    }

    /// @notice Freeze merkle root after publishing. Irreversible.
    function freezeMerkleRoot() external onlyOwner {
        require(merkleRootInitialized, "ROOT_NOT_SET");
        require(!merkleRootFrozen, "ALREADY_FROZEN");
        merkleRootFrozen = true;
        emit MerkleRootFrozen();
    }

    function setCommunity(address newCommunity) external onlyOwner {
        require(newCommunity != address(0), "COMMUNITY_0");
        community = ICommunityClaimJoin(newCommunity);
        emit CommunityUpdated(newCommunity);
    }

    function setBlacklist(address account, bool blocked) external onlyOwner {
        blacklisted[account] = blocked;
        emit BlacklistUpdated(account, blocked);
    }

    /// @notice max invitees per inviter (0 = unlimited)
    function setInviterLimit(uint256 maxInvitees) external onlyOwner {
        maxInviteesPerInviter = maxInvitees;
        emit InviterLimitUpdated(maxInvitees);
    }

    /// @notice Rescue any ERC20 mistakenly sent to this contract.
    function rescueERC20(address erc20, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "TO_0");
        IERC20(erc20).safeTransfer(to, amount);
    }

    // ---------------- core ----------------

    /// @notice Claim once with merkle proof; optionally bind inviter forever; join on-chain group for claimer & inviter.
    /// @param proof Merkle proof for msg.sender.
    /// @param inviter Optional inviter address (0 allowed). If already bound, must match (or pass 0).
    function claim(bytes32[] calldata proof, address inviter) external nonReentrant {
        address claimer = msg.sender;

        require(!blacklisted[claimer], "CLAIMER_BLOCKED");
        require(!_claimed[claimer], "ALREADY_CLAIMED");
        require(merkleRootInitialized, "ROOT_NOT_SET");

        // Verify merkle leaf
        bytes32 leaf = keccak256(abi.encode(claimer));
        bool ok = MerkleProof.verifyCalldata(proof, _merkleRoot, leaf);
        require(ok, "INVALID_PROOF");

        // inviter binding rules
        if (inviter != address(0)) {
            require(inviter != claimer, "SELF_INVITE");
            require(!blacklisted[inviter], "INVITER_BLOCKED");
        }

        address bound = _inviterOf[claimer];
        address effectiveInviter = bound;

        if (bound == address(0)) {
            // not bound yet
            if (inviter != address(0)) {
                // enforce inviter limit before pushing
                if (maxInviteesPerInviter != 0) {
                    require(_invitees[inviter].length < maxInviteesPerInviter, "INVITER_LIMIT");
                }

                _inviterOf[claimer] = inviter;
                _invitees[inviter].push(claimer);
                effectiveInviter = inviter;

                emit InviterBound(claimer, inviter);
            }
        } else {
            // already bound: allow inviter==0 (front-end may omit), but forbid change
            if (inviter != address(0)) {
                require(inviter == bound, "INVITER_MISMATCH");
            }
        }

        // Effects before interactions
        _claimed[claimer] = true;

        // Mint fixed reward to claimer.
        oztToken.mintByClaim(claimer, claimRewardAmount);

        // Mint fixed reward to inviter for each successful invite.
        if (effectiveInviter != address(0)) {
            oztToken.mintByClaim(effectiveInviter, inviterRewardAmount);
        }

        // On-chain group join (idempotent group is recommended)
        community.claimJoin(claimer);
        if (effectiveInviter != address(0)) {
            community.claimJoin(effectiveInviter);
        }

        emit Claimed(claimer, claimRewardAmount, effectiveInviter);
    }
}
