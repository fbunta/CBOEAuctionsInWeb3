// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";

contract LW3Token is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 10 * 10**decimals()); // 10 full tokens to be minted to developer's address upon deployment
    }

    function get(uint256 value) external {
      _mint(msg.sender, value * 10**decimals());
    }

    function transfer(address from, address to, uint256 value) external {
      _update(from, to, value * 10**decimals());
    }
}
