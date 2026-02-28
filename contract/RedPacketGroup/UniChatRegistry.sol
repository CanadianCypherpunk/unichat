// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title UniChatRegistry
 * @notice Global configuration center (token list, listing fee, referral codes, platform treasury, factory, optional token-gating validator)
 */
contract UniChatRegistry is AccessControl {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant BIG_OWNER_ROLE = keccak256("BIG_OWNER_ROLE");
    bytes32 public constant OWNER_ROLE     = keccak256("OWNER_ROLE");

    // Fixed core tokens
    IERC20  public immutable UNICHAT;
    address public immutable USDT;

    // Platform config
    address public platformTreasury;
    address public groupFactory;
    address public anyTokenBuyValidator; // Optional: token-gating validator contract (future integration)

    // Listing fee (default 20000 UNICHAT, assuming 18 decimals)
    uint256 public listingFee = 20_000e18;

    // Token List (allowed tokens can create groups)
    mapping(address => bool) public allowedGroupTokens;
    address[] public allowedTokensList; // Listed tokens list

    // Listing applications
    struct ListingApplication {
        address applicant;
        uint64 appliedAt;
        bool   exists;
    }
    mapping(address => ListingApplication) public listingApplications;

    // Referral
    // listingShareBps: 5000~8000 only applies to "listing fee" distribution
    struct Referral {
        address referrer;
        uint16  listingShareBps; // 50%~80%
        bool    exists;
    }
    mapping(bytes32 => Referral) private _referrals;
    mapping(address => bytes32[]) private _addressToCodes; // Mapping from address to referral code list

    // Group registry (for discovery)
    struct GroupInfo {
        address creator;
        address groupToken;
        uint64  createdAt;
        bool    active;
    }
    mapping(address => GroupInfo) public groups;
    address[] public allGroups;

    // Events
    event PlatformTreasuryUpdated(address indexed treasury);
    event GroupFactoryUpdated(address indexed factory);
    event AnyTokenBuyValidatorUpdated(address indexed validator);
    event ListingFeeUpdated(uint256 newFee);

    event ReferralCreated(bytes32 indexed code, address indexed referrer, uint16 listingShareBps);

    event TokenListingApplied(address indexed token, address indexed applicant, bytes32 indexed referralCode);
    event TokenListingApproved(address indexed token, bool allowed);

    event GroupRegistered(address indexed group, address indexed creator, address indexed groupToken);

    constructor(
        address unichatToken,
        address usdtToken,
        address bigOwner,
        address owner,
        address treasury
    ) {
        require(unichatToken != address(0) && usdtToken != address(0), "Registry: zero token");
        require(bigOwner != address(0) && owner != address(0), "Registry: zero admin");
        require(treasury != address(0), "Registry: zero treasury");

        UNICHAT = IERC20(unichatToken);
        USDT = usdtToken;
        platformTreasury = treasury;

        // AccessControl setup
        _grantRole(DEFAULT_ADMIN_ROLE, bigOwner);
        _grantRole(BIG_OWNER_ROLE, bigOwner);

        // platform owner (ops)
        _grantRole(OWNER_ROLE, owner);

        // BIG_OWNER is admin of everything by default
        _setRoleAdmin(OWNER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(BIG_OWNER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    // -------------------------
    // Admin setters
    // -------------------------
    function setPlatformTreasury(address treasury) external onlyRole(OWNER_ROLE) {
        require(treasury != address(0), "Registry: zero treasury");
        platformTreasury = treasury;
        emit PlatformTreasuryUpdated(treasury);
    }

    function setGroupFactory(address factory) external onlyRole(OWNER_ROLE) {
        require(factory != address(0), "Registry: zero factory");
        groupFactory = factory;
        emit GroupFactoryUpdated(factory);
    }

    function setAnyTokenBuyValidator(address validator) external onlyRole(OWNER_ROLE) {
        anyTokenBuyValidator = validator;
        emit AnyTokenBuyValidatorUpdated(validator);
    }

    function setListingFee(uint256 newFee) external onlyRole(OWNER_ROLE) {
        require(newFee > 0, "Registry: fee=0");
        listingFee = newFee;
        emit ListingFeeUpdated(newFee);
    }

    // -------------------------
    // Referral
    // -------------------------
    /**
     * @notice Create referral code (for listing fee distribution, can also be used for group entry referrer binding)
     * @notice Anyone can create their own referral code, referrer address automatically set to caller address (msg.sender)
     * @param listingShareBps Listing fee distribution ratio (50%~80%)
     * @param salt Used to generate unique code (frontend can use random number/counter/user input)
     */
    function createReferral(uint16 listingShareBps, bytes32 salt)
        external
        returns (bytes32 code)
    {
        require(listingShareBps >= 5000 && listingShareBps <= 8000, "Registry: share out of range");

        address referrer = msg.sender;
        code = keccak256(abi.encodePacked(referrer, listingShareBps, salt, block.chainid, address(this)));
        require(!_referrals[code].exists, "Registry: code exists");

        _referrals[code] = Referral({
            referrer: referrer,
            listingShareBps: listingShareBps,
            exists: true
        });

        // Add to address to referral code mapping
        _addressToCodes[referrer].push(code);

        emit ReferralCreated(code, referrer, listingShareBps);
    }

    function referralExists(bytes32 code) external view returns (bool) {
        return _referrals[code].exists;
    }

    function getReferrer(bytes32 code) external view returns (address) {
        return _referrals[code].referrer;
    }

    function getListingShareBps(bytes32 code) external view returns (uint16) {
        return _referrals[code].listingShareBps;
    }

    /**
     * @notice Query all referral codes created by specified address
     * @param addr Address
     * @return codes Array of all referral codes created by this address
     */
    function getCodesByAddress(address addr) external view returns (bytes32[] memory) {
        return _addressToCodes[addr];
    }

    // -------------------------
    // Token listing
    // -------------------------
    /**
     * @notice Apply to add token to token list: automatically approved after paying listingFee (default 20000 UNICHAT)
     * @dev If referralCode is provided, distribute according to its listingShareBps to referrer, remainder to platform treasury
     * @dev Automatically approved after submission, no review required
     */
    function applyTokenListing(address token, bytes32 referralCode) external {
        require(token != address(0), "Registry: zero token");
        require(!allowedGroupTokens[token], "Registry: already allowed");
        require(!listingApplications[token].exists, "Registry: already applied");

        uint256 fee = listingFee;
        UNICHAT.safeTransferFrom(msg.sender, address(this), fee);

        address treasury = platformTreasury;
        uint256 toRef = 0;

        if (_referrals[referralCode].exists && _referrals[referralCode].referrer != address(0)) {
            uint16 bps = _referrals[referralCode].listingShareBps;
            toRef = (fee * bps) / 10_000;
            if (toRef > 0) {
                UNICHAT.safeTransfer(_referrals[referralCode].referrer, toRef);
            }
        }

        uint256 toTreasury = fee - toRef;
        if (toTreasury > 0) {
            UNICHAT.safeTransfer(treasury, toTreasury);
        }

        listingApplications[token] = ListingApplication({
            applicant: msg.sender,
            appliedAt: uint64(block.timestamp),
            exists: true
        });

        // Automatically approved, no review required
        allowedGroupTokens[token] = true;
        
        // Add to listed tokens list (avoid duplicates)
        if (allowedTokensList.length == 0 || allowedTokensList[allowedTokensList.length - 1] != token) {
            allowedTokensList.push(token);
        }

        emit TokenListingApplied(token, msg.sender, referralCode);
        emit TokenListingApproved(token, true);
    }

    /**
     * @notice Owner review: allow/revoke token as "group creation token"
     */
    function approveTokenListing(address token, bool allowed) external onlyRole(OWNER_ROLE) {
        require(token != address(0), "Registry: zero token");
        allowedGroupTokens[token] = allowed;
        
        // If allowed, add to list (avoid duplicates)
        if (allowed) {
            // Check if already in list
            bool exists = false;
            for (uint256 i = 0; i < allowedTokensList.length; i++) {
                if (allowedTokensList[i] == token) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                allowedTokensList.push(token);
            }
        }
        // Note: when revoking, don't remove from list, filter via allowedGroupTokens when querying

        // keep application record (optional); you can delete if you want:
        // delete listingApplications[token];

        emit TokenListingApproved(token, allowed);
    }

    // -------------------------
    // Group registry (called by factory)
    // -------------------------
    function registerGroup(address group, address groupToken, address creator) external {
        require(msg.sender == groupFactory, "Registry: only factory");
        require(group != address(0) && creator != address(0), "Registry: zero addr");

        groups[group] = GroupInfo({
            creator: creator,
            groupToken: groupToken,
            createdAt: uint64(block.timestamp),
            active: true
        });
        allGroups.push(group);

        emit GroupRegistered(group, creator, groupToken);
    }

    function groupsLength() external view returns (uint256) {
        return allGroups.length;
    }

    // ========== View Getters (with named return values for frontend/testing convenience) ==========

    /**
     * @notice Get group information
     */
    function getGroupInfo(address group) external view returns (
        address creator,
        address groupToken,
        uint64 createdAt,
        bool active
    ) {
        GroupInfo storage g = groups[group];
        return (g.creator, g.groupToken, g.createdAt, g.active);
    }

    /**
     * @notice Get listing application information
     */
    function getListingApplication(address token) external view returns (
        address applicant,
        uint64 appliedAt,
        bool exists
    ) {
        ListingApplication storage app = listingApplications[token];
        return (app.applicant, app.appliedAt, app.exists);
    }

    // -------------------------
    // Allowed tokens list
    // -------------------------
    /**
     * @notice Get length of listed tokens list
     */
    function allowedTokensLength() external view returns (uint256) {
        return allowedTokensList.length;
    }

    /**
     * @notice Get listed token address by index
     * @param index Index position (starting from 0)
     */
    function getAllowedToken(uint256 index) external view returns (address) {
        require(index < allowedTokensList.length, "Registry: index out of bounds");
        return allowedTokensList[index];
    }

    /**
     * @notice Batch get listed tokens list (with validity check)
     * @param offset Starting index
     * @param limit Maximum return count (recommend not exceeding 100 to avoid high gas)
     * @return tokens Token address array
     * @return count Actual returned valid token count
     */
    function getAllowedTokens(uint256 offset, uint256 limit) external view returns (
        address[] memory tokens,
        uint256 count
    ) {
        uint256 total = allowedTokensList.length;
        if (offset >= total) {
            return (new address[](0), 0);
        }

        uint256 maxLimit = limit > 100 ? 100 : limit; // Limit maximum return count
        uint256 end = offset + maxLimit;
        if (end > total) {
            end = total;
        }

        address[] memory tempTokens = new address[](maxLimit);
        uint256 validCount = 0;

        // Iterate and filter out still valid tokens
        for (uint256 i = offset; i < end; i++) {
            address token = allowedTokensList[i];
            if (allowedGroupTokens[token]) {
                tempTokens[validCount] = token;
                validCount++;
            }
        }

        // Create array of exact size
        tokens = new address[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            tokens[i] = tempTokens[i];
        }

        return (tokens, validCount);
    }

    /**
     * @notice Get all listed and valid tokens list (Note: gas consumption may be high, recommend using getAllowedTokens for pagination)
     */
    function getAllAllowedTokens() external view returns (address[] memory) {
        uint256 total = allowedTokensList.length;
        address[] memory tempTokens = new address[](total);
        uint256 validCount = 0;

        // Filter out still valid tokens
        for (uint256 i = 0; i < total; i++) {
            address token = allowedTokensList[i];
            if (allowedGroupTokens[token]) {
                tempTokens[validCount] = token;
                validCount++;
            }
        }

        // Create array of exact size
        address[] memory tokens = new address[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            tokens[i] = tempTokens[i];
        }

        return tokens;
    }
}
