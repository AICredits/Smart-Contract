pragma solidity ^0.4.18;

import './fund/ICrowdsaleFund.sol';
import './token/IERC20Token.sol';
import './token/TransferLimitedToken.sol';
import './token/LockedTokens.sol';
import './ownership/Ownable.sol';
import './Pausable.sol';


contract RenitheumDAICO is Ownable, SafeMath, Pausable {
    enum TelegramBonusState {
        Unavailable,
        Active,
        Applied
    }

    uint256 public constant TG_BONUS_NUM = 3;
    uint256 public constant TG_BONUS_DENOM = 100;

    uint256 public constant ETHER_MIN_CONTRIB = 0.1 ether;
    uint256 public constant ETHER_MAX_CONTRIB = 10 ether;

    uint256 public constant ETHER_MIN_CONTRIB_PRIVATE = 100 ether;
    uint256 public constant ETHER_MAX_CONTRIB_PRIVATE = 3000 ether;

    uint256 public constant ETHER_MIN_CONTRIB_USA = 1 ether;
    uint256 public constant ETHER_MAX_CONTRIB_USA = 100 ether;

    uint256 public constant SOFT_CAP = 5000 ether;

    uint256 public constant SALE_START_TIME = 1520413200; // 07.03.2018 09:00:00 UTC
    uint256 public constant SALE_END_TIME = 1523091600; // 07.04.2018 09:00:00 UTC

    uint256 public constant BONUS_WINDOW_1_END_TIME = SALE_START_TIME + 2 days;
    uint256 public constant BONUS_WINDOW_2_END_TIME = SALE_START_TIME + 7 days;
    uint256 public constant BONUS_WINDOW_3_END_TIME = SALE_START_TIME + 14 days;
    uint256 public constant BONUS_WINDOW_4_END_TIME = SALE_START_TIME + 21 days;

    uint256 public constant HARD_CAP_MERGE_TIME = SALE_START_TIME + 15 days;
    uint256 public constant MAX_CONTRIB_CHECK_END_TIME = SALE_START_TIME + 7 days;

    uint256 public tokenPriceNum = 0;
    uint256 public tokenPriceDenom = 0;
    
    TransferLimitedToken public token;
    ICrowdsaleFund public fund;
    LockedTokens public lockedTokens;

    mapping(address => bool) public whiteList;
    mapping(address => bool) public privilegedList;
    mapping(address => TelegramBonusState) public telegramMemberBonusState;
    mapping(address => uint256) public userTotalContributed;

    address public RTHTokenWallet;
    address public referralTokenWallet;
    address public advisorsTokenWallet;
    address public companyTokenWallet;
    address public reserveTokenWallet;
    address public bountyTokenWallet;

    uint256 public totalWorldEtherContributed = 0;
    uint256 public totalUSAEtherContributed = 0;

    uint256 public rawTokenSupply = 0;

    // RTH
    IERC20Token public RTHToken;
    uint256 public RTH_HARD_CAP = 300000 ether; // 300K RTH
    uint256 public RTH_MIN_CONTRIB = 1000 ether; // 1K RTH
    mapping(address => uint256) public RTHContributions;
    uint256 public totalRTHContributed = 0;
    uint256 public constant RTH_tokenPriceNum = 50; // Price will be set right before Token Sale
    uint256 public constant RTH_tokenPriceDenom = 1;
    uint256 public hardCap = 0; // World hard cap will be set right before Token Sale
    uint256 public USAHardCap = 0; // USA hard cap will be set right before Token Sale
    bool public RTHRefundEnabled = false;

    event LogContribution(address contributor, uint256 amountWei, uint256 tokenAmount, uint256 tokenBonus, uint256 timestamp);
    event LogRTHContribution(address contributor, uint256 amountRTH, uint256 tokenAmount, uint256 tokenBonus, uint256 timestamp);

    modifier checkContribution() {
        require(isValidContribution());
        _;
    }

    modifier checkRTHContribution() {
        require(isValidRTHContribution());
        _;
    }

    modifier checkCap() {
        require(validateCap());
        _;
    }

    function RenitheumDAICO(
        address RTHTokenAddress,
        address tokenAddress,
        address fundAddress,
        address _RTHTokenWallet,
        address _referralTokenWallet,
        address _advisorsTokenWallet,
        address _companyTokenWallet,
        address _reserveTokenWallet,
        address _bountyTokenWallet,
        address _owner
    ) public
        Ownable(_owner)
    {
        require(tokenAddress != address(0));

        RTHToken = IERC20Token(RTHTokenAddress);
        token = TransferLimitedToken(tokenAddress);
        fund = ICrowdsaleFund(fundAddress);

        RTHTokenWallet = _RTHTokenWallet;
        referralTokenWallet = _referralTokenWallet;
        advisorsTokenWallet = _advisorsTokenWallet;
        companyTokenWallet = _companyTokenWallet;
        reserveTokenWallet = _reserveTokenWallet;
        bountyTokenWallet = _bountyTokenWallet;
    }

    /**
     * @dev check contribution amount and time
     */
    function isValidContribution() internal view returns(bool) {
        if(now < SALE_START_TIME || now > SALE_END_TIME) {
            return false;

        }
        uint256 currentUserContribution = safeAdd(msg.value, userTotalContributed[msg.sender]);
        if(whiteList[msg.sender] && msg.value >= ETHER_MIN_CONTRIB) {
            if(now <= MAX_CONTRIB_CHECK_END_TIME && currentUserContribution > ETHER_MAX_CONTRIB ) {
                    return false;
            }
            return true;

        }
        if(privilegedList[msg.sender] && msg.value >= ETHER_MIN_CONTRIB_PRIVATE) {
            if(now <= MAX_CONTRIB_CHECK_END_TIME && currentUserContribution > ETHER_MAX_CONTRIB_PRIVATE ) {
                    return false;
            }
            return true;
        }
        if(token.limitedWallets(msg.sender) && msg.value >= ETHER_MIN_CONTRIB_USA) {
            if(now <= MAX_CONTRIB_CHECK_END_TIME && currentUserContribution > ETHER_MAX_CONTRIB_USA) {
                    return false;
            }
            return true;
        }

        return false;
    }

    /**
     * @dev Check hard cap overflow
     */
    function validateCap() internal view returns(bool){
        if(now <= HARD_CAP_MERGE_TIME) {
            if(token.limitedWallets(msg.sender)) {
                if(safeAdd(totalUSAEtherContributed, msg.value) <= USAHardCap) {
                    return true;
                }
                return false;
            }
            if(safeAdd(totalWorldEtherContributed, msg.value) <= hardCap) {
                return true;
            }
            return false;
        }

        uint256 totalHardCap = safeAdd(USAHardCap, hardCap);
        uint256 totalEtherContributed = safeAdd(totalWorldEtherContributed, totalUSAEtherContributed);
        if(msg.value <= safeSub(totalHardCap, totalEtherContributed)) {
            return true;
        }
        return false;
    }

    /**
     * @dev Set token price once before start of crowdsale
     */
    function setTokenPrice(uint256 _tokenPriceNum, uint256 _tokenPriceDenom) public onlyOwner {
        require(tokenPriceNum == 0 && tokenPriceDenom == 0);
        require(_tokenPriceNum > 0 && _tokenPriceDenom > 0);
        tokenPriceNum = _tokenPriceNum;
        tokenPriceDenom = _tokenPriceDenom;
    }

    /**
     * @dev Set hard caps.
     * @param _hardCap - World hard cap (USA hard cap = 0.5 * WorldHardCap)
     */
    function setHardCap(uint256 _hardCap) public onlyOwner {
        require(hardCap == 0);
        hardCap = _hardCap;
        USAHardCap = safeDiv(hardCap, 2);
    }

    /**
     * @dev Check RTH contribution time, amount and hard cap overflow
     */
    function isValidRTHContribution() internal view returns(bool) {
        if(token.limitedWallets(msg.sender)) {
            return false;
        }
        if(now < SALE_START_TIME || now > SALE_END_TIME) {
            return false;
        }
        if(!whiteList[msg.sender] && !privilegedList[msg.sender]) {
            return false;
        }
        uint256 amount = RTHToken.allowance(msg.sender, address(this));
        if(amount < RTH_MIN_CONTRIB || safeAdd(totalRTHContributed, amount) > RTH_HARD_CAP) {
            return false;
        }
        return true;

    }

    /**
     * @dev Calc bonus amount by contribution time
     */
    function getBonus() internal constant returns (uint256, uint256) {
        uint256 numerator = 0;
        uint256 denominator = 100;

        if(now < BONUS_WINDOW_1_END_TIME) {
            numerator = 25;
        } else if(now < BONUS_WINDOW_2_END_TIME) {
            numerator = 15;
        } else if(now < BONUS_WINDOW_3_END_TIME) {
            numerator = 10;
        } else if(now < BONUS_WINDOW_4_END_TIME) {
            numerator = 5;
        } else {
            numerator = 0;
        }

        return (numerator, denominator);
    }

    /**
     * @dev Add wallet to whitelist. For contract owner only.
     */
    function addToWhiteList(address _wallet) public onlyOwner {
        whiteList[_wallet] = true;
    }

    /**
     * @dev Add wallet to telegram members. For contract owner only.
     */
    function addTelegramMember(address _wallet) public onlyOwner {
        telegramMemberBonusState[_wallet] = TelegramBonusState.Active;
    }

    /**
     * @dev Add wallet to privileged list. For contract owner only.
     */
    function addToPrivilegedList(address _wallet) public onlyOwner {
        privilegedList[_wallet] = true;
    }

    /**
     * @dev Set LockedTokens contract address
     */
    function setLockedTokens(address lockedTokensAddress) public onlyOwner {
        lockedTokens = LockedTokens(lockedTokensAddress);
    }

    /**
     * @dev Fallback function to receive ether contributions
     */
    function () payable public {
        processContribution();
    }

    /**
     * @dev Process RTH token contribution
     * Transfer all amount of tokens approved by sender. Calc bonuses and issue tokens to contributor.
     */
    function processRTHContribution() public whenNotPaused checkRTHContribution {
        uint256 bonusNum = 0;
        uint256 bonusDenom = 100;
        (bonusNum, bonusDenom) = getBonus();
        uint256 amountRTH = RTHToken.allowance(msg.sender, address(this));
        RTHToken.transferFrom(msg.sender, address(this), amountRTH);
        RTHContributions[msg.sender] = safeAdd(RTHContributions[msg.sender], amountRTH);

        uint256 tokenBonusAmount = 0;
        uint256 tokenAmount = safeDiv(safeMul(amountRTH, RTH_tokenPriceNum), RTH_tokenPriceDenom);
        rawTokenSupply = safeAdd(rawTokenSupply, tokenAmount);
        if(bonusNum > 0) {
            tokenBonusAmount = safeDiv(safeMul(tokenAmount, bonusNum), bonusDenom);
        }

        if(telegramMemberBonusState[msg.sender] ==  TelegramBonusState.Active) {
            telegramMemberBonusState[msg.sender] = TelegramBonusState.Applied;
            uint256 telegramBonus = safeDiv(safeMul(tokenAmount, TG_BONUS_NUM), TG_BONUS_DENOM);
            tokenBonusAmount = safeAdd(tokenBonusAmount, telegramBonus);
        }

        uint256 tokenTotalAmount = safeAdd(tokenAmount, tokenBonusAmount);
        token.issue(msg.sender, tokenTotalAmount);
        totalRTHContributed = safeAdd(totalRTHContributed, amountRTH);

        LogRTHContribution(msg.sender, amountRTH, tokenAmount, tokenBonusAmount, now);
    }

    /**
     * @dev Process ether contribution. Calc bonuses and issue tokens to contributor.
     */
    function processContribution() private whenNotPaused checkContribution checkCap {
        uint256 bonusNum = 0;
        uint256 bonusDenom = 100;
        (bonusNum, bonusDenom) = getBonus();
        uint256 tokenBonusAmount = 0;
        userTotalContributed[msg.sender] = safeAdd(userTotalContributed[msg.sender], msg.value);
        uint256 tokenAmount = safeDiv(safeMul(msg.value, tokenPriceNum), tokenPriceDenom);
        rawTokenSupply = safeAdd(rawTokenSupply, tokenAmount);

        if(bonusNum > 0) {
            tokenBonusAmount = safeDiv(safeMul(tokenAmount, bonusNum), bonusDenom);
        }

        if(telegramMemberBonusState[msg.sender] ==  TelegramBonusState.Active) {
            telegramMemberBonusState[msg.sender] = TelegramBonusState.Applied;
            uint256 telegramBonus = safeDiv(safeMul(tokenAmount, TG_BONUS_NUM), TG_BONUS_DENOM);
            tokenBonusAmount = safeAdd(tokenBonusAmount, telegramBonus);
        }

        uint256 tokenTotalAmount = safeAdd(tokenAmount, tokenBonusAmount);

        token.issue(msg.sender, tokenTotalAmount);
        fund.processContribution.value(msg.value)(msg.sender);

        if(token.limitedWallets(msg.sender)) {
            totalUSAEtherContributed = safeAdd(totalUSAEtherContributed, msg.value);
        } else {
            totalWorldEtherContributed = safeAdd(totalWorldEtherContributed, msg.value);
        }

        LogContribution(msg.sender, msg.value, tokenAmount, tokenBonusAmount, now);
    }

    /**
     * @dev Finalize crowdsale if we reached all hard caps or current time > SALE_END_TIME
     */
    function finalizeCrowdsale() public onlyOwner {
        uint256 totalHardCap = safeAdd(USAHardCap, hardCap);
        uint256 totalEtherContributed = safeAdd(totalWorldEtherContributed, totalUSAEtherContributed);
        if(
            (totalEtherContributed >= safeSub(totalHardCap, ETHER_MIN_CONTRIB_USA) && totalRTHContributed >= safeSub(RTH_HARD_CAP, RTH_MIN_CONTRIB)) ||
            (now >= SALE_END_TIME && totalEtherContributed >= SOFT_CAP)
        ) {
            fund.onCrowdsaleEnd();
            // RTH transfer
            RTHToken.transfer(RTHTokenWallet, RTHToken.balanceOf(address(this)));

            // Referral
            uint256 referralTokenAmount = safeDiv(rawTokenSupply, 10);
            token.issue(referralTokenWallet, referralTokenAmount);

            uint256 suppliedTokenAmount = token.totalSupply();

            // Reserve
            uint256 reservedTokenAmount = safeDiv(safeMul(suppliedTokenAmount, 3), 10); // 18%
            token.issue(address(lockedTokens), reservedTokenAmount);
            lockedTokens.addTokens(reserveTokenWallet, reservedTokenAmount, now + 183 days);

            // Advisors
            uint256 advisorsTokenAmount = safeDiv(suppliedTokenAmount, 10); // 6%
            token.issue(advisorsTokenWallet, advisorsTokenAmount);

            // Company
            uint256 companyTokenAmount = safeDiv(suppliedTokenAmount, 4); // 15%
            token.issue(address(lockedTokens), companyTokenAmount);
            lockedTokens.addTokens(companyTokenWallet, companyTokenAmount, now + 365 days);


            // Bounty
            uint256 bountyTokenAmount = safeDiv(suppliedTokenAmount, 60); // 1%
            token.issue(bountyTokenWallet, bountyTokenAmount);

            token.setAllowTransfers(true);

        } else if(now >= SALE_END_TIME) {
            // Enable fund`s crowdsale refund if soft cap is not reached
            fund.enableCrowdsaleRefund();
            RTHRefundEnabled = true;
        }
        token.finishIssuance();
    }

    /**
     * @dev Function is called by contributor to refund RTH token payments if crowdsale failed to reach soft cap
     */
    function refundRTHContributor() public {
        require(RTHRefundEnabled);
        require(RTHContributions[msg.sender] > 0);
        uint256 amount = RTHContributions[msg.sender];
        RTHContributions[msg.sender] = 0;
        RTHToken.transfer(msg.sender, amount);
        token.destroy(msg.sender, token.balanceOf(msg.sender));
    }
}
