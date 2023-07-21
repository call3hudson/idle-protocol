// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRewardsDistribution {
  function notifyRewardAmount(uint256 reward) external;

  function setRewardsDistribution(address _rewardsDistribution) external;
}
