//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SisterAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";


/// Base info definition
abstract contract SisterBase is SisterAccessControl, ERC721EnumerableUpgradeable  {

    struct Sister {
        // card round in mysteryBox
        uint256 roundIndex;
        uint256 roleIndex;
        // rarity of Role
        uint256 rarityLevel;
        //the create time
        uint256 createAt;
        // ETH, USDT et.
        // mapping in common dictionary
        uint256 effectCoin;
        // how long this card effect durateion
        uint256 effectDuration;
        // now left effect duration
        uint256 effectLeft;
        // ture buff, false debuff
        // the buff value mapping with rarityLevel
        bool buff;
        // true mysteryBox, false normal card
        bool mystery;
    }

    Sister[] public sisters;

    string private baseURI;

    function setBaseURI(string memory baseURI_) external onlyCOO {
       baseURI = baseURI_;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _createSister(
        uint256 _roundIndex,
        uint256 _roleIndex,
        uint256 _rarityLevel,
        uint256 effectCoin,
        uint256 effectDuration,
        bool _buff,
        bool _mystery,
        address _owner
    )
        internal
        returns (uint256)
    {
        Sister memory _sister = Sister({
            roundIndex: _roundIndex,
            roleIndex: _roleIndex,
            rarityLevel: _rarityLevel,
            createAt: block.timestamp,
            effectCoin: effectCoin,
            effectDuration: effectDuration,
            effectLeft: effectDuration,
            buff: _buff,
            mystery: _mystery
        });

        uint256 sisterId = sisters.length;

        sisters.push(_sister);
        _mint(_owner, sisterId);
        // _transfer(address(0), _owner, sisterId);

        return sisterId;
    }

    function createSister(
        uint256 _roundIndex,
        uint256 _roleIndex,
        uint256 _rarityLevel,
        uint256 effectCoin,
        uint256 effectDuration,
        bool _buff,
        bool _mystery,
        address _owner
    )
        external
        onlyCEO
        returns (uint256)
    {
        return _createSister(
            _roundIndex,
            _roleIndex,
            _rarityLevel,
            effectCoin,
            effectDuration,
            _buff,
            _mystery,
            _owner
        );
    }
}