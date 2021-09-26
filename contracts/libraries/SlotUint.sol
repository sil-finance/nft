//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;


library SlotUint {
  
  // uint256 public constant STEP = 20;

  function setSlot(uint256 content, uint256 _solt, uint256 _v) internal pure returns (uint256) {
    // content = _v2 << (STEP * _solt) | (content) ; // >> STEP << STEP 
    uint256 maskCode = 1048575;
    maskCode = ~(maskCode << (20 * _solt));
  
    content &= maskCode;
    content |= _v << (20 * _solt);

    return content;
  }
  
  function slotAt(uint256 content, uint256 _solt) internal pure returns(uint256) {
      uint256 maskCode = 1048575;
      return  content >> (20 * _solt) & maskCode;
  }
}
