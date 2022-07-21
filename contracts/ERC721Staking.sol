// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
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

interface IERC721TokenURI is IERC721Enumerable {
  function tokenURI(uint256 tokenId) external view returns(string memory);
}

interface IERC721ReadOnly is IERC165 {
  event Transfer(
    address indexed from, 
    address indexed to, 
    uint256 indexed tokenId
  );

  function name() external view returns(string memory);

  function symbol() external view returns(string memory);

  function balanceOf(address owner) external view returns (uint256 balance);

  function ownerOf(uint256 tokenId) external view returns (address owner);

  function tokenURI(uint256 tokenId) external view returns(string memory);
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
  AccessControl,
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

  //admin roles
  bytes32 private constant _STAKER_ROLE = keccak256("STAKER_ROLE");
  bytes32 private constant _CURATOR_ROLE = keccak256("CURATOR_ROLE");
  
  //this is the contract address for erc721
  IERC721TokenURI public immutable NFT;
  //this is the contract address for erc20
  IERC20Mintable public immutable TOKEN;

  // ============ Storage ============
  
  //mapping of owner to balance
  mapping(address => uint256) private _balances;
  //mapping of nft token id to owner
  mapping(uint256 => address) private _owner;
  //mapping of nft token id to starting stake time
  mapping(uint256 => uint256) private _start;
  //mapping of nft token id to last released time
  mapping(uint256 => uint256) private _lastReleased;
  //mapping of nft token id to longest time stake
  mapping(uint256 => uint256) private _highestStakeTime;
  //tokens earned per second
  uint256 private _tokenRate = 0.0001 ether;

  // ============ Deploy ============

  constructor(
    IERC721TokenURI nft, 
    IERC20Mintable token, 
    address admin
  ) {
    NFT = nft;
    TOKEN = token;

    _setupRole(DEFAULT_ADMIN_ROLE, admin);
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
    uint256[] memory tokens = new uint256[](NFT.balanceOf(owner));
    uint256 index;
    for (uint256 i = 1; i <= supply; i++) {
      if (NFT.ownerOf(i) == owner) {
        tokens[index++] = i;
      }
    }
    return tokens;
  }

  /**
   * @dev Returns the date which the token started staking. 
   */
  function highestStakeTime(uint256 tokenId) external view returns(uint256) {
    uint256 duration = _duration(tokenId, block.timestamp);
    return duration > _highestStakeTime[tokenId] 
      ? duration
      : _highestStakeTime[tokenId];
  }

  /**
   * @dev Returns the last time tokens were released on `tokenId`
   */
  function lastReleased(uint256 tokenId) external view returns(uint256) {
    return _lastReleased[tokenId];
  }

  /**
   * @dev Calculate how many tokens an NFT earned
   */
  function releaseable(uint256 tokenId) external view returns(uint256) {
    //if not staking
    if (_lastReleased[tokenId] == 0) {
      return 0;
    }
    //duration x rate
    return _releaseable(_duration(tokenId, block.timestamp));
  }

  /**
   * @dev Returns all the tokens of the `staker` that is currently 
   * staking. It is incredibly inefficient for use by a contract 
   * write function.
   */
  function staked(
    address staker
  ) external view returns(uint256[] memory) {
    uint256 supply = NFT.totalSupply();
    uint256[] memory tokens = new uint256[](balanceOf(staker));
    uint256 index;
    for (uint256 i = 1; i <= supply; i++) {
      if (ownerOf(i) == staker) {
        tokens[index++] = i;
      }
    }
    return tokens;
  }

  /**
   * @dev Returns the date which the token started staking. 
   */
  function stakedSince(uint256 tokenId) external view returns(uint256) {
    return _start[tokenId];
  }

  // ============ Write Methods ============

  /**
   * @dev Releases tokens without unstaking
   */
  function release(uint256[] memory tokenIds) external {
    _release(_msgSender(), tokenIds);
  }

  /**
   * @dev Stakes NFTs
   */
  function stake(uint256[] memory tokenIds) external {
    _stake(_msgSender(), tokenIds);
  }

  /**
   * @dev Unstakes NFTs
   */
  function unstake(uint256[] memory tokenIds) external {
    _unstake(_msgSender(), tokenIds);
  }

  // ============ Admin Methods ============

  /**
   * @dev Releases tokens without unstaking
   */
  function release(
    address staker, 
    uint256[] memory tokenIds
  ) external onlyRole(_STAKER_ROLE) {
    _release(staker, tokenIds);
  }

  /**
   * @dev Stakes NFTs
   */
  function stake(
    address staker, 
    uint256[] memory tokenIds
  ) external onlyRole(_STAKER_ROLE) {
    _stake(staker, tokenIds);
  }

  /**
   * @dev Unstakes NFTs
   */
  function unstake(
    address staker, 
    uint256[] memory tokenIds
  ) external onlyRole(_STAKER_ROLE) {
    _unstake(staker, tokenIds);
  }

  /**
   * @dev Updates staking rate
   */
  function updateRate(uint256 rate) external onlyRole(_CURATOR_ROLE) {
    _tokenRate = rate;
  }

