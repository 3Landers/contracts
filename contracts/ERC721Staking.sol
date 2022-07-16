// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";

// ============ Interfaces ============

interface IERC20Mintable is IERC20 {
  function mint(address to, uint256 amount) external;
}

interface IERC721ReadOnly {
  event Transfer(
    address indexed from, 
    address indexed to, 
    uint256 indexed tokenId
  );

  function balanceOf(address owner) external view returns (uint256 balance);

  function ownerOf(uint256 tokenId) external view returns (address owner);
}

// ============ Contract ============

/**
 * @dev This staking contract is designed to work 
 * with an existing ERC721 NFT. It also mocks an ERC721
 * in order to work with verfiers like collabland while
 * being unable to approve and transfer like a normal 
 * ERC721 (read-only).
 *
 * It is meant to have access to mint from an ERC20 token
 * without the consideration of that token's max supply.
 *
 * There are no admin functions needed to configure.
 */
contract ERC721Staking is 
  Context, 
  IERC721ReadOnly, 
  IERC721Receiver 
{
  //used in unstake()
  using Address for address;

  // ============ Errors ============

  error InvalidCall();

  // ============ Events ============

  // Tokens were released.
  event Release(address owner, uint256 amount);

  // ============ Constants ============

  //tokens earned per second
  uint256 public constant TOKEN_RATE = 0.0001 ether;
  //this is the contract address for erc721
  IERC721Enumerable public immutable NFT;
  //this is the contract address for erc20
  IERC20Mintable public immutable TOKEN;

  // ============ Storage ============

  //mapping of owner to buffered
  mapping(address => uint256) private _buffered;
  //mapping of owner to starting stake time
  mapping(address => uint256) private _start;
  //mapping of owner to tokens
  mapping(address => uint256[]) private _staked;
  //mapping of token to index
  mapping(uint256 => uint256) private _index;
  //mapping of token to owner
  mapping(uint256 => address) private _owner;

  // ============ Deploy ============

  constructor(IERC721Enumerable nft, IERC20Mintable token) {
    NFT = nft;
    TOKEN = token;
  }

  // ============ Read Methods ============

  /**
   * @dev Returns all the tokens of the `owner` available for staking.
   * This method is only meant for a dApp to read. It is incredibly
   * inefficient for use by a contract write function.
   */
  function available(
    address owner
  ) external view returns(uint256[] memory) {
    uint256 supply = NFT.totalSupply();
    uint256[] memory tokens = new uint256[](
      NFT.balanceOf(owner)
    );
    uint256 index;
    for (uint256 i = 1; i <= supply; i++) {
      if (NFT.ownerOf(i) == owner) {
        tokens[index++] = i;
      }
    }
    return tokens;
  }

  /**
   * @dev Returns the number of tokens in ``owner``'s account.
   */
  function balanceOf(
    address owner
  ) external view returns(uint256 balance) {
    return _staked[owner].length;
  }

  /**
   * @dev allows the contract to receive NFTs
   */
  function onERC721Received(
    address, 
    address, 
    uint256, 
    bytes calldata
  ) external pure returns(bytes4) {
    return 0x150b7a02;
  }

  /**
   * @dev Returns the owner of the `tokenId` token.
   */
  function ownerOf(
    uint256 tokenId
  ) external view returns(address owner) {
    return _owner[tokenId];
  }

  /**
   * @dev Calculate how many tokens an NFT earned
   */
  function releaseable(
    address staker, 
    uint256 timestamp
  ) public view returns(uint256) {
    //duration x # staking x rate + buffered
    return (
      (timestamp - _start[staker]) 
      * _staked[staker].length 
      * TOKEN_RATE
    ) + _buffered[staker];
  }

  /**
   * @dev Returns all the tokens the `staker` has staked
   */
  function staked(
    address staker
  ) external view returns(uint256[] memory) {
    return _staked[staker];
  }

  // ============ Write Methods ============

  /**
   * @dev Releases tokens without unstaking
   */
  function release() public {
    //get the staker
    address staker = _msgSender();
    uint256 toRelease = releaseable(staker, block.timestamp);
    //mint tokens
    address(TOKEN).functionCall(
      abi.encodeWithSelector(TOKEN.mint.selector, staker, toRelease), 
      "Low-level mint failed"
    );
    //reset vault
    _buffered[staker] = 0;
    //reset the clock
    _start[staker] = block.timestamp;
    //emit released
    emit Release(staker, toRelease);
  }

  /**
   * @dev Stakes NFTs
   */
  function stake(uint256[] memory tokenIds) external {
    //get the staker
    address staker = _msgSender();
    //vault the current releaseable
    _buffered[staker] = releaseable(staker, block.timestamp);
    //reset the clock
    _start[staker] = block.timestamp;
    //loop through each token id
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      //reverts if not owner. this prevents random people
      //transferring nfts when this contract is approved to do so
      if (NFT.ownerOf(tokenId) != staker) revert InvalidCall();
      // reverts if contract not approved to move nft tokens
      NFT.transferFrom(staker, address(this), tokenId);
      //index and add token id (index zero is reserved for not exists)
      _index[tokenId] = _staked[staker].length + 1;
      _staked[staker].push(tokenId);
      //mock emit mint transfer
      emit Transfer(address(0), staker, tokenId);
    }
  }

  /**
   * @dev Unstakes NFTs
   */
  function unstake(uint256[] memory tokenIds, bool andRelease) external {
    //get the staker
    address staker = _msgSender();
    if (andRelease) {
      release();
    } else {
      //vault the current releaseable
      _buffered[staker] = releaseable(staker, block.timestamp);
      //reset the clock
      _start[staker] = block.timestamp;
    }
    
    //loop through each token id
    for (uint256 i = 0; i < tokenIds.length; i++) {
      //get token id
      uint256 tokenId = tokenIds[i];
      //get index
      uint256 index = _index[tokenId];
      //only the owner can unstake their nft
      if (index == 0) revert InvalidCall();
      //transfer from contract to owner
      NFT.transferFrom(address(this), staker, tokenId);
      //get last token id
      uint256 lastTokenId = _staked[staker][
        _staked[staker].length - 1
      ];
      //replace the token id we will be removing with
      //the last token id in the array
      _staked[staker][index - 1] = lastTokenId;
      //pop out the last token id in the array
      _staked[staker].pop();
      //remove the token id from the index
      _index[tokenId] = 0;
      //update the last token id with the index of
      //the now unstaked token id
      _index[lastTokenId] = index;
      //mock emit burn transfer
      emit Transfer(staker, address(0), tokenId);
    }
  }
}