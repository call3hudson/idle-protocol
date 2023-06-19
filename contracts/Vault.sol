// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IStrategy.sol';

contract Vault is ERC20, Ownable {
  IStrategy public strategy;

  event Deposited(address indexed sender, uint amountDeposited);
  event Withdrawn(address indexed sender, uint amountWithdrawn);
  event Invested(address indexed sender, uint amountInvested);
  event StrategyChanged(address indexed sender, IStrategy former, IStrategy latter);

  constructor(IStrategy strategy_) ERC20('ETH Vault', 'yETH') {
    strategy = strategy_;
  }

  function deposit() external payable {
    require(msg.value > 0, 'Ether: You must provide ether to deposit');

    uint256 amountToMint;
    if (totalSupply() == 0) amountToMint = 1e20;
    else amountToMint = (totalSupply() * msg.value) / strategy.getExpectedWithdraw();

    _mint(msg.sender, amountToMint);
    emit Deposited(msg.sender, amountToMint);
  }

  function withdraw(uint256 amountYEth_) external {
    require(amountYEth_ <= balanceOf(msg.sender), 'Ether: Invalid amount to withdraw');

    uint256 amountToReturn = (amountYEth_ * strategy.getExpectedWithdraw()) / totalSupply();

    if (amountToReturn > address(this).balance) {
      uint256 amountNeeded = amountToReturn - address(this).balance;
      if (strategy.getExpectedWithdraw() < amountNeeded) revert('Insufficient amount to withdraw');
      strategy.withdraw(amountNeeded);
    }

    (bool success, ) = address(strategy).call{ value: amountToReturn }('');
    if (success) {
      _burn(msg.sender, amountToReturn);
    }

    emit Withdrawn(msg.sender, amountToReturn);
  }

  function invest() external onlyOwner {
    uint256 amount = (address(this).balance * 9) / 10;
    strategy.mint{ value: amount }();
    emit Invested(msg.sender, amount);
  }

  function changeStrategy(IStrategy strategy_) external onlyOwner {
    strategy.withdrawAll();
    IStrategy former = strategy;
    strategy = strategy_;
    emit StrategyChanged(msg.sender, former, strategy);
  }
}
