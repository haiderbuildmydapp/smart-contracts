// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Lottery is VRFConsumerBase, Ownable {
    using SafeERC20 for IERC20;
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public lotteryRoundId;
    uint8 public platformShare;
    uint256 public bondPrice;
    uint32 public lotteryDuration;
    uint256 public minBalanceCheck;
    IERC20 public platfromToken;
    struct LotteryRound {
        mapping(address => uint16) entries;
        mapping(address => uint256) userDeposits;
        address[] participants;
        uint256 lotteryEndTime;
        bool lotteryEnded;
        address winner;
        uint256 prizeWon;
    }
 
    struct LotteryDetail {
        uint256 lotteryId;
        uint256 amountWon;
        address winner;
        address[] participants;
        uint256 totalCollection;
        uint256 lotteryEndTime;
    }
    mapping(address => uint256[]) public UserParticipation;
    mapping(uint256 => LotteryRound) public LotteryRoundInfo;

    // Events
    event LotteryEntry(uint256 lotteryId, address participant, uint256 amount);
    event WinnerSelection(uint256 lotteryId, address winner, uint256 amount);
    event PlatfromFeeSent(uint256 lotteryId, uint256 amount);
    event EtherReceived(address sender, uint256 amount);

    // constructor(
    //     address _vrfCoordinator,
    //     address _linkToken,
    //     address initialOwner,
    //     bytes32 _keyHash,
    //     uint256 _fee
    // ) VRFConsumerBase(_vrfCoordinator, _linkToken) Ownable(initialOwner) {
    //     keyHash = _keyHash;
    //     fee = _fee;
    // }

      constructor(
        ) VRFConsumerBase(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625, 0x779877A7B0D9E8603169DdbD7836e478b4624789) Ownable(0x56426233C10880d029fB20dA51bF24450D5a93bC) {
            keyHash = 0x0476f9a745b61ea5c0ab224d3a6e4c99f0b02fce4da01143a4f70aa80ae76e8a;
            fee = 0.01 ether;
            platformShare=10;
            bondPrice=0.00001 ether;
            lotteryDuration=6 minutes;
            minBalanceCheck=1000 ether;
            platfromToken=IERC20(0x1A3923aB9Eb37e402D8cd57c03D36976125bA378);
        }
    error InSufficientEthSent(uint256 required, uint256 sent);

    receive() external payable {
        if (msg.value < bondPrice) {
            revert InSufficientEthSent(bondPrice, msg.value);
        }
        if (
            block.timestamp >=
            LotteryRoundInfo[lotteryRoundId].lotteryEndTime &&
            !LotteryRoundInfo[lotteryRoundId].lotteryEnded
        ) {
            endLotteryInternal();
            unchecked {
                lotteryRoundId++;
                LotteryRoundInfo[lotteryRoundId].lotteryEndTime =
                    block.timestamp +
                    lotteryDuration;
            }
        }
        if (LotteryRoundInfo[lotteryRoundId].entries[msg.sender] == 0) {
            LotteryRoundInfo[lotteryRoundId].participants.push(msg.sender);
        }
        uint16 entryAmount = uint16(msg.value / bondPrice);
        uint256 userBalance = platfromToken.balanceOf(msg.sender);
        if (userBalance >= minBalanceCheck) {
            uint16 additionalEntries = uint16(userBalance / minBalanceCheck);
            entryAmount += additionalEntries;
        }
        unchecked {
            LotteryRoundInfo[lotteryRoundId].entries[msg.sender] += entryAmount;
            LotteryRoundInfo[lotteryRoundId].userDeposits[msg.sender] += msg
                .value;
        }
        UserParticipation[msg.sender].push(lotteryRoundId);
        emit LotteryEntry(lotteryRoundId, msg.sender, msg.value);
    }

    // Manually end the lottery and pick a winner
    error LotteryNotEnded();

    function endLottery() external {
        if (
            block.timestamp < LotteryRoundInfo[lotteryRoundId].lotteryEndTime &&
            !LotteryRoundInfo[lotteryRoundId].lotteryEnded
        ) {
            revert LotteryNotEnded();
        }
        endLotteryInternal();
        unchecked {
            lotteryRoundId++;
            LotteryRoundInfo[lotteryRoundId].lotteryEndTime =
                block.timestamp +
                lotteryDuration;
        }
    }

    error InsufficientLinkBalance();

    function endLotteryInternal() internal {
        if (LotteryRoundInfo[lotteryRoundId].participants.length == 0) {
            LotteryRoundInfo[lotteryRoundId].lotteryEnded = true;
        } else if (LotteryRoundInfo[lotteryRoundId].participants.length == 1) {
            // uint256 lotteryId = lotteryRoundId - 1;

            uint256 totalCollection = LotteryRoundInfo[lotteryRoundId]
                .userDeposits[LotteryRoundInfo[lotteryRoundId].participants[0]];
            address winner = LotteryRoundInfo[lotteryRoundId].participants[0];
            executeWinner(lotteryRoundId, totalCollection, winner);
            LotteryRoundInfo[lotteryRoundId].lotteryEnded = true;
        } else {
            if (LINK.balanceOf(address(this)) < fee) {
                revert InsufficientLinkBalance();
            }
            requestRandomness(keyHash, fee);
            LotteryRoundInfo[lotteryRoundId].lotteryEnded = true;
        }
    }

    error payoutToWinnerError();
    error payoutToPlatformError();

    // Chainlink VRF callback function
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        uint256 totalEntries;
        uint256 lotteryId = lotteryRoundId - 1;
        uint256 noOfParticipants = LotteryRoundInfo[lotteryId]
            .participants
            .length;
        for (uint16 i; i < noOfParticipants; ) {
            unchecked {
                totalEntries += LotteryRoundInfo[lotteryId].entries[
                    LotteryRoundInfo[lotteryId].participants[i]
                ];
                i++;
            }
        }

        uint256 winningPoint = randomness % totalEntries;
        uint256 counter;
        address winner;

        for (uint16 i; i < noOfParticipants; ) {
            unchecked {
                counter += LotteryRoundInfo[lotteryId].entries[
                    LotteryRoundInfo[lotteryId].participants[i]
                ];
                i++;
            }
            if (counter >= winningPoint) {
                winner = LotteryRoundInfo[lotteryId].participants[i];
                break;
            }
        }
        uint256 totalRoundCollection;
        for (uint16 i; i < noOfParticipants; ) {
            unchecked {
                totalRoundCollection += LotteryRoundInfo[lotteryId]
                    .userDeposits[LotteryRoundInfo[lotteryId].participants[i]];
                i++;
            }
        }

        executeWinner(lotteryId, totalRoundCollection, winner);

        // uint256 platfromAmount = (totalRoundCollection * platformShare) / 100;
        // uint256 prizeMoney;
        // unchecked {
        //     prizeMoney = totalRoundCollection - platfromAmount;
        // }
        // (bool payoutToWinnerSuccess, ) = payable(winner).call{
        //     value: prizeMoney
        // }("");

        // if (!payoutToWinnerSuccess) {
        //     revert payoutToWinnerError();
        // }
        // (bool payoutToPlatformSuccess, ) = payable(owner()).call{
        //     value: platfromAmount
        // }("");

        // if (!payoutToPlatformSuccess) {
        //     revert payoutToPlatformError();
        // }
        // LotteryRoundInfo[lotteryId].winner = winner;
        // LotteryRoundInfo[lotteryId].prizeWon = prizeMoney;
        // winnersInfo[winner].push(Winners(lotteryId, prizeMoney));
        // emit WinnerSelection(lotteryId, winner, prizeMoney);
        // emit PlatfromFeeSent(lotteryId, platfromAmount);
    }

    function executeWinner(
        uint256 _lotteryId,
        uint256 _amount,
        address _winner
    ) internal {
        uint256 platfromAmount = (_amount * platformShare) / 100;

        uint256 prizeMoney = _amount - platfromAmount;

        (bool payoutToWinnerSuccess, ) = payable(_winner).call{
            value: prizeMoney
        }("");
        if (!payoutToWinnerSuccess) {
            revert payoutToWinnerError();
        }
        (bool payoutToPlatformSuccess, ) = payable(owner()).call{
            value: platfromAmount
        }("");

        if (!payoutToPlatformSuccess) {
            revert payoutToPlatformError();
        }
        LotteryRoundInfo[_lotteryId].winner = _winner;
        LotteryRoundInfo[_lotteryId].prizeWon = prizeMoney;
        // winnersInfo[_winner].push(Winners(_lotteryId, prizeMoney));
        emit WinnerSelection(_lotteryId, _winner, prizeMoney);
        emit PlatfromFeeSent(_lotteryId, platfromAmount);
    }

    function setPlatformShare(uint8 _platformShare) external onlyOwner {
        require(_platformShare != 0, "Can't be zero");
        require(_platformShare <= 20, "Max 20% allowed");
        platformShare = _platformShare;
    }

    function setBalanceThreshold(uint256 _amount) external onlyOwner {
        require(_amount != 0, "Can't be zero");
        minBalanceCheck = _amount;
    }

    function setBondPrice(uint256 _bondPrice) external onlyOwner {
        require(_bondPrice != 0, "Can't be zero");

        bondPrice = _bondPrice;
    }

    function setPlatformToken(address _token) external onlyOwner {
        require(_token != address(0), "Can't be zero");

        platfromToken = IERC20(_token);
    }

    function setLotteryDuration(uint32 _lotteryDuration) external onlyOwner {
        require(_lotteryDuration != 0, "Can't be zero");
        lotteryDuration = _lotteryDuration;
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

    error invalidIds();

    function lotteryDetail(uint256 startId, uint256 toId)
        external
        view
        returns (LotteryDetail[] memory)
    {
        if (startId == 0 || toId > lotteryRoundId || toId < startId) {
            revert invalidIds();
        }
        LotteryDetail[] memory lotteryData = new LotteryDetail[](
            toId - startId + 1
        );

        uint256 index = 0;
        for (uint256 j = startId; j <= toId; j++) {
            LotteryRound storage round = LotteryRoundInfo[j];
            uint256 totalRoundCollection;
            for (uint16 i; i < LotteryRoundInfo[j].participants.length; ) {
                unchecked {
                    totalRoundCollection += LotteryRoundInfo[j].userDeposits[
                        LotteryRoundInfo[j].participants[i]
                    ];
                    i++;
                }
            }
            lotteryData[index].lotteryId = j;
            lotteryData[index].amountWon = round.prizeWon;
            lotteryData[index].winner = round.winner;
            lotteryData[index].participants = round.participants;
            lotteryData[index].lotteryEndTime = round.lotteryEndTime;
            lotteryData[index].totalCollection = totalRoundCollection;
            index++;
        }
        return lotteryData;
    }

    error zeroAddress();
      function getParticipation(address user) public view returns (uint256[] memory) {
        return UserParticipation[user];
    }
}