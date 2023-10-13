// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@chainlink/contracts/src/v0.8/ChainlinkClient.sol';
import '@chainlink/contracts/src/v0.8/ConfirmedOwner.sol';
import '../interfaces/IAPIConsumer.sol';

/**
 * @author  Huang.
 * @title   External API call for Idle token price.
 * @dev     Retrieve price value from https://api.harvest.finance/vaults?key=41e90ced-d559-4433-b390-af424fdc76d6.
 * @notice  Strategies can verify the spot price with oracle price.
 */
contract APIConsumer is ChainlinkClient, IAPIConsumer {
  using Chainlink for Chainlink.Request;

  // Stored oracle price
  uint256 private _value;

  // Job id and LINK token to be paid for single request
  bytes32 private _jobID;
  uint256 private _fee;

  // Emitted when the stored value updates
  event RequestPrice(bytes32 indexed requestId, uint256 value);

  constructor() {
    setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
    setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD);

    // Randomly generated job id
    // _jobID = 'ca98366cc7314956b8c012c72f05aeeb';

    // It's good to keep the job id as the api handle
    _jobId = '41e90ced-d559-4433-b390-af424fdc76d6';

    // Dedicated LINK token per each request
    // _fee = (1 * LINK_DIVISIBILITY) / 10;
    _fee = (1 * LINK_DIVISIBILITY) / 10;

    // Initial value
    _value = 1028200749733226351;
  }

  /**
   * @notice  Requests the oracle price from external API.
   * @dev     Create job and append two tasks.
   * @return  requestId  Corresponding request id for further respond.
   */
  function requestPrice() public returns (bytes32 requestId) {
    Chainlink.Request memory req = buildChainlinkRequest(
      _jobID,
      address(this),
      this.fulfill.selector
    );

    req.add('get', 'https://api.harvest.finance/vaults?key=41e90ced-d559-4433-b390-af424fdc76d6');
    req.add('path', 'eth,WETH');

    return sendChainlinkRequest(req, _fee);
  }

  /**
   * @notice  Callback function.
   * @dev     Modifies the stored oracle price.
   * @param   requestedId_  Corresponding requested id.
   * @param   vaule_  Oracle price.
   */
  function fulfill(
    bytes32 requestedId_,
    uint256 vaule_
  ) public recordChainlinkFulfillment(requestedId_) {
    emit RequestPrice(requestedId_, vaule_);
    _value = vaule_;
  }

  /**
   * @notice  External adapter for retrieving the oracle price.
   * @dev     Returns stored price.
   * @return  value Stored price.
   */
  function getValue() external view returns (uint256 value) {
    return _value;
  }
}
