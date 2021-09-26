//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SisterBase.sol";

/// Base info definition
abstract contract SisterExpand is SisterBase  {

    /// Level list config
    /// Top level has a height weight for buff|debugg
    enum RarityLevel{
        LEGEND,
        EPIC,
        RATE,
        UNCOMMON,
        ORDINARY
    }
    /// Role Info
    /// List information, will decide showing view in frontend
    struct SisterRole {
      string name;
      string artist;
      string uri;
    }
    // All roles
    SisterRole[] public roles;
    // Token address list
    address[] public tokenWhiteList;
    // Key: address Value: tokenWhiteList.index
    mapping(address => uint256) public tokenWhiteIndex;
        // key: RarityLevel.index, value: arrays of SisterRole.index
    mapping(uint256 => mapping(uint256 => uint256[])) levelRoles;

    event RoleCreated(uint256 indexed _index, string _name, string _artist);
    event AddToken(address indexed _token, uint256 _index);
    event BurnEffectDuration(uint256 indexed _tokenId, uint256 _burnDuration);
    event SyntheticCard(address indexed _to, uint256 indexed _tokenId);

    function levelRoleSize(uint256 _round , uint256 _level) external view  returns(uint256){
        return levelRoles[_round][_level].length;
    }
    
    function setLevelRole(uint256 _round, uint256 _level, uint256[] calldata _roles) internal {

        levelRoles[_round][_level] = _roles;
    }

    function addWhiteToken(address _token) external onlyCOO {
        require(tokenWhiteIndex[_token] == 0);

        uint256 _index = tokenWhiteList.length;
        tokenWhiteIndex[_token] = tokenWhiteList.length;

        tokenWhiteList.push(_token);
        emit AddToken(_token, _index);
    }

    function craeteRole(
        string memory _name,
        string memory _artist,
        string memory _uri
    ) 
        external 
        onlyCOO
    {
        roles.push(SisterRole( {
            name: _name,
            artist: _artist,
            uri: _uri
        }));
        emit RoleCreated(roles.length - 1, _name, _artist);
    }


    /// @notice MintContract (which effect SIL mining via NTF) can reduce effectLeft
    /// @dev call when mint overtime
    function burnEffectLeft(uint256 _tokenId, uint256 _burnDuration)
        external
        onlyMint
    {
        Sister storage sister = sisters[_tokenId];
        if(sister.effectLeft > _burnDuration) {
            sister.effectLeft = sister.effectLeft - _burnDuration;
        } else {
            sister.effectLeft = 0;
        }
        emit BurnEffectDuration(_tokenId, _burnDuration);
    }

    function syntheticCard(
        uint256 _roleIndex,
        uint256 _rarityLevel,
        uint256 effectCoin,
        uint256 effectDuration,
        bool _buff,
        address _to,
        uint256[] calldata partIds // partIds synthetic one height level card
    )
        external
        onlySynt
        returns (uint256 tokenId)
    {
        uint256 len = partIds.length;
        require(len > 1, "SisterBase:: synthetic parts must gt 1");

        tokenId = _createSister(
            ~uint(0), //constant
            _roleIndex,
            _rarityLevel,
            effectCoin,
            effectDuration,
            _buff,
            false,
            _to
        );
        for(uint256 i = 0; i < len; i++ ){
            _burn(partIds[i]);
        }
        emit SyntheticCard(_to, tokenId);
    }

    function roleLength() public view returns (uint256) {
        return roles.length;
    }

    function tokenWhiteListLength() public view returns (uint256) {
        return tokenWhiteList.length;
    }
}