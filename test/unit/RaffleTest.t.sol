// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// 导入部署抽奖合约的脚本
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
// 导入抽奖合约本体
import {Raffle} from "../../src/Raffle.sol";
// 导入助手配置合约，用于获取配置参数
import {HelperConfig} from "../../script/HelperConfig.s.sol";
// 导入Forge标准测试库
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
// 导入VRF协调器模拟合约，用于模拟链外服务
import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mock.sol";
import {CreateSubscription} from "../../script/Interactions.s.sol";

// 测试合约继承自Test和StdCheats，提供便捷的链上操作和测试功能
contract RaffleTest is StdCheats, Test {
    // 定义事件，用于在测试中检测合约是否正确触发这些事件
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);

    // 合约实例
    Raffle public raffle;
    HelperConfig public helperConfig;

    // 测试用的配置参数
    uint64 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint256 raffleEntranceFee;
    uint32 callbackGasLimit;
    address vrfCoordinatorV2;

    // 测试用的玩家地址和初始余额
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    // 初始化函数，用于部署和配置测试环境
    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        // 从配置中获取参数
        (
            ,
            gasLane,
            automationUpdateInterval,
            raffleEntranceFee,
            callbackGasLimit,
            vrfCoordinatorV2,
,
        ) = helperConfig.activeNetworkConfig();
    }

    // 测试合约初始状态为开放
    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /////////////////////////
    // 测试进入抽奖
    /////////////////////////

    // 测试当不支付足够的入场费时应该撤销交易
    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    // 测试玩家成功进入抽奖后是否被正确记录
    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    // 测试进入抽奖时是否触发相应的事件
    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEnter(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    // 测试在计算中状态不允许玩家进入
    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    /////////////////////////
    // 测试检查维护
    /////////////////////////
    // 测试当合约没有余额时，checkUpkeep返回false
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    // 测试在抽奖不开放时，checkUpkeep返回false
    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(!upkeepNeeded);
    }

    // 如果不够时间间隔，checkUpkeep返回false
    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    // 当参数正确时，checkUpkeep返回true
    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    /////////////////////////
    // 测试执行维护
    /////////////////////////

    // 只有当checkUpkeep为true时，才能运行performUpkeep
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
    }

    // 如果checkUpkeep为false，执行performUpkeep应撤销
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    // 执行performUpkeep应更新状态并触发请求ID事件
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        raffle.performUpkeep(""); // 触发请求ID
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint(raffleState) == 1); // 0 = open, 1 = calculating
    }

    /////////////////////////
    // 测试随机数完成
    ////////////////////////

    // 这个修饰符确保在测试随机数完成之前已经进入了抽奖
    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // 如果不是在指定的链上，则跳过测试
    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    // 测试在执行performUpkeep后才能调用fulfillRandomWords
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep()
        public
        raffleEntered
        skipFork
    {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            0,
            address(raffle)
        );

        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            1,
            address(raffle)
        );
    }

    // 测试fulfillRandomWords正确选择获胜者，重置状态，并发送奖金
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEntered
        skipFork
    {
        address expectedWinner = address(1);

        uint256 additionalEntrances = 3;
        uint256 startingIndex = 1; // 从address(1)开始，避免使用address(0)

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrances;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, 1 ether); // 为玩家提供1 ether
            raffle.enterRaffle{value: raffleEntranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep(""); // 触发请求ID
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = raffleEntranceFee * (additionalEntrances + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
