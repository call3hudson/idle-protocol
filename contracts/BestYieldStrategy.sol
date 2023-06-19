// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IStrategy.sol';
import './interfaces/IWETH.sol';
import './interfaces/IIdleToken.sol';

contract BestYieldStrategy is IStrategy {
  using SafeERC20 for IERC20;

  mapping(address => uint256) private depositedAmount;

  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant YIELD = 0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80;

  event Minted(address indexed sender, uint amountDeposited);
  event Withdrawn(address indexed sender, uint amountWithdrawn);
  event WithdrawnAll(address indexed sender, uint amountWithdrawn);

  function mint() external payable {
    IWETH(WETH).deposit{ value: msg.value }();
    IIdleToken(YIELD).rebalance();

    uint256 supply = IERC20(WETH).balanceOf(address(msg.sender));
    IERC20(WETH).safeApprove(YIELD, supply);
    uint256 amountMinted = IIdleToken(YIELD).mintIdleToken(supply, true, address(0));

    depositedAmount[address(msg.sender)] += amountMinted;
    emit Minted(msg.sender, msg.value);
  }

  function withdraw(uint256 amountToWithdraw_) external {
    require(amountToWithdraw_ > 0, 'Strategy: Invalid amount');

    uint256 tokenPrice = IIdleToken(YIELD).tokenPrice();
    uint256 idleAmount = (amountToWithdraw_ / tokenPrice) + 1;

    require(depositedAmount[address(msg.sender)] >= idleAmount, 'Strategy: Insufficient amount');

    uint256 underlyingAmount = IIdleToken(YIELD).redeemIdleToken(idleAmount);
    require(underlyingAmount >= amountToWithdraw_, 'Strategy: Slippage happened');

    IWETH(WETH).withdraw(amountToWithdraw_);
    payable(msg.sender).transfer(amountToWithdraw_);

    depositedAmount[address(msg.sender)] -= idleAmount;
    emit Withdrawn(msg.sender, amountToWithdraw_);
  }

  function withdrawAll() external {
    require(depositedAmount[address(msg.sender)] > 0, 'Strategy: Provide underlying token first');

    uint256 redeemedAmount = IIdleToken(YIELD).redeemIdleToken(
      depositedAmount[address(msg.sender)]
    );
    IWETH(WETH).withdraw(redeemedAmount);
    payable(msg.sender).transfer(redeemedAmount);

    depositedAmount[address(msg.sender)] = 0;
    emit WithdrawnAll(msg.sender, redeemedAmount);
  }

  function getExpectedWithdraw() external view returns (uint256) {
    uint256 tokenPrice = IIdleToken(YIELD).tokenPrice();
    uint256 supply = depositedAmount[address(msg.sender)];
    return supply * tokenPrice;
  }
}
