// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
  uint256 public supply;
  constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

  function mint(address to, uint256 tokenId) external {
    _safeMint(to, tokenId);
    supply++;
  }

  function totalSupply() external view returns(uint256) {
    return supply;
  }
}