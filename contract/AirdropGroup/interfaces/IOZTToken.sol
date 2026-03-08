// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOZTToken {
    function decimals() external view returns (uint8);
    function mintByClaim(address to, uint256 amount) external;
    function setClaimContractOnce(address claimContract_) external;
}
