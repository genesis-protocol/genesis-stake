pragma solidity ^0.4.26;

import "./Ownable.sol";
import "./library/IERC20.sol";
import "./library/SafeMath.sol";

contract Stake is Ownable {
    using SafeMath for uint256;

    event NewRound(address indexed sToken, address indexed rToken, uint256 indexed rAmount, uint256 round);
    event Claimed(address indexed who, address indexed rToken, uint256 indexed rAmount, uint256 round);
    event StakeIn(address indexed who, address indexed sToken, uint256 indexed sAmount, uint256 round);

    struct roundInfo {
        address stakeToken;
        uint256 maxStakeIn;
        uint256 minStakeIn;
        address rewardToken;
        uint256 rewardAmount;
        uint256 lockBlock;
        uint256 unlockBlock;
        uint256 totalStaking;
    }

    struct stakeData {
        uint256 stakeIn;
        bool    claimed;
    }

    uint256 private nextRound = 0;
    mapping(address=>mapping(uint256=>stakeData)) private stakingList;
    mapping(address=>uint256) private rewardPool;

    roundInfo[] public rounds;

    function getStakingData(address who, uint256 round) public view returns(uint256, bool) {
        require(nextRound > 0);
        require(round < nextRound);

        stakeData memory ret = stakingList[who][round];
        return (ret.stakeIn, ret.claimed);
    }

    function stakeIn(uint256 amount) public {
        require(nextRound != 0, "contract not running");
        uint256 roundIdx = nextRound - 1;
        roundInfo storage currentRound  = rounds[roundIdx];

        require(block.number < currentRound.lockBlock, "staking stage of this round was closed");

        IERC20 sToken = IERC20(currentRound.stakeToken);
        uint256 userBalance = sToken.balanceOf(msg.sender);

        require(amount <= userBalance, "insufficient staking balance");
        sToken.transferFrom(msg.sender,  address(this), amount);
        currentRound.totalStaking = currentRound.totalStaking.add(amount);

        rounds[roundIdx] = currentRound;

        uint256 staked;
        bool claimed;
        (staked, claimed) = getStakingData(msg.sender, roundIdx);
        stakeData memory sData = stakeData(staked, claimed);
        sData.stakeIn = sData.stakeIn.add(amount);

        stakingList[msg.sender][roundIdx] = sData;

        emit StakeIn(msg.sender, currentRound.stakeToken, amount, roundIdx);
    }

    function claimRewards(uint256 round) public {
        require(round < nextRound);
        roundInfo storage theRound = rounds[round];

        require(block.number > theRound.unlockBlock, "staking still running");

        uint256 staked;
        bool claimed;
        (staked, claimed) = getStakingData(msg.sender, round);
        stakeData memory sData = stakeData(staked, claimed);

        require(!sData.claimed, "already claimed rewards");

        uint256 total = theRound.totalStaking.add(theRound.rewardAmount);
        uint256 rewards = sData.stakeIn.mul(total).div(theRound.totalStaking).sub(sData.stakeIn);
        IERC20 rToken = IERC20(theRound.rewardToken);

        if(theRound.rewardToken != theRound.stakeToken) {
            rToken.transfer(msg.sender, rewards);

            IERC20 sToken = IERC20(theRound.stakeToken);
            sToken.transfer(msg.sender, sData.stakeIn);
        } else {
            rToken.transfer(msg.sender, rewards.add(sData.stakeIn));
        }

        sData.claimed = true;
        stakingList[msg.sender][round] = sData;

        emit Claimed(msg.sender, theRound.stakeToken, rewards, round);
    }

    function _checkToken(address stakeToken, uint256 maxStakeIn, uint256 minStakeIn, address rewardToken, uint256 rewardAmount) private view {
        require(minStakeIn > 0);
        require(maxStakeIn > minStakeIn);

        IERC20 sToken = IERC20(stakeToken);
        IERC20 rToken = IERC20(rewardToken);

        require(sToken != address(0));
        require(rToken != address(0));

        uint256 thisBalance = rToken.balanceOf(address(this));
        require(thisBalance >= rewardAmount, "owner must locked in rewards token first");
    }

    function _checkStartRound(uint256 lockBlock, uint256 unlockBlock) private view {
        if(nextRound == 0) {
            return;
        }
        uint256 currentBlock = block.number;

        require(unlockBlock > lockBlock);
        require(lockBlock > currentBlock);

        roundInfo storage currentRound = rounds[nextRound - 1];
        require(currentBlock > currentRound.unlockBlock, "pre-round still running");
    }

    function startNewRound(
        address stakeToken,
        uint256 maxStakeIn,
        uint256 minStakeIn,
        address rewardToken,
        uint256 rewardAmount,
        uint256 lockBlock,
        uint256 unlockBlock
    ) public onlyOwner {

        _checkStartRound(lockBlock, unlockBlock);
        _checkToken(stakeToken, maxStakeIn, minStakeIn, rewardToken, rewardAmount);

        roundInfo memory newRound = roundInfo(
            stakeToken, maxStakeIn, minStakeIn, rewardToken, rewardAmount, lockBlock, unlockBlock, 0
        );

        rewardPool[rewardToken] = rewardPool[rewardToken].add(rewardAmount);

        emit NewRound(stakeToken, rewardToken, rewardAmount, nextRound);

        rounds.push(newRound);
        nextRound = nextRound.add(1);
    }

    function redeemRewardsBeforeStart(address rewardToken) public onlyOwner {
        IERC20 rToken = IERC20(rewardToken);
        uint256 thisBalance = rToken.balanceOf(address(this));
        uint256 unclaimedReward = rewardPool[rewardToken];

        require(thisBalance > unclaimedReward, "no extra token");
        uint256 redeemAmount = thisBalance.sub(unclaimedReward);
        rToken.transfer(msg.sender, redeemAmount);
    }

    function() external payable {
        revert();
    }
}
