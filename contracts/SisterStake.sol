//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/EnumerableSet.sol";

interface IPair {
    function lpToken() external returns (address);
    function token0() external returns (address);
    function token1() external returns (address);
}

interface ISisterBox {
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

    function sisters(uint256 tokenId) external view returns(Sister memory);
    // effectCoin length & info
    function tokenWhiteListLength() external view returns (uint256);
    function tokenWhiteList(uint256 index) external view returns (address);  
    // 0x23b872dd
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
    //0x548db3d8
    function burnEffectLeft(uint256 _tokenId, uint256 _burnDuration) external;
}

interface ISilMaster {

    //Pool length & info
    function poolLength() external view returns (uint256);

    function poolInfo(uint256) external view returns (address);

    function grantBuff(uint256 _pid, uint256 _index, uint256 _value, address _user) external;
}

contract SisterStake is OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;

    struct PoolInfo{
        // length must equal 2; 0: token0, 1: token1
        // address[] tokenAddr;
        address token0;
        address token1;
    }
    struct UserInfo {
        uint256 buffWeight;
        uint256 debuffWeight;
    }
    struct NftInfo {
        uint256 tokenId;
        uint256 weight;
        bool    buff;
    }
    
    // Copy Info from SilMaster
    PoolInfo[] public masterPools;
    /** @notice Copy white list from nft */
    address[] public effectCoins;
    
    ISisterBox public sisterBox;
    ISilMaster public silMaster;

    // System Globle Config: buff weight by Sister.rarityLevel
    mapping(uint256 => uint256) public buffEffectWeight;
    // System Globle Config: debuff weight by Sister.rarityLevel
    mapping(uint256 => uint256) public debuffEffectWeight;
    // variable of user 
    mapping(address => mapping(uint256 => EnumerableSet.UintSet)) private userBuffs;
    mapping(address => mapping(uint256 => EnumerableSet.UintSet)) private userDebuffs;

    mapping(address => mapping(uint256 => UserInfo)) userInfo;

    mapping(address => mapping(uint256 => uint256)) public userBuffValue;
    mapping(address => mapping(uint256 => uint256)) public userDebuffValue;
    // variable of NFT
    mapping(uint256 => uint256) public expiredAt;
    mapping(uint256 => uint256) public effectAt;
    mapping(uint256 => address) public nftUser;
    mapping(uint256 => address) public nftOriginOwner;
    mapping(uint256 => NftInfo) public nftInfo;
    mapping(uint256 => uint256) public nftPidSide;

    // ignorePool in some error Case
    mapping(address => bool) public ignorePool;

    uint256 public maxBuff;
    uint256 public maxDebuff;

    uint256 public maxBuffCount;
    uint256 public maxDebuffCount;

    uint256 public expiredGap ;

    event NftStaked(uint256 indexed _tokenId, uint256 _expiredAt);
    event WithdrawNFT(uint256 indexed _tokenId);
    
    function initialize(address _nft, address _silMaster)  initializer public {
       sisterBox = ISisterBox(_nft);
       silMaster = ISilMaster(_silMaster);

       maxBuff = 240;
       maxDebuff = 5;

       maxBuffCount = 3;
       maxDebuffCount = 2;
       expiredGap = 4 hours;
       
       __Ownable_init();
    }
    /** ===== pure tools function ===== */
    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b? b : a;
    }

    function mergePoodIdSide(uint256 pId, uint256 side) private pure  returns (uint256) {
        // sport 1048575 pool
        return  (1 << 20 | pId) << 2 | side;
    }

    function splitPoodIdSide(uint256 pIdSide) private pure returns (uint256 pId, uint256 side) {
        // if pid = 0, the value will lose
        side = pIdSide & 3; //pidSide & 0x11;
        pId  = pIdSide >> 2  & 1048575; // trime side (2 sold) and 0x1 prefix
        // return 1 << 10 << pId << 2 | side;
    }
    /** ===== base private unit function ===== */

    /**
     * @dev remve useless data from storage
     */
    function _removeStakeStorage(uint256 _pIdSide, uint256 tokenId) private {
        NftInfo storage _nftInfo = nftInfo[tokenId];
        // update NFT effectLeft
        uint256 _effectLast = block.timestamp - effectAt[tokenId];
        // zero
        sisterBox.burnEffectLeft(tokenId, _effectLast);
        // send back to NFT owner
        sisterBox.transferFrom(address(this), nftOriginOwner[tokenId], tokenId);
        // _delFromBuffArray(nftUser[tokenId], _pIdSide, _nftInfo.buff, tokenId);
        address _user = nftUser[tokenId];
        if( _nftInfo.buff) {
            userBuffs[_user][_pIdSide].remove(tokenId);
        } else {
            userDebuffs[_user][_pIdSide].remove(tokenId);
        }
        delete expiredAt[tokenId];
        delete nftUser[tokenId];
        delete nftInfo[tokenId];
        delete nftPidSide[tokenId];
        delete nftOriginOwner[tokenId];

        emit WithdrawNFT(tokenId );
    }

    function _updateUserBuffValue(address _user, uint _pIdSide, bool _buff, bool _add, uint256 _weight) private {
        UserInfo storage _userInfo = userInfo[_user][_pIdSide];

        if(_buff) {
            _add? _userInfo.buffWeight += _weight :  _userInfo.buffWeight -= _weight;
        } else {
            _add? _userInfo.debuffWeight += _weight :  _userInfo.debuffWeight -= _weight;
        }
    }

    function _withdrawByTokenId(uint256 __tokenId) private {
        NftInfo storage _nftInfo = nftInfo[__tokenId];
        uint256 buffWeight = _nftInfo.weight;
        bool _buff = _nftInfo.buff;
        uint256 _pIdSide = nftPidSide[__tokenId];
        address _user = nftUser[__tokenId];
        // remove stake via TokenId
        _removeStakeStorage(_pIdSide, __tokenId);
        //3. update UserEffect
        _updateUserBuffValue(_user, _pIdSide, _buff, false, buffWeight);
        //4. call SilMaster
        (uint256 _pId, uint256 _side) = splitPoodIdSide(_pIdSide);
        
        syncGrantBuff(_user, _pId, _side);
    }

    /**
     * @dev deal notify SilMaster buff effect
     */
    function syncGrantBuff(address _user, uint256 _pId, uint _side) private {
        ( , uint256 weight) = userEffect(_user, _pId, _side);
        silMaster.grantBuff(_pId, _side, weight , _user);
    }

     /**
     * @dev sync expried NFT, both buff&debuff array
     */
    function _syncExpiredNft(address _user, uint256 _pIdSide) private {
        uint256 accBuff     = calcuExpiredAccWeight(_user, _pIdSide, true);
        uint256 accDebuff   = calcuExpiredAccWeight(_user, _pIdSide, false);
        if(accBuff > 0) {
            _updateUserBuffValue(_user, _pIdSide, true, false, accBuff);
        } 
        if (accDebuff > 0) {
            _updateUserBuffValue(_user, _pIdSide, false, false, accDebuff);
        }
    }
    /**
     * @dev calculate acc weight 
     */
    function calcuExpiredAccWeight(address _user, uint256 _pIdSide,bool _buff) private returns (uint256) {
        uint256 accWeight;
        uint256[] memory _userBuffs =  _buff? userBuffs[_user][_pIdSide].values() : userDebuffs[_user][_pIdSide].values();
        uint256 buffLen = _userBuffs.length;
        if(buffLen > 0) {
            uint256[] memory expiredBuffes = new uint256[](buffLen);
            uint256 expiredCount = 0;
            for(uint i = 0; i < buffLen; i++) {
                uint256 _tokenId = _userBuffs[i];

                if(expiredAt[_tokenId] > 0 && expiredAt[_tokenId] <= block.timestamp) {//expired
                    expiredBuffes[expiredCount] = _tokenId;
                    expiredCount++;
                }
            }
            //remove
            for(uint i = 0; i < expiredCount; i++) {
                uint256 __tokenId = expiredBuffes[i];
                // if(__tokenId > 0) {
                    NftInfo storage _nftInfo = nftInfo[__tokenId];
                    accWeight += _nftInfo.weight;
                    _removeStakeStorage(_pIdSide, __tokenId);
                // }
            }
        }
        return accWeight;
    }
    /**
     * returns ( buff, weight)
     */
    function _stake(uint256 tokenId, uint256 _pId, uint256 _side, address _effectAddr) private returns (bool, uint256)  {
        require(_side < 2, "Side error!");
        // _sisiter Info
        ISisterBox.Sister memory _sisiter = sisterBox.sisters(tokenId);
        if (_sisiter.effectLeft < expiredGap) { 
            // expired token
            return (_sisiter.buff, 0);
        }
        PoolInfo storage poolInfo = masterPools[_pId];
        // check Token
        {   
            address _effectCoin = effectCoins[_sisiter.effectCoin];
            address _poolToken = _side == 0 ? poolInfo.token0 : poolInfo.token1;
            require(_effectCoin == _poolToken, "Effect coin not match");
        }
        address user = _effectAddr;
        uint256 pid_side = mergePoodIdSide( _pId,_side);
        // 1. size check && calucate BuffValue
        if (_sisiter.buff) {
            //size check
            if( userBuffs[user][pid_side].length() == maxBuffCount ) {
                // wight == 0, will break Stake
                return (_sisiter.buff, 0);
            }
            // require(userBuffs[user][pid_side].length() +1 <= maxBuffCount, "Buff stake outof MaxCount");
            userBuffs[user][pid_side].add(tokenId);
        } else {
            //size check
            if( userDebuffs[user][pid_side].length() == maxDebuffCount ) {
                // wight == 0, will break Stake
                return (_sisiter.buff, 0);
            }
            userDebuffs[user][pid_side].add(tokenId);
        }
        // 2. transfer from user.address
        sisterBox.transferFrom(msg.sender, address(this), tokenId);
        nftOriginOwner[tokenId] = msg.sender;
        // 3. effect Buff
        uint256 _effectWeight = _sisiter.buff? buffEffectWeight[_sisiter.rarityLevel] : debuffEffectWeight[_sisiter.rarityLevel];
        // 4. set end Time
        nftUser[tokenId] = user;
        nftPidSide[tokenId] = pid_side;
        expiredAt[tokenId] = block.timestamp + _sisiter.effectLeft;
        effectAt[tokenId] = block.timestamp;

        emit NftStaked(tokenId, block.timestamp + _sisiter.effectLeft);

        NftInfo storage _nftInfo =  nftInfo[tokenId];
        _nftInfo.tokenId = tokenId;
        _nftInfo.buff = _sisiter.buff;
        _nftInfo.weight = _effectWeight;
        return (_sisiter.buff, _effectWeight);
    }

    /** ===== external call functions ====== */

    /**
     * mutli stake
     */
    function stake(uint256[] calldata tokenIds, uint256 _pId, uint256 _side, address _effectAddr) external {

        require(tokenIds.length > 0, "Empty tokenIds");
        require(_side < 2, "Side error!");
        //check expired stake
        uint256 pid_side = mergePoodIdSide( _pId,_side);

        _syncExpiredNft(_effectAddr, pid_side);
        uint256 sumWeight;
        bool buffLock;
        for(uint i = 0; i < tokenIds.length; i++) {
            (bool buff, uint256 weight) = _stake(tokenIds[i], _pId, _side, _effectAddr);
            if(weight == 0) {
                break;
            }
            if(i == 0) {
                buffLock = buff;
            }
            require(buffLock == buff, "Buff direction must be same");
            sumWeight += weight;
        }
        require(sumWeight > 0, 'SisterStake: invalid stake');
        //update user Buff values
        _updateUserBuffValue(_effectAddr, pid_side, buffLock, true, sumWeight);
        // call silMaster to update user buff
        syncGrantBuff(_effectAddr, _pId, _side);
    }

    function checkExpiredTokens(uint256[] calldata expiredIds) external  {
       
        for(uint256 i = 0; i< expiredIds.length; i++) {
            uint256 __tokenId = expiredIds[i];
            //1. check expried Time
            if(expiredAt[__tokenId] <= expiredGap + block.timestamp) {
                //commen method
                _withdrawByTokenId(__tokenId);
                //2. delete TokenId
                // NftInfo storage _nftInfo = nftInfo[__tokenId];
                // uint256 buffWeight = _nftInfo.weight;
                // bool _buff = _nftInfo.buff;
                // uint256 _pIdSide = nftPidSide[__tokenId];

                // address _user = nftUser[__tokenId];
                // _removeStakeStorage(_pIdSide, __tokenId);
                // //3. update UserEffect
                // _updateUserBuffValue(_user, _pIdSide, _buff, false, buffWeight);
                // //4. call SilMaster
                // (uint256 _pId, uint256 _side) = splitPoodIdSide(_pIdSide);

                // syncGrantBuff(_user, _pId, _side);
            }
        }
    }
    /**
     * @notice withdrawTokens by TokenId, will reset effectBuff value
     */
    function withdrawTokens(uint256[] calldata expiredIds) external  {
       
        for(uint256 i = 0; i< expiredIds.length; i++) {
            uint256 __tokenId = expiredIds[i];
            //check origin owner
            require(nftOriginOwner[__tokenId] == msg.sender, 'Withdraw NFT only owner');
            _withdrawByTokenId(__tokenId);
        }
    }

    /** ===== system setting functions  ===== */

    function setIgnorePool(address _poolAddr, bool _ignore) external onlyOwner {
        ignorePool[_poolAddr] = _ignore;
    }

    function copyEffectCoin() external onlyOwner {
        // cppy effectCoin from SisterBox to address(this)
        delete effectCoins;
        uint256 len = sisterBox.tokenWhiteListLength();
        for(uint i = 0; i < len; i++) {
            address _token = sisterBox.tokenWhiteList(i);
            effectCoins.push(_token);
        }
    }
 
    function copyPoolInfo() external onlyOwner {

        uint cLen = masterPools.length;

        uint masterLen = silMaster.poolLength();
        if(masterLen > cLen) {
            for(uint i = cLen; i < masterLen; i ++) {
                (address silPair) = silMaster.poolInfo(i);
                if(!ignorePool[silPair]) {
                    address lpToken = IPair(silPair).lpToken();
                    address _token0 = IPair(lpToken).token0();
                    address _token1 = IPair(lpToken).token1();
                    masterPools.push(PoolInfo({
                        token0: _token0,
                        token1: _token1
                    }));
                } else {
                    masterPools.push(PoolInfo({
                        token0: silPair,
                        token1: silPair
                    }));
                }
            }
        }
    }

    function setSilMaster(address _silMaster) external onlyOwner {
        silMaster = ISilMaster(_silMaster);
    }
    // 1000 base
    function setBuffEffectWeight(uint256 _level, uint256 _weight) external onlyOwner {
        buffEffectWeight[_level] = _weight;
    }
    // 1000 base
    function setDebuffEffectWeight(uint256 _level, uint256 _weight) external onlyOwner {
        debuffEffectWeight[_level] = _weight;
    }

    function setMaxBuffCount(uint256 _maxBuffCount) external onlyOwner {
        maxBuffCount = _maxBuffCount;
    }

    function setMaxDebuffCount(uint256 _maxDebuffCount) external onlyOwner {
        maxDebuffCount = _maxDebuffCount;
    }

    function setMaxBuffWeight(uint256 _maxWeight) external onlyOwner {
        maxBuff = _maxWeight;
    }

    function setMaxDebuffWeight(uint256 _maxWeight) external onlyOwner {
        maxDebuff = _maxWeight;
    }

    function setExpiredGap(uint256 _expiredGap) external onlyOwner {
        expiredGap = _expiredGap;
    }

    /** external call view functions */

    function maxCardSlot() external view returns (uint256, uint256) {
        return (maxBuffCount, maxDebuffCount);
    }

   
    function userPoolInfo(uint256 _pId, uint256 _side, address _user) 
        external
        view
        returns (
            uint256 _userBuffCount, 
            uint256 _userDebuffCount,
            uint256 _maxBuffCount,
            uint256 _maxDebuffCount,

            uint256 _userBuffValue,
            uint256 _userDebuffValue,
            uint256 _maxBuffValue,
            uint256 _maxDebuffValue
        )
    {
        uint256 pid_side = mergePoodIdSide(_pId, _side);
        
        _userBuffCount = userBuffs[_user][pid_side].length();
        _userDebuffCount = userDebuffs[_user][pid_side].length();

        _maxBuffCount = maxBuffCount;
        _maxDebuffCount = maxDebuffCount;


        UserInfo storage _userInfo = userInfo[_user][pid_side];
        _userBuffValue = min(_userInfo.buffWeight, maxBuff);
        _userDebuffValue = min(_userInfo.debuffWeight, maxDebuff);

        _maxBuffValue = maxBuff;
        _maxDebuffValue  =  maxDebuff;
    }

    function useableCardSlot(address _user, uint256 _pId, uint256 _side) external view
        returns (uint256 buffCardSlot, uint256 debuffCardSlot)
    {
        uint256 pid_side = mergePoodIdSide(_pId, _side);
        buffCardSlot = maxBuffCount - userBuffs[_user][pid_side].length();
        debuffCardSlot =  maxDebuffCount - userDebuffs[_user][pid_side].length();
    }

    function userEffect(address _user, uint256 _pId, uint256 _side) 
        public view 
        returns (bool buff, uint256 effectWeight)
    {
        uint256 pid_side = mergePoodIdSide(_pId, _side);
        UserInfo storage _userInfo = userInfo[_user][pid_side];

        uint256 buffWeight   = min(_userInfo.buffWeight, maxBuff);
        uint256 debuffWeight = min(_userInfo.debuffWeight, maxDebuff);
        //returns
        buff = buffWeight > debuffWeight;
        effectWeight = 1000 + buffWeight - debuffWeight;
    }

    function userStakeTokenIds(address _user, uint256 _pId, uint256 _side) external view
        returns (uint256[] memory, uint256[] memory) 
    {
        uint256 pid_side = mergePoodIdSide(_pId, _side);
        uint256[] memory _userBuffs =   userBuffs[_user][pid_side].values();
        uint256[] memory _userDebuffs = userDebuffs[_user][pid_side].values();

        return (_userBuffs, _userDebuffs);
    }

}