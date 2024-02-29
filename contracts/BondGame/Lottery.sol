// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Lottery is VRFConsumerBase, Ownable {
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public lotteryRoundId;
    uint256 public platformShare;
    uint256 public bondPrice;
    uint256 public lotteryDuration;
    uint256 public maximumPurchaseAmount;
    struct LotteryRound {
        mapping(address => uint256) entries;
        mapping(address => uint256) userDeposits;
        address[] participants;
        uint256 lotteryEndTime;
        bool lotteryEnded;
        address winner;
        uint256 amountWon;
    } 
    struct Winners{
        uint256 lotteryId;
        uint256 amount;
    }
     mapping(address => Winners[]) public winnersInfo;
    mapping(uint256 => LotteryRound) public LotteryRoundInfo;

    // Events
    event LotteryEntry(uint256 lotteryId, address participant, uint256 amount);
    event WinnerSelection(uint256 lotteryId, address winner, uint256 amount);
    event PlatfromFeeSent(uint256 lotteryId, uint256 amount);
    event EtherReceived(address sender, uint256 amount);

    constructor(
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _keyHash,
        uint256 _fee,
        address initialOwner
    ) VRFConsumerBase(_vrfCoordinator, _linkToken) Ownable(initialOwner) {
        keyHash = _keyHash;
        fee = _fee;
    }

    receive() external payable {
        require(msg.value >= bondPrice, "Minimum purchase amount required");
        require(
            msg.value <= maximumPurchaseAmount,
            "Maximum purchase amount exceeded"
        );
        if (
            block.timestamp > LotteryRoundInfo[lotteryRoundId].lotteryEndTime &&
            !LotteryRoundInfo[lotteryRoundId].lotteryEnded
        ) {
            lotteryRoundId++;
            endLotteryInternal();
            LotteryRoundInfo[lotteryRoundId].lotteryEndTime =
                block.timestamp +
                lotteryDuration;
        }
        require(
            block.timestamp <= LotteryRoundInfo[lotteryRoundId].lotteryEndTime,
            "Lottery ended"
        );
        if (LotteryRoundInfo[lotteryRoundId].entries[msg.sender] == 0) {
            LotteryRoundInfo[lotteryRoundId].participants.push(msg.sender);
        }
        uint256 entryAmount = msg.value / bondPrice;
        entryAmount = entryAmount * bondPrice;
        LotteryRoundInfo[lotteryRoundId].entries[msg.sender] += entryAmount;
        LotteryRoundInfo[lotteryRoundId].userDeposits[msg.sender] += msg.value;
        emit LotteryEntry(lotteryRoundId, msg.sender, msg.value);
        emit EtherReceived(msg.sender, msg.value);
    }

    // Manually end the lottery and pick a winner
    function endLottery() external onlyOwner {
        lotteryRoundId++;
        endLotteryInternal();
        LotteryRoundInfo[lotteryRoundId].lotteryEndTime =
            block.timestamp +
            lotteryDuration;
    }

    function endLotteryInternal() internal {
        uint256 lotteryId = lotteryRoundId - 1;
        require(
            block.timestamp >= LotteryRoundInfo[lotteryId].lotteryEndTime,
            "Lottery not yet ended"
        );
        require(
            !LotteryRoundInfo[lotteryId].lotteryEnded,
            "Lottery already ended"
        );
        if (LotteryRoundInfo[lotteryId].participants.length == 0) {
            LotteryRoundInfo[lotteryId].lotteryEnded = true;
        } else {
            require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
            requestRandomness(keyHash, fee);
            LotteryRoundInfo[lotteryId].lotteryEnded = true;
        }
    }

    // Chainlink VRF callback function
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        uint256 totalEntries = 0;
        uint256 lotteryId = lotteryRoundId - 1;
        for (
            uint256 i = 0;
            i < LotteryRoundInfo[lotteryId].participants.length;
            i++
        ) {
            totalEntries += LotteryRoundInfo[lotteryId].entries[
                LotteryRoundInfo[lotteryId].participants[i]
            ];
        }

        uint256 winningPoint = randomness % totalEntries;
        uint256 counter = 0;
        address winner;

        for (
            uint256 i = 0;
            i < LotteryRoundInfo[lotteryId].participants.length;
            i++
        ) {
            counter += LotteryRoundInfo[lotteryId].entries[
                LotteryRoundInfo[lotteryId].participants[i]
            ];
            if (counter >= winningPoint) {
                winner = LotteryRoundInfo[lotteryId].participants[i];
                break;
            }
        }
        uint256 totalRoundCollection = 0;
        for (
            uint256 i = 0;
            i < LotteryRoundInfo[lotteryId].participants.length;
            i++
        ) {
            totalRoundCollection += LotteryRoundInfo[lotteryId].userDeposits[
                LotteryRoundInfo[lotteryId].participants[i]
            ];
        }
        uint256 platfromAmount = (totalRoundCollection * platformShare) / 100;

        uint256 prizeMoney = totalRoundCollection - platfromAmount;
        (bool payoutToWinnerSuccess, ) = payable(winner).call{
            value: prizeMoney
        }("");
        require(payoutToWinnerSuccess, "Winner payout failed.");
        (bool payoutToPlatformSuccess, ) = payable(owner()).call{
            value: platfromAmount
        }("");
        require(payoutToPlatformSuccess, "Platform fee transfer failed.");
        LotteryRoundInfo[lotteryId].winner = winner;
        LotteryRoundInfo[lotteryId].amountWon = prizeMoney;
        winnersInfo[winner].push(Winners(lotteryId, prizeMoney));
        emit WinnerSelection(lotteryId, winner, prizeMoney);
        emit PlatfromFeeSent(lotteryId, platfromAmount);
    }

    function setPlatformShare(uint256 _platformShare) external onlyOwner {
        require(_platformShare != 0, "Can't be zero");
        require(_platformShare <= 20, "Max 20% allowed");
        platformShare = _platformShare;
    }

    function setBondPrice(uint256 _bondPrice) external onlyOwner {
        require(_bondPrice != 0, "Can't be zero");

        bondPrice = _bondPrice;
    }

    function setLotteryDuration(uint256 _lotteryDuration) external onlyOwner {
         require(_lotteryDuration != 0, "Can't be zero");
        lotteryDuration = _lotteryDuration;
    }

    function setMaximumPurchaseAmount(uint256 _maximumPurchaseAmount)
        external
        onlyOwner
    {
        require(
            _maximumPurchaseAmount > bondPrice,
            "Max purchase must exceed bond price"
        );
        maximumPurchaseAmount = _maximumPurchaseAmount;
    }

    function getLotteryPartcipants(uint256 _lotteryId)
        external
        view
        returns (address[] memory participants)
    {
        return LotteryRoundInfo[_lotteryId].participants;
    }

    function getLotteryPartcipantEntries(uint256 _lotteryId, address _user)
        external
        view
        returns (uint256)
    {
        return LotteryRoundInfo[_lotteryId].entries[_user];
    }

    function getLotteryPartcipantDeposits(uint256 lotteryId, address user)
        external
        view
        returns (uint256)
    {
        return LotteryRoundInfo[lotteryId].userDeposits[user];
    }
}