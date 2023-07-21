// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IVGov.sol';

contract VGov is IVGov, ERC20, Ownable {
  constructor() ERC20('VGov', 'VGV') {}
    
  function mint(address target_, uint256 amount_) external onlyOwner {
    _mint(target_, amount_);
  }

  function burn(address target_, uint256 amount_) external onlyOwner {
    _burn(target_, amount_);
  }
}
