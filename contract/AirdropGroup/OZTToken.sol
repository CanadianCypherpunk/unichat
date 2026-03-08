// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OZTToken is ERC20, Ownable {
    address public claimContract;
    bool public claimContractSet;

    constructor(string memory name_, string memory symbol_, address initialOwner)
        ERC20(name_, symbol_)
        Ownable(initialOwner)
    {}

    function setClaimContractOnce(address claimContract_) external onlyOwner {
        require(!claimContractSet, "CLAIM_CONTRACT_ALREADY_SET");
        require(claimContract_ != address(0), "ZERO_ADDR");

        claimContractSet = true;
        claimContract = claimContract_;
    }

    function mintByClaim(address to, uint256 amount) external {
        require(msg.sender == claimContract, "NOT_CLAIM_CONTRACT");
        _mint(to, amount);
    }
}
