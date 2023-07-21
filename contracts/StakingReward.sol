// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

// Inheritance
import './interfaces/IStakingReward.sol';
import './RewardsDistributionRecipient.sol';

contract StakingReward is IStakingReward, RewardsDistributionRecipient {
  using SafeERC20 for IERC20;

  address public rewardsToken;
  address public stakingToken;
  uint256 public periodFinish = 0;

  uint256 public rewardRate = 0;
  uint256 public rewardsDuration = 7 days;
  uint256 public lastUpdateTime;
  uint256 public rewardPerTokenStored;

  mapping(address => uint256) public userRewardPerTokenPaid;
  mapping(address => uint256) public rewards;

  uint256 private _totalSupply;
  mapping(address => uint256) private _balances;

  constructor(address _rewardsDistribution, address _rewardsToken, address _stakingToken) {
    rewardsToken = _rewardsToken;
    stakingToken = _stakingToken;
    rewardsDistribution = _rewardsDistribution;
  }

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  function lastTimeRewardApplicable() public view returns (uint256) {
    return block.timestamp < periodFinish ? block.timestamp : periodFinish;
  }

  function rewardPerToken() public view returns (uint256) {
    if (_totalSupply == 0) {
      return rewardPerTokenStored;
    }
    return
      rewardPerTokenStored +
      ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) /
      _totalSupply;
  }

  function earned(address account) public view returns (uint256) {
    return
      (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) /
      1e18 +
      rewards[account];
  }

  function getRewardForDuration() external view returns (uint256) {
    return rewardRate * rewardsDuration;
  }

  function stake(uint256 amount) external updateReward(msg.sender) {
    require(amount > 0, 'Cannot stake 0');
    _totalSupply = _totalSupply + amount;
    _balances[msg.sender] = _balances[msg.sender] + amount;
    IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), amount);
    emit Staked(msg.sender, amount);
  }

  function withdraw(uint256 amount) public updateReward(msg.sender) {
    require(amount > 0, 'Cannot withdraw 0');
    _totalSupply = _totalSupply - amount;
    _balances[msg.sender] = _balances[msg.sender] - amount;
    IERC20(stakingToken).safeTransfer(msg.sender, amount);
    emit Withdrawn(msg.sender, amount);
  }

  function getReward() public updateReward(msg.sender) {
    uint256 reward = rewards[msg.sender];
    if (reward > 0) {
      rewards[msg.sender] = 0;
      IERC20(rewardsToken).safeTransfer(msg.sender, reward);
      emit RewardPaid(msg.sender, reward);
    }
  }

  function exit() external {
    withdraw(_balances[msg.sender]);
    getReward();
  }

  function notifyRewardAmount(
    uint256 reward
  ) external onlyRewardsDistribution updateReward(address(0)) {
    if (block.timestamp >= periodFinish) {
      rewardRate = reward / rewardsDuration;
    } else {
      uint256 remaining = periodFinish - block.timestamp;
      uint256 leftover = remaining * rewardRate;
      rewardRate = (reward + leftover) / rewardsDuration;
    }

    uint balance = IERC20(rewardsToken).balanceOf(address(this));
    require(rewardRate <= (balance / rewardsDuration), 'Provided reward too high');

    lastUpdateTime = block.timestamp;
    periodFinish = block.timestamp + rewardsDuration;
    emit RewardAdded(reward);
  }

  function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
    require(
      block.timestamp > periodFinish,
      'Previous rewards period must be complete before changing the duration for the new period'
    );
    rewardsDuration = _rewardsDuration;
    emit RewardsDurationUpdated(rewardsDuration);
  }

  modifier updateReward(address account) {
    rewardPerTokenStored = rewardPerToken();
    lastUpdateTime = lastTimeRewardApplicable();
    if (account != address(0)) {
      rewards[account] = earned(account);
      userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
    _;
  }

  event RewardAdded(uint256 reward);
  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);
  event RewardsDurationUpdated(uint256 newDuration);
  event Recovered(address token, uint256 amount);
}
