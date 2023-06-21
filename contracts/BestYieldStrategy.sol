// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './interfaces/IStrategy.sol';
import './interfaces/IWETH.sol';
import './interfaces/IIdleToken.sol';

/**
 * @author  Huang.
 * @title   BestYieldStrategy.
 * @dev     Provide portable and secure APIs for interacting with Idle protocol. Designed to avoid complex adoption for different strategies
 * @notice  Any contracts can store this strategy interface and earn interests from the Idle protocol.
 */

contract BestYieldStrategy is IStrategy, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // Records how much did every depositor deposit
  mapping(address => uint256) private depositedAmount_;

  // Deployed addresses of WETH and YIELD in ethereum mainnet
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant YIELD = 0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80;

  // Occured when corresponding action triggered
  event Minted(address indexed sender, uint amountDeposited, uint idleMinted);
  event Withdrawn(address indexed sender, uint amountWithdrawn, uint idleWithdrawn);
  event WithdrawnAll(address indexed sender, uint amountWithdrawn, uint idleWithdrawn);

  // !Important : Since strategy receives ether when withdrawing from WETH
  receive() external payable {}

  /**
   * @notice  Sender sends eth and registered to be a liquidity provider.
   * @dev     Convert ether to WETH, stores the amount deposited and move WETH to the Idle Protocol.
   */
  function mint() external payable {
    // Check if no ether provided
    require(msg.value > 0, 'Strategy: Invalid Ether amount');

    // Deposit eth to WETH contract and gain corresponding WETH
    IWETH(WETH).deposit{ value: msg.value }();

    // Get the remaining(including division truncate happened in withdraw) WETH to Idle Protocol
    uint256 supply = IERC20(WETH).balanceOf(address(this));

    // To let protocol handling the WETH, we need to approve it
    IERC20(WETH).safeApprove(YIELD, supply);
    uint256 amountMinted = IIdleToken(YIELD).mintIdleToken(supply, true, address(0));

    // Update records as well
    depositedAmount_[msg.sender] += amountMinted;
    emit Minted(msg.sender, msg.value, amountMinted);
  }

  /**
   * @notice  Depositors withdraw certain amount of stored ether.
   * @dev     Redeem WETH from Idle Protocol and withdraw WETH to ether. Update record as well.
   * @param   amountToWithdraw_  Amount of ether need for msg.sender.
   */
  function withdraw(uint256 amountToWithdraw_) external {
    // Check the validation
    require(amountToWithdraw_ > 0, 'Strategy: Invalid amount');

    // Get the current price to buy and figure out how much idle token to be burned
    uint256 tokenPrice = IIdleToken(YIELD).tokenPrice();
    uint256 idleAmount = ((amountToWithdraw_ * 1e18) / tokenPrice) + 1;

    // Check if the sender has enough idle token for redeeming
    require(depositedAmount_[msg.sender] >= idleAmount, 'Strategy: Insufficient amount');

    // Redeem idle token and get the actual amount withdrawn
    uint256 amountWithdrawn = _withdrawFromIdle(msg.sender, idleAmount);

    emit Withdrawn(msg.sender, amountWithdrawn, idleAmount);
  }

  /**
   * @notice  Depositors withdraw the whole amount of stored ether.
   * @dev     Redeem WETH from Idle Protocol and withdraw WETH to ether. Update record as well.
   */
  function withdrawAll() external {
    // Check if sender is provider
    require(depositedAmount_[msg.sender] > 0, 'Strategy: Provide underlying token first');

    // Redeem out the whole idle token stored in the sender address
    uint256 idleAmount = depositedAmount_[msg.sender];
    uint256 amountWithdrawn = _withdrawFromIdle(msg.sender, idleAmount);

    emit WithdrawnAll(msg.sender, amountWithdrawn, idleAmount);
  }

  /**
   * @notice  Depositors get the maximum amount that they receive.
   * @dev     Get the current Idle token price and multiplies to the supply.
   * @return  uint256  Expected amount to be withdrawn.
   */
  function getExpectedWithdraw() external view returns (uint256) {
    // Get the currrent token price to be withdrawn and multiplies to the supply
    uint256 tokenPrice = IIdleToken(YIELD).tokenPrice();
    uint256 supply = depositedAmount_[msg.sender];
    return (supply * tokenPrice) / 1e18;
  }

  /**
   * @notice  Actual routine for withdrawing ether from Idle.
   * @dev     Redeem underlying WETH and convert to ether.
   * @param   sender_  Sender wanted to withdraw assets.
   * @param   idleAmount_  Amount of Idle token to be redeemed.
   * @return  uint256  Redeemed WETH amount.
   */
  function _withdrawFromIdle(
    address sender_,
    uint256 idleAmount_
  ) internal nonReentrant returns (uint256) {
    // Redeem idle token from the Idle Protocol and receive WETH to the Strategy address
    uint256 redeemedAmount = IIdleToken(YIELD).redeemIdleToken(idleAmount_);

    // Withdraw WETH to ether - receive() function needed
    IWETH(WETH).withdraw(redeemedAmount);

    // Transfer withdrawn eth to the sender
    payable(sender_).transfer(redeemedAmount);

    // Update records as well
    depositedAmount_[sender_] -= idleAmount_;

    return redeemedAmount;
  }
}
