//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SisterExpand.sol";
import "./interfaces/ISyntheticScience.sol";
import "./libraries/SlotUint.sol";


contract SisterBox is SisterExpand {
    using SlotUint for uint256;

    struct Box {
        // rarityLevel counts values splited and saved in uint256
        // each value saved in a 20-length bits slot 
        uint256 rarityLevelInfo;
        uint256 rarityLevelShadow;
    
        uint256 buffRate;           // 1000-based buff point weight /1000
        uint256 effectDurations;    // slotAt(0) arrayLength, slotAt(1),value0, slotAt(1),value1 and so on...
        uint256 silPrice;           // sil price per MysterBox
        //how many bidable card left
        uint256 totalLeft;          // how many bidable MysteryBox left
        uint256 mysteryLeft;        // how many Box still mystery, not exposed
        uint256 closeAt;            //  cannot bid box after closeAt
    }
    //Bid via SIL
    address silToken;
    address airdroperAddr;

    ISyntheticScience public syntheticScience;

    Box[] public boxes;
    //Current Round
    uint256 public currentRound;
    // Lock period befor exposeMysteryBox()
    uint256 public mysteryPeriod;
    //if mysteryBox ready
    mapping(uint256 => bool) boxReady;

    event MysteryBox(address indexed _to, uint256 indexed _tokenId, uint256 _round);
    event CreateBox(uint256 _round);
    event AirdroperAddress(address indexed airdroper);
    event MysteryPeriod(uint256 mysteryPeriod);

    modifier onlyAirdroper(){
        require(msg.sender == airdroperAddr, "Sender is not airdroper");
        _;
    }

    function initialize(address _silToken, address _coe )  initializer public {
        silToken = _silToken;

        ceoAddress = _coe;
        cfoAddress = _coe;
        cooAddress = _coe;

        __ERC721_init("SIL NFT", "SILNFT");
    }

    function setSyntheticScience(address _impl) external onlyCEO {
        syntheticScience = ISyntheticScience(_impl);
    }
    // set globle mysterPeriod
    function setMysteryPeriod(uint256 _period) external onlyCOO {
        mysteryPeriod = _period;
        emit MysteryPeriod(_period);
    }

    function setAirdoper(address _apidroper) external onlyCOO {
        airdroperAddr = _apidroper;
        emit AirdroperAddress(_apidroper);
    }

    function setBoxRoles(
        uint256 _round,
        uint256[] calldata _legendRoles,
        uint256[] calldata _eoicRoles,
        uint256[] calldata _rateRoles,
        uint256[] calldata _uncommonRoles,
        uint256[] calldata _ordubaryRoles
    )
        external 
        onlyCOO
    {
        require(!boxReady[_round], "Box had initialized");
        setLevelRole(_round, 0 ,_legendRoles);
        setLevelRole(_round, 1 ,_eoicRoles);
        setLevelRole(_round, 2 ,_rateRoles);
        setLevelRole(_round, 3 ,_uncommonRoles);
        setLevelRole(_round, 4 ,_ordubaryRoles);

        boxReady[_round] = true;
    }

    function publishBox(
        uint256 _countLegend,
        uint256 _countEoic,
        uint256 _countRate,
        uint256 _countUncommon,
        uint256 _countOrdubary,

        uint256 _buffRate,
        uint256 _durationRate,
        uint256 _silPrice,
        uint256 _closeAt
    )
        external
        onlyCOO
    {
        uint256 slotData = _countLegend;
        slotData = slotData.setSlot(1, _countEoic);
        slotData = slotData.setSlot(2, _countRate);
        slotData = slotData.setSlot(3, _countUncommon);
        slotData = slotData.setSlot(4, _countOrdubary);

        // check _durationRate
        checkDurationRate(_durationRate);
        
        uint256 totalNum = _countLegend + _countEoic + _countRate + _countUncommon + _countOrdubary;
        Box memory box = Box({
           rarityLevelInfo: slotData,
           rarityLevelShadow: slotData,
           buffRate: _buffRate,
           effectDurations: _durationRate,
           silPrice: _silPrice,
           totalLeft: totalNum,
           mysteryLeft: totalNum,
           closeAt: _closeAt
        });

        currentRound = boxes.length;
        boxes.push(box);

        emit CreateBox(currentRound);
    }

    function checkDurationRate(uint256 _rate) private pure  {
        uint256 len = _rate.slotAt(0);
        require(len > 0, "SisterBox:: effectRate size cannot be 0");
        for(uint i = 1; i <= len; i++) {
            require(_rate.slotAt(i) > 0, "SisterBox:: effectRate cannot be 0");
        }
    }

    function airdropBox(uint256 _round, uint256 _count, address _to)
        external
        whenNotPaused
        onlyAirdroper
        returns(uint256[] memory)
    {
        
        uint256[] memory tokenIds = _bidBox(_round, _count, _to);
        return tokenIds;
    }

    // @notice User buy box
    function bidBox(uint256 _round, uint256 _count, address _to)
        external
        whenNotPaused
        returns (uint256[] memory) 
    {
        Box storage box = boxes[_round];

        uint256[] memory tokenIds = _bidBox(_round, _count, _to);   

        safeTransferFrom(silToken, msg.sender, address(this), box.silPrice * tokenIds.length);

        return tokenIds;
    }

    //data
    function _bidBox(uint256 _round, uint256 _count, address _to) private returns(uint256[] memory) {
        require(boxReady[_round], "Box not initialize");
        Box storage box = boxes[_round];
        require(box.closeAt >= block.timestamp, "Mystery shop has closed");
        require(box.totalLeft > 0, "Sell out");

        if(_count > box.totalLeft) {
            _count = box.totalLeft;
        }
        uint256[] memory tokenIds = new uint256[](_count);
        for(uint i=0; i < _count; i++) {
            uint256 _tokenId = _createMysteryBox(_round, _to);
            // box.totalLeft -= 1;
            tokenIds[i] = _tokenId;
            emit MysteryBox(_to, _tokenId, _round);
        }
        box.totalLeft -= _count;

        return tokenIds;
    }

    function _createMysteryBox(uint256 _round, address _to) private returns(uint256 _tokenId) {
        _tokenId = _createSister(_round, 0, 0, 0, 0, false, true, _to);
    }

    function exposeMysteryBox(uint256 tokenId) external whenNotPaused {
        require(ownerOf(tokenId) == msg.sender, "Not owner");

        Sister storage _sisiter = sisters[tokenId];
        require(_sisiter.mystery, "exposeMysteryBox:: had exposed");

        Box storage box = boxes[_sisiter.roundIndex];
        // require( block.timestamp >= box.closeAt + mysteryPeriod , "Card still in mystery period"); 
        
        uint256 proof = syntheticScience.syntheticProof();
        // === rarity Level calclate  === 
        // role level, count limit. if currentLevl sell out,down
        uint256 _rarityLevelInfo = box.rarityLevelInfo;
        RarityLevel level =  _calcRarityLevel(proof, box.mysteryLeft, _rarityLevelInfo);
        uint256 _rarityLevel = uint256(level);
        /// Box:: update totalLeft
        box.mysteryLeft -= 1;
        /// Box:: update levelInfo
        box.rarityLevelInfo = _rarityLevelInfo.setSlot(_rarityLevel, _rarityLevelInfo.slotAt(_rarityLevel) - 1);

        // === role index calclate, relate with rarityLevel  === */
        uint256[] memory roles = levelRoles[_sisiter.roundIndex][_rarityLevel];
        uint256 _roleIndex = roles[calcWithProof(proof, roles.length)];
        // === coin calclate, no limit  === */
        uint256 _effectCoinIndex = calcWithProof(proof, tokenWhiteListLength());
        // random 1000-based
        uint256 random_base_1000 = calcWithProof(proof, 1000);
        // buff =  1000 based < buffRate
        bool _buff = random_base_1000 <= box.buffRate;
        //=== _effectDurationIndex calclate, random in   === */
        uint256 _effectDurationIndex = calcWithProof(random_base_1000,  box.effectDurations.slotAt(0)) + 1;
        uint256 _effectDuration = box.effectDurations.slotAt(_effectDurationIndex);
        ///updateValue value
        _sisiter.roleIndex = _roleIndex;
        _sisiter.rarityLevel = _rarityLevel;
        _sisiter.effectCoin = _effectCoinIndex;
        _sisiter.roleIndex = _roleIndex;
        _sisiter.effectDuration = _effectDuration;
        _sisiter.effectLeft = _effectDuration;
        _sisiter.buff = _buff;
        _sisiter.mystery = false;
    }
    //Query BoxExposableAt
    function boxExposableAt(uint256 _tokenId) external view returns(uint256) {
        require(_tokenId < boxes.length, "tokenId unavailable" );
        Box storage _box = boxes[_tokenId];
        return _box.closeAt + mysteryPeriod;
    }

    function _calcRarityLevel(uint256 _randomProof, uint256 _randomRange, uint256 _values) private pure returns(RarityLevel) {
        uint256 len = uint256(RarityLevel.ORDINARY);
        uint256 leftCount;

        _randomProof = _randomProof % _randomRange;

        for(uint256 i = 0; i <=len; i++) {
            uint256 index = len - i ;
            leftCount += _values.slotAt(index);
            if(leftCount > _randomProof){
                return RarityLevel(index);
            }
        }
        return RarityLevel.ORDINARY;
    }

    //pure
    function calcWithProof(uint256 _proof, uint256 _mode) private pure  returns(uint256) {
        return _proof % _mode;
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SilsterBox: TRANSFER_FROM_FAILED');
    }

    function withdrawToken(address token, address _to, uint256 _value) external onlyCFO {

        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, _to, _value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Box: TRANSFER_FAILED');
    }
}