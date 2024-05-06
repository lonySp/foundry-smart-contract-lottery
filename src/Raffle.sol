// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// 引入 Chainlink 的 VRF 协调器接口
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
// 引入 Chainlink 的 VRF 消费者基础合约
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
// 引入 Chainlink 的自动化兼容接口
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

/**@title 抽奖合约示例
 * @notice 本合约用于创建一个简单的抽奖程序
 * @dev 实现了 Chainlink VRF Version 2 的功能
 */
contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    /* 自定义错误 */
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );
    error Raffle__TransferFailed();
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__RaffleNotOpen();

    /* 类型声明 */
    enum RaffleState {
        OPEN, // 开放状态
        CALCULATING // 正在计算结果状态
    }

    /* 状态变量 */
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator; // Chainlink VRF 协调器
    uint64 private immutable i_subscriptionId; // VRF 订阅 ID
    bytes32 private immutable i_gasLane; // VRF Gas Lane
    uint32 private immutable i_callbackGasLimit; // VRF 回调的 Gas 限制
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // VRF 请求确认数
    uint32 private constant NUM_WORDS = 1; // VRF 请求的随机数个数

    uint256 private immutable i_interval; // 抽奖间隔
    uint256 private immutable i_entranceFee; // 抽奖入场费
    uint256 private s_lastTimeStamp; // 上次抽奖时间
    address private s_recentWinner; // 最近的获奖者
    address payable[] private s_players; // 抽奖参与者数组
    RaffleState private s_raffleState; // 抽奖状态

    /* 事件定义 */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);

    /* 构造函数 */
    constructor(
        uint64 subscriptionId,
        bytes32 gasLane,
        uint256 interval,
        uint256 entranceFee,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_entranceFee = entranceFee;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    }

    // 允许参与者支付入场费加入抽奖
    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    // 由 Chainlink Keeper 节点调用，检查是否需要进行抽奖
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 如果 `checkUpkeep` 返回 `true`，调用此函数进行抽奖
    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    // 由 Chainlink VRF 节点调用，将奖金发送给随机选择的获奖者
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(recentWinner);
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // 获取当前抽奖状态
    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    // 获取请求数量
    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    // 获取请求确认数
    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    // 获取最近的获奖者
    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    // 获取指定索引的参与者
    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    // 获取上次抽奖时间
    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    // 获取抽奖间隔
    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    // 获取入场费
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    // 获取参与者数量
    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
