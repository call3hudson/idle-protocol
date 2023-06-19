// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IStrategy {
  function mint() external payable;

  function withdraw(uint256 amountToWithdraw) external;

  function withdrawAll() external;

  function getExpectedWithdraw() external view returns (uint256);
}
