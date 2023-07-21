// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '../node_modules/hardhat/console.sol';

import './interfaces/IRewardsDistribution.sol';
import './interfaces/IStrategy.sol';
import './interfaces/IVGov.sol';
import './interfaces/IWETH.sol';
import './VGov.sol';

/**
 * @author  Huang.
 * @title   Vault.
 * @dev     Yield farming vault which accrues interests from Idle protocol via Strategy.
 * @notice  Any users can deposit their ether here and earn interests.
 */

contract Vault is ERC20, Ownable, ReentrancyGuard {
  // Interface to the interest earning strategy
  IStrategy public strategy;
  IVGov public governance;
  IRewardsDistribution public rewardsDistribution;

  // Last stored vault token price
  uint256 public currentPrice = 0;

  // Current reward held for stakers
  uint256 public totalRewardStored = 0;

  // Maximum slippage percent that could be ignored
  uint256 public constant SLIPPAGE = 5;

  // Deployed addresses of WETH
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  event Deposited(address indexed sender, uint amountDeposited, uint yETH);
  event Withdrawn(address indexed sender, uint amountWithdrawn, uint yETH);
  event Invested(address indexed sender, uint amountInvested);
  event Rebalanced(address indexed sender, uint amountRebalanced);
  event StrategyChanged(address indexed sender, IStrategy former, IStrategy latter);
  event RewardsDistributionChanged(
    address indexed sender,
    IRewardsDistribution former,
    IRewardsDistribution latter
  );
  event RewardsDistributionStarted(
    address indexed sender,
    IRewardsDistribution distribution,
    uint256 amountToDistributed
  );

  /**
   * @notice  Update new yEth price and held reward of 1% profit.
   * @dev     Check the increase in token price and take 1% of increase as reward.
   */
  modifier updatePrice(uint256 payed) {
    // Check the total fund locked
    (uint256 spotAmount, uint256 oracleAmount, uint256 virtualAmount) = strategy
      .getExpectedWithdraw();

    // Check if the amount is malformed
    require(validate(spotAmount, oracleAmount), 'Vault: Tolerance rate exceeded');
    require(validate(spotAmount, virtualAmount), 'Vault: Tolerance rate exceeded');

    // Calculate current price per yEth
    uint256 totalSupply = totalSupply();

    // Only if there's yETH token already minted
    if (totalSupply != 0) {
      // Get the new price
      uint256 newPrice = ((spotAmount + address(this).balance - payed) * 1e18) / totalSupply;

      // If the new price is bigger than former price
      if (currentPrice < newPrice && currentPrice > 0) {
        // Take out 1% of profit as reward
        uint256 rewardPerToken = (newPrice - currentPrice) / 100;
        uint256 reward = (rewardPerToken * totalSupply) / 1e18;
        newPrice = newPrice - rewardPerToken;

        // Mint WETH according to the amount of savings
        strategy.withdraw(reward);
        IWETH(WETH).deposit{ value: reward }();

        // Update totalRewardStored
        totalRewardStored += reward;
      }

      // Set new price
      currentPrice = newPrice;
    }
    _;
  }

  // Set the default strategy of vault - can be changed upon calling changeStrategy()
  constructor(IStrategy strategy_) ERC20('ETH Vault', 'yETH') {
    strategy = strategy_;
    governance = new VGov();
  }

  // Must be declared to receive ether from strategies
  receive() external payable {
    require(msg.sender == address(strategy), 'WETH: Only strategy can send ether');
  }

  /**
   * @notice  Deposit ether and receives yETH according to the rate set by the first depositor. If nobody deposited, then it will mint 100 yETH.
   * @dev     Receive ether and figure out how much yETH needed according to the yETH total supply and ether funds.
   */
  function deposit() external payable updatePrice(msg.value) {
    // Check if no ether was provided
    require(msg.value > 0, 'Vault: You must provide ether to deposit');

    // Calculate amount of yETH to be minted - if nobody minted, 100 yETH would be taken
    uint256 amountToMint;

    if (totalSupply() == 0)
      amountToMint = 1e20;
      // Add current balance and expected balance in strategy
    else amountToMint = (msg.value * 1e18) / currentPrice;

    // Mint yETH
    _mint(msg.sender, amountToMint);

    // Mint Governance token as well
    governance.mint(msg.sender, amountToMint);

    emit Deposited(msg.sender, msg.value, amountToMint);
  }

  /**
   * @notice  Depositors burn yETH and receives their liquidity and interests according to the shares.
   * @dev     Calculate amount to be returned with current balance and expected withdraw and total supply.
   * @param   amountYEth_  Amount of yETH to be burned.
   */
  function withdraw(uint256 amountYEth_) external nonReentrant updatePrice(0) {
    // Check the validation of parameter
    require(amountYEth_ > 0, 'Vault: Invalid yETH to withdraw');
    require(amountYEth_ <= balanceOf(msg.sender), 'Vault: Insufficient yETH');
    require(
      amountYEth_ <= governance.balanceOf(msg.sender),
      'Vault: Please refund staked Govtoken'
    );

    // Calculate the amount of corresponding ether
    uint256 amountToReturn = (amountYEth_ * currentPrice) / 1e18;

    // If the ether inside the contract is insufficient, then we need to get ether from strategies
    if (amountToReturn > address(this).balance) {
      uint256 amountNeeded = amountToReturn - address(this).balance;
      strategy.withdraw(amountNeeded);
    }

    // Send actual amount of ether to the caller
    (bool success, ) = (msg.sender).call{ value: amountToReturn }('');
    require(success, 'Vault: Transfer failed.');

    // Burn amountYEth_ that is already withdrawn
    _burn(msg.sender, amountYEth_);

    // Burn Governance token as well
    governance.burn(msg.sender, amountYEth_);

    emit Withdrawn(msg.sender, amountToReturn, amountYEth_);
  }

  /**
   * @notice  Invest 90% of ethers inside the contract to the strategy.
   * @dev     Owner can invest 90% of total balance to the strategy.
   */
  function invest() external onlyOwner {
    // Check the possibility of investing
    (uint256 spotAmount, uint256 oracleAmount, uint256 virtualAmount) = strategy
      .getExpectedWithdraw();
    require(validate(spotAmount, oracleAmount), 'Vault: Tolerance rate exceeded');
    require(validate(spotAmount, virtualAmount), 'Vault: Tolerance rate exceeded');

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
    (uint256 spotAmount, uint256 oracleAmount, uint256 virtualAmount) = strategy
      .getExpectedWithdraw();
    require(validate(spotAmount, oracleAmount), 'Vault: Tolerance rate exceeded');
    require(validate(spotAmount, virtualAmount), 'Vault: Tolerance rate exceeded');

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
   * @notice  Changes rewards distribution target.
   * @dev     Change the address of rewardsDistribution.
   * @param   distribution_  New distribution address.
   */
  function setStakingContract(IRewardsDistribution distribution_) external onlyOwner {
    // Keep the former address for record
    IRewardsDistribution former = rewardsDistribution;
    rewardsDistribution = distribution_;

    emit RewardsDistributionChanged(msg.sender, former, rewardsDistribution);
  }

  function startRewardsDistribution() external onlyOwner {
    // First, transfer the reward to the target distribution
    if (totalRewardStored > 0)
      IERC20(WETH).transfer(address(rewardsDistribution), totalRewardStored);

    // Notify that a new campaign started
    rewardsDistribution.notifyRewardAmount(totalRewardStored);

    emit RewardsDistributionStarted(msg.sender, rewardsDistribution, totalRewardStored);
  }

  /**
   * @notice  Validate the expected withdraw.
   * @dev     Check that two values are in the tolerance range.
   * @param   spotAmount_  Expected withdraw based on spot price.
   * @param   validateAmount_  Expected withdraw based on validation price.
   * @return  bool  Returns true if validated.
   */
  function validate(uint256 spotAmount_, uint256 validateAmount_) internal pure returns (bool) {
    if (validateAmount_ == spotAmount_) return true;

    // In case of oracle price is bigger than spot price
    if (validateAmount_ > spotAmount_ && ((spotAmount_ * (100 + SLIPPAGE)) / 100 > validateAmount_))
      return true;

    // Otherwise
    if (validateAmount_ < spotAmount_ && ((validateAmount_ * (100 + SLIPPAGE)) / 100 > spotAmount_))
      return true;

    return false;
  }
}
