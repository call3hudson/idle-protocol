// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './interfaces/IStrategy.sol';

/**
 * @author  Huang.
 * @title   Vault.
 * @dev     Yield farming vault which accrues interests from Idle protocl via Strategy.
 * @notice  Any users can deposit their ether here and earn interests.
 */

contract Vault is ERC20, Ownable, ReentrancyGuard {
  // Interface to the interest earning strategy
  IStrategy public strategy;

  event Deposited(address indexed sender, uint amountDeposited, uint yETH);
  event Withdrawn(address indexed sender, uint amountWithdrawn, uint yETH);
  event Invested(address indexed sender, uint amountInvested);
  event StrategyChanged(address indexed sender, IStrategy former, IStrategy latter);

  // Set the default strategy of vault - can be changed upon calling changeStrategy()
  constructor(IStrategy strategy_) ERC20('ETH Vault', 'yETH') {
    strategy = strategy_;
  }

  // Must be declared to receive ether from strategies
  receive() external payable {}

  /**
   * @notice  Deposit ether and receives yETH according to the rate set by the first depositor. If nobody deposited, then it will mint 100 yETH.
   * @dev     Receive ether and figure out how much yETH needed according to the yETH total supply and ether funds.
   */
  function deposit() external payable {
    // Check if no ether was provided
    require(msg.value > 0, 'Vault: You must provide ether to deposit');

    // Calculate amount of yETH to be minted - if nobody minted, 100 yETH would be taken
    uint256 amountToMint;
    if (totalSupply() == 0)
      amountToMint = 1e20;
      // Add current balance and expected balance in strategy
    else
      amountToMint =
        (totalSupply() * msg.value) /
        (strategy.getExpectedWithdraw() + address(this).balance - msg.value);

    // Mint yETH
    _mint(msg.sender, amountToMint);

    emit Deposited(msg.sender, msg.value, amountToMint);
  }

  /**
   * @notice  Depositors burn yETH and receives their liquidity and interests according to the shares.
   * @dev     Calculate amount to be returned with current balance and expected withdraw and total supply.
   * @param   amountYEth_  Amount of yETH to be burned.
   */
  function withdraw(uint256 amountYEth_) external nonReentrant {
    // Check the validation of parameter
    require(amountYEth_ > 0, 'Vault: Invalid yETH to withdraw');
    require(amountYEth_ <= balanceOf(msg.sender), 'Vault: Insufficient yETH');

    // Calculate the amount of corresponding ether
    uint256 amountToReturn = (amountYEth_ *
      (strategy.getExpectedWithdraw() + address(this).balance)) / totalSupply();

    // If the ether inside the contract is insufficient, then we need to get ether from strategies
    if (amountToReturn > address(this).balance) {
      uint256 amountNeeded = amountToReturn - address(this).balance;
      strategy.withdraw(amountNeeded);
    }

    // Send actual amount of ether to the caller
    payable(msg.sender).transfer(amountToReturn);

    // Burns amountYEth_ that is already withdrawn
    _burn(msg.sender, amountYEth_);

    emit Withdrawn(msg.sender, amountToReturn, amountYEth_);
  }

  /**
   * @notice  Invest 90% of ethers inside the contract to the strategy.
   * @dev     Owner can invest 90% of currently remaining ethers to the strategy.
   */
  function invest() external onlyOwner {
    // Check the possibility of investing
    require(address(this).balance > 0, 'Vault: No ether to invest');

    // Calculate 90% of remaining ether
    uint256 amount = (address(this).balance * 9) / 10;

    // Provide ethers to the strategy
    strategy.mint{ value: amount }();

    emit Invested(msg.sender, amount);
  }

  /**
   * @notice  Changes more efficient strategy for more interests.
   * @dev     Withdraw all ether locked on the strategy and set new strategy.
   * @param   strategy_  New strategy to be set.
   */
  function changeStrategy(IStrategy strategy_) external onlyOwner {
    // We first need to withdraw the funds provided
    strategy.withdrawAll();

    // Keep the former strategy for record
    IStrategy former = strategy;
    strategy = strategy_;

    emit StrategyChanged(msg.sender, former, strategy);
  }
}