  // ============ ERC721 Related ============

  /**
   * @dev Returns the number of tokens in ``owner``'s account.
   */
  function balanceOf(
    address owner
  ) public view returns(uint256 balance) {
    return _balances[owner];
  }

  /**
   * @dev Never approved
   */
  function getApproved(uint256) public pure returns(address) {
    return address(0);
  }

  /**
   * @dev Never approved
   */
  function isApprovedForAll(address, address) public pure returns(bool) {
    return false;
  }

  /**
   * @dev Returns the name of this staked nft collection
   */
  function name() external pure returns(string memory) {
    return "3Landers Staked";
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
  ) public view returns(address owner) {
    return _owner[tokenId];
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(
    bytes4 interfaceId
  ) public view override(IERC165, AccessControl) returns(bool) {
    return interfaceId == 0x80ac58cd 
      || interfaceId == type(IERC721Metadata).interfaceId 
      || super.supportsInterface(interfaceId);
  }

  /**
   * @dev Returns the name of this staked nft collection
   */
  function symbol() external pure returns(string memory) {
    return "3LS";
  }

  /**
   * @dev Returns the token URI of the original token
   */
  function tokenURI(uint256 tokenId) external view returns(string memory) {
    return NFT.tokenURI(tokenId);
  }

  // ============ Internal Methods ============

  /**
   * @dev returns the duration given the `staker` and `timestamp`
   */
  function _duration(
    uint256 tokenId, 
    uint256 timestamp
  ) internal view returns(uint256) {
    if (_lastReleased[tokenId] == 0) {
      return 0;
    }
    return timestamp - _lastReleased[tokenId];
  }

  /**
   * @dev Releases tokens staked by many nfts
   */
  function _release(address staker, uint256[] memory tokenIds) internal {
    //init to release. we will add amounts in loop
    uint256 toRelease;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      //get tokenId
      uint256 tokenId = tokenIds[i];
      //revert if not staking or not owner
      if (_lastReleased[tokenId] == 0 || staker != ownerOf(tokenId)) 
        revert InvalidCall();
      //add to release
      toRelease += _releaseable(_duration(tokenId, block.timestamp));
      //update the last released time
      _lastReleased[tokenId] = block.timestamp;
    }
    //mint tokens
    address(TOKEN).functionCall(
      abi.encodeWithSelector(TOKEN.mint.selector, staker, toRelease), 
      "Low-level mint failed"
    );
    //emit released
    emit Release(staker, toRelease);
  }
  
  /**
   * @dev Converts time to tokens given `duration`
   */
  function _releaseable(
    uint256 duration
  ) internal view returns(uint256) {
    //duration x rate
    return duration * _tokenRate;
  }

  /**
   * @dev Stakes NFTs
   */
  function _stake(address staker, uint256[] memory tokenIds) internal {
    //add balance
    _balances[staker] += tokenIds.length;
    //loop through each token id
    for (uint256 i = 0; i < tokenIds.length; i++) {
      //get token id
      uint256 tokenId = tokenIds[i];
      //revert if already staking
      //we dont need to check `ownerOf` because 
      //`transferFrom` will fail if not owner
      if (_lastReleased[tokenId] != 0) revert InvalidCall();
      // reverts if contract not approved to move nft tokens
      NFT.transferFrom(staker, address(this), tokenId);
      //map token to staker
      _owner[tokenId] = staker;
      //set start time
      _start[tokenId] = block.timestamp;
      //set the last released time
      _lastReleased[tokenId] = block.timestamp;
      //mock emit mint transfer
      emit Transfer(address(0), staker, tokenId);
    }
  }

  /**
   * @dev Release and unstakes NFTs
   */
  function _unstake(address staker, uint256[] memory tokenIds) internal {
    //less balance
    _balances[staker] -= tokenIds.length;
    //init to release. we will add amounts in loop
    uint256 toRelease;
    //loop through each token id
    for (uint256 i = 0; i < tokenIds.length; i++) {
      //get token id
      uint256 tokenId = tokenIds[i];
      //revert if not staking or not owner
      if (_lastReleased[tokenId] == 0 || staker != ownerOf(tokenId)) 
        revert InvalidCall();

      //transfer nft to owner
      NFT.transferFrom(address(this), staker, tokenId);
      //unmap token from staker
      _owner[tokenId] = address(0);

      //get duration
      uint256 duration = _duration(tokenId, block.timestamp);
      //reset the clocks
      _start[tokenId] = 0;
      _lastReleased[tokenId] = 0;
      //update total
      if (duration > _highestStakeTime[tokenId]) {
        _highestStakeTime[tokenId] = duration;
      }

      //mock emit burn transfer
      emit Transfer(staker, address(0), tokenId);

      //add to release
      toRelease += _releaseable(duration);
    }

    //mint tokens
    address(TOKEN).functionCall(
      abi.encodeWithSelector(TOKEN.mint.selector, staker, toRelease), 
      "Low-level mint failed"
    );
    //emit released
    emit Release(staker, toRelease);
  }
}