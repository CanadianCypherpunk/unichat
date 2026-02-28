// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

interface IUniChatRegistry_Factory {
    function allowedGroupTokens(address token) external view returns (bool);
    function registerGroup(address group, address groupToken, address creator) external;
}

interface IRedPacketGroup_Init {
    function initialize(address registry, address mainOwner, address groupToken, uint256 entryFee, string calldata groupName, string calldata groupRules) external;
}

/**
 * @title GroupFactory
 * @notice Create red packet group instances using EIP-1167 minimal proxy (Clones)
 */
contract GroupFactory {
    using Clones for address;

    address public immutable implementation;
    IUniChatRegistry_Factory public immutable registry;

    event GroupCreated(address indexed group, address indexed creator, address indexed groupToken, uint256 entryFee);

    constructor(address registry_, address implementation_) {
        require(registry_ != address(0) && implementation_ != address(0), "Factory: zero addr");
        registry = IUniChatRegistry_Factory(registry_);
        implementation = implementation_;
    }

    /**
     * @notice Create a main group (public group)
     * @dev Must select a groupToken from the registry token list
     * @param groupToken Group token address
     * @param entryFee Entry fee
     * @param groupName Group name
     * @param groupRules Group rules
     */
    function createGroup(address groupToken, uint256 entryFee, string calldata groupName, string calldata groupRules) external returns (address group) {
        require(registry.allowedGroupTokens(groupToken), "Factory: token not allowed");
        require(entryFee > 0, "Factory: fee=0");

        group = implementation.clone();
        IRedPacketGroup_Init(group).initialize(address(registry), msg.sender, groupToken, entryFee, groupName, groupRules);

        registry.registerGroup(group, groupToken, msg.sender);

        emit GroupCreated(group, msg.sender, groupToken, entryFee);
    }
}
