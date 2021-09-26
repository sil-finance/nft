//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISyntheticScience {

    function isSyntheticScience() external pure returns (bool);

    //1000-Based
    function syntheticProof() external view returns (uint256);
}
