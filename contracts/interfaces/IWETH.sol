// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IWETH {
  function deposit() external payable;

  function withdraw(uint wad) external payable;

  function totalSupply() external returns (uint);
}
