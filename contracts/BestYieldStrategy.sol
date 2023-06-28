// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './interfaces/IStrategy.sol';
import './interfaces/IWETH.sol';
import './interfaces/IIdleToken.sol';
import './interfaces/IAPIConsumer.sol';

/**
 * @author  Huang.
 * @title   BestYieldStrategy.
 * @dev     Provide portable and secure APIs for interacting with Idle protocol. Designed to avoid complex adoption for different strategies
 * @notice  Any contracts can store this strategy interface and earn interests from the Idle protocol.
 */

contract BestYieldStrategy is IStrategy, ReentrancyGuard, Ownable {
  using SafeERC20 for IERC20;

  // User of BestYieldStrategy - Vault
  address public user;
  address public oracle;

  // Deployed addresses of WETH and YIELD in ethereum mainnet
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant YIELD = 0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80;

  // Maximum slippage percent that could be ignored
  uint256 public constant SLIPPAGE = 5;

  // Virtual prices
  uint256 public virtualPrice = 0;

  // Occured when corresponding action triggered
  event Minted(address indexed sender, uint amountDeposited, uint idleMinted);
  event Withdrawn(address indexed sender, uint amountWithdrawn, uint idleWithdrawn);
  event WithdrawnAll(address indexed sender, uint amountWithdrawn, uint idleWithdrawn);
  event NewUser(address indexed sender, address indexed former, address indexed user);
  event NewOracle(address indexed sender, address indexed former, address indexed user);

  /**
   * @notice  If another user tries to call function with this modifier, reverts.
   * @dev     Only user can pass in this modifier.
   */
  modifier onlyUser() {
    require(msg.sender == user, 'Strategy: Only user can call this function');
    _;
  }

  // !Important : Since strategy receives ether when withdrawing from WETH
  receive() external payable {
    require(msg.sender == WETH, 'Strategy: Only WETH can send ether');
  }

  /**
   * @notice  Sender sends eth and registered to be a liquidity provider.
   * @dev     Convert ether to WETH, stores the amount deposited and move WETH to the Idle Protocol.
   */
  function mint() external payable onlyUser {
    // Check if no ether provided
    require(msg.value > 0, 'Strategy: Invalid Ether amount');

    // Check the validity of spot price
    uint256 tokenPrice = IIdleToken(YIELD).tokenPrice();
    require(validatePrice(tokenPrice), 'Strategy: Tolerance rate exceeded');

    // Deposit eth to WETH contract and gain corresponding WETH
    IWETH(WETH).deposit{ value: msg.value }();

    // Get the remaining(including division truncate happened in withdraw) WETH to Idle Protocol
    uint256 supply = IERC20(WETH).balanceOf(address(this));

    // To let protocol handling the WETH, we need to approve it
    IERC20(WETH).safeApprove(YIELD, supply);
    uint256 amountMinted = IIdleToken(YIELD).mintIdleToken(supply, true, address(0));

    emit Minted(msg.sender, msg.value, amountMinted);
  }

  /**
   * @notice  Depositors withdraw certain amount of stored ether.
   * @dev     Redeem WETH from Idle Protocol and withdraw WETH to ether. Update record as well.
   * @param   amountToWithdraw_  Amount of ether need for msg.sender.
   */
  function withdraw(uint256 amountToWithdraw_) external onlyUser {
    // Check the validation
    require(amountToWithdraw_ > 0, 'Strategy: Invalid amount');

    // Get the current price to buy and figure out how much idle token to be burned
    uint256 tokenPrice = IIdleToken(YIELD).tokenPrice();
    require(validatePrice(tokenPrice), 'Strategy: Tolerance rate exceeded');

    uint256 idleAmount = ((amountToWithdraw_ * 1e18) / tokenPrice) + 1;

    // Check if the sender has enough idle token for redeeming
    require(IERC20(YIELD).balanceOf(address(this)) >= idleAmount, 'Strategy: Insufficient amount');

    // Redeem idle token from the Idle Protocol and receive WETH to the Strategy address
    uint256 redeemedAmount = IIdleToken(YIELD).redeemIdleToken(idleAmount);
    assert(redeemedAmount >= amountToWithdraw_);

    // Withdraw WETH to ether - receive() function needed
    IWETH(WETH).withdraw(redeemedAmount);

    // Transfer withdrawn eth to the sender
    (bool success, ) = (msg.sender).call{ value: amountToWithdraw_ }('');
    require(success, 'Strategy: Transfer failed.');

    emit Withdrawn(msg.sender, amountToWithdraw_, idleAmount);
  }

  /**
   * @notice  Depositors withdraw the whole amount of stored ether.
   * @dev     Redeem WETH from Idle Protocol and withdraw WETH to ether. Update record as well.
   */
  function withdrawAll() external nonReentrant onlyUser {
    // Check if sender is provider
    require(IERC20(YIELD).balanceOf(address(this)) > 0, 'Strategy: Provide underlying token first');

    // Check the validity of spot price
    uint256 tokenPrice = IIdleToken(YIELD).tokenPrice();
    require(validatePrice(tokenPrice), 'Strategy: Tolerance rate exceeded');

    // Redeem out the whole idle token stored in the sender address
    uint256 idleAmount = IERC20(YIELD).balanceOf(address(this));

    // Redeem idle token from the Idle Protocol and receive WETH to the Strategy address
    uint256 redeemedAmount = IIdleToken(YIELD).redeemIdleToken(idleAmount);

    // Withdraw WETH to ether - receive() function needed
    IWETH(WETH).withdraw(redeemedAmount);

    // Transfer withdrawn eth to the sender
    (bool success, ) = (msg.sender).call{ value: redeemedAmount }('');
    require(success, 'Strategy: Transfer failed.');

    emit WithdrawnAll(msg.sender, redeemedAmount, idleAmount);
  }

  /**
   * @notice  Depositors get the maximum amount that they receive.
   * @dev     Get the current Idle token price and multiplies to the supply.
   * @return  uint256  Expected amount to be withdrawn.
   */
  function getExpectedWithdraw() external view onlyUser returns (uint256, uint256, uint256) {
    // Get the currrent token price to be withdrawn and multiplies to the supply
    uint256 spotPrice = IIdleToken(YIELD).tokenPrice();
    uint256 oraclePrice = IAPIConsumer(oracle).getValue();

    uint256 totalSupply = IERC20(YIELD).balanceOf(address(this));

    return (
      (spotPrice * totalSupply) / 1e18,
      (oraclePrice * totalSupply) / 1e18,
      (virtualPrice * totalSupply) / 1e18
    );
  }

  /**
   * @notice  Set new strategy user.
   * @dev     Owner changes new user.
   * @param   user_  Address to be set.
   */
  function setUser(address user_) external onlyOwner {
    address former = user;
    user = user_;
    emit NewUser(msg.sender, former, user);
  }

  /**
   * @notice  Set new oracle.
   * @dev     Owner changes new oracle.
   * @param   oracle_  Address to be set.
   */
  function setOracle(address oracle_) external onlyOwner {
    address former = oracle;
    oracle = oracle_;
    emit NewOracle(msg.sender, former, oracle);
  }

  /**
   * @notice  Returns if spot price was not forged.
   * @dev     Check if the spot price is within the range of oracle price with tolerance slippage percent.
   * @param   price_  Target price.
   * @return  bool  Returns true if validated.
   */
  function validatePrice(uint256 price_) internal returns (bool) {
    // Get the oracle price
    uint256 oraclePrice = IAPIConsumer(oracle).getValue();
    if (virtualPrice == 0) virtualPrice = oraclePrice;

    // In case of oracle price is bigger than spot price
    if (oraclePrice > price_ && ((price_ * (100 + SLIPPAGE)) / 100 < oraclePrice)) return false;

    // Otherwise
    if (oraclePrice < price_ && ((oraclePrice * (100 + SLIPPAGE)) / 100 < price_)) return false;

    // In case of virtual price is bigger than spot price
    if (virtualPrice > price_ && ((price_ * (100 + SLIPPAGE)) / 100 < virtualPrice)) return false;

    // Otherwise
    if (virtualPrice < price_ && ((virtualPrice * (100 + SLIPPAGE)) / 100 < price_)) return false;

    // Update virtual price as well
    virtualPrice = price_;

    return true;
  }
}
