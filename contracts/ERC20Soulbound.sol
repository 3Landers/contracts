// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @dev Tokens of Gratitude, issued as rewards for staking sunflowers
 * used to purchase various things in the Gratitude store
 */
contract ERC20Soulbound is Pausable, AccessControl, ERC20 {
  // ============ Errors ============

  error InvalidCall();

  // ============ Constants ============

  //all custom roles
  bytes32 private constant _MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 private constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 private constant _BURNER_ROLE = keccak256("BURNER_ROLE");

  // ============ Deploy ============

  /**
   * @dev Sets the name and symbol. Grants `DEFAULT_ADMIN_ROLE`
   * to the admin
   */
  constructor(address admin) ERC20("3L TIME", "DAY") {
    //set up roles for contract creator
    _setupRole(DEFAULT_ADMIN_ROLE, admin);
    _setupRole(_PAUSER_ROLE, admin);
  }

  // ============ Write Methods ============

  /**
   * @dev Destroys `amount` tokens from the caller.
   */
  function burn(uint256 amount) external {
    _burn(_msgSender(), amount);
  }

  /**
   * @dev Destroys `amount` tokens from `account`, deducting from 
   * the caller's allowance.
   */
  function burn(address account, uint256 amount) external {
    address operator = _msgSender();
    //if operator is not allowed to burn
    if (!hasRole(_BURNER_ROLE, operator)) {
      //get the operator's current allowance
      uint256 currentAllowance = allowance(account, operator);
      //if not enough allowance
      if(currentAllowance < amount) revert InvalidCall();
      //deduct the burn amount from the allowance
      unchecked {
        _approve(account, operator, currentAllowance - amount);
      }
    }
    //now actually burn (with no other restrictions)
    _burn(account, amount);
  }

  /**
   * @dev Creates `amount` new tokens for `to`.
   */
  function mint(
    address to, 
    uint256 amount
  ) external whenNotPaused onlyRole(_MINTER_ROLE) {
    _mint(to, amount);
  }

  /**
   * @dev Pauses all token transfers.
   */
  function pause() public virtual onlyRole(_PAUSER_ROLE) {
    _pause();
  }

  /**
   * @dev Unpauses all token transfers.
   */
  function unpause() public virtual onlyRole(_PAUSER_ROLE) {
    _unpause();
  }

  /**
   * @dev Checks if paused or soulbound before token transfer
   */
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    //revert if paused
    if (paused()
      //or not minting and not burning (soulbound)
      || (from != address(0) && to != address(0))
    ) revert InvalidCall();
    //business as usual
    super._beforeTokenTransfer(from, to, amount);
  }
}
