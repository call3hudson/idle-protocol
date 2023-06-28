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

  // Maximum slippage percent that could be ignored
  uint256 public constant SLIPPAGE = 5;

  event Deposited(address indexed sender, uint amountDeposited, uint yETH);
  event Withdrawn(address indexed sender, uint amountWithdrawn, uint yETH);
  event Invested(address indexed sender, uint amountInvested);
  event Rebalanced(address indexed sender, uint amountRebalanced);
  event StrategyChanged(address indexed sender, IStrategy former, IStrategy latter);

  // Set the default strategy of vault - can be changed upon calling changeStrategy()
  constructor(IStrategy strategy_) ERC20('ETH Vault', 'yETH') {
    strategy = strategy_;
  }

  // Must be declared to receive ether from strategies
  receive() external payable {
    require(msg.sender == address(strategy), 'WETH: Only strategy can send ether');
  }

  /**
   * @notice  Deposit ether and receives yETH according to the rate set by the first depositor. If nobody deposited, then it will mint 100 yETH.
   * @dev     Receive ether and figure out how much yETH needed according to the yETH total supply and ether funds.
   */
  function deposit() external payable {
    // Check if no ether was provided
    require(msg.value > 0, 'Vault: You must provide ether to deposit');

    // Calculate amount of yETH to be minted - if nobody minted, 100 yETH would be taken
    uint256 amountToMint;
    (uint256 spotAmount, uint256 oracleAmount) = strategy.getExpectedWithdraw();
    require(validate(spotAmount, oracleAmount), 'Vault: Tolerance rate exceeded');

    if (totalSupply() == 0)
      amountToMint = 1e20;
      // Add current balance and expected balance in strategy
    else
      amountToMint = (totalSupply() * msg.value) / (spotAmount + address(this).balance - msg.value);

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
    (uint256 spotAmount, uint256 oracleAmount) = strategy.getExpectedWithdraw();
    require(validate(spotAmount, oracleAmount), 'Vault: Tolerance rate exceeded');

    uint256 amountToReturn = (amountYEth_ * (spotAmount + address(this).balance)) / totalSupply();

    // If the ether inside the contract is insufficient, then we need to get ether from strategies
    if (amountToReturn > address(this).balance) {
      uint256 amountNeeded = amountToReturn - address(this).balance;
      strategy.withdraw(amountNeeded);
    }

    // Send actual amount of ether to the caller
    (bool success, ) = (msg.sender).call{ value: amountToReturn }('');
    require(success, 'Vault: Transfer failed.');

    // Burns amountYEth_ that is already withdrawn
    _burn(msg.sender, amountYEth_);

    emit Withdrawn(msg.sender, amountToReturn, amountYEth_);
  }

  /**
   * @notice  Invest 90% of ethers inside the contract to the strategy.
   * @dev     Owner can invest 90% of total balance to the strategy.
   */
  function invest() external onlyOwner {
    // Check the possibility of investing
    (uint256 spotAmount, uint256 oracleAmount) = strategy.getExpectedWithdraw();
    require(validate(spotAmount, oracleAmount), 'Vault: Tolerance rate exceeded');

    uint256 totalDeposited = address(this).balance + spotAmount;
    require(address(this).balance * 10 > totalDeposited, 'Vault: No ether to invest');

    // Calculate 90% of total ether
    uint256 amount = address(this).balance - (totalDeposited / 10);

    // Provide ethers to the strategy
    strategy.mint{ value: amount }();

    emit Invested(msg.sender, amount);
  }

  /**
   * @notice  Rebalance to keep 10% of total balance inside the vault contract.
   * @dev     Owner can keep 10% of total balance inside the vault.
   */
  function rebalance() external onlyOwner {
    // Check the possibility of rebalancing
    (uint256 spotAmount, uint256 oracleAmount) = strategy.getExpectedWithdraw();
    require(validate(spotAmount, oracleAmount), 'Vault: Tolerance rate exceeded');

    uint256 totalDeposited = address(this).balance + spotAmount;
    require(address(this).balance < (totalDeposited / 10), 'Vault: No ether to rebalance');

    // Calculate 10% of total ether
    uint256 amount = (totalDeposited / 10) - address(this).balance;

    // Withdraw required ethers from the strategy
    strategy.withdraw(amount);

    emit Rebalanced(msg.sender, amount);
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

  /**
   * @notice  Validate the expected withdraw.
   * @dev     Check that two values are in the tolerance range.
   * @param   spotAmount_  Expected withdraw based on spot price.
   * @param   oracleAmount_  Expected withdraw based on oracle price.
   * @return  bool  Returns true if validated.
   */
  function validate(uint256 spotAmount_, uint256 oracleAmount_) internal pure returns (bool) {
    if (oracleAmount_ == spotAmount_) return true;

    // In case of oracle price is bigger than spot price
    if (oracleAmount_ > spotAmount_ && ((spotAmount_ * (100 + SLIPPAGE)) / 100 > oracleAmount_))
      return true;

    // Otherwise
    if (oracleAmount_ < spotAmount_ && ((oracleAmount_ * (100 + SLIPPAGE)) / 100 > spotAmount_))
      return true;

    return false;
  }
}
