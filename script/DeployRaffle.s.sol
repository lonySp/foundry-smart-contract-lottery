// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// 导入 Forge 标准库中的 Script 工具，用于脚本编写
import {Script} from "forge-std/Script.sol";
// 导入网络配置助手合约
import {HelperConfig} from "./HelperConfig.s.sol";
// 导入抽奖合约
import {Raffle} from "../src/Raffle.sol";
// 导入创建订阅、添加消费者和资金注入的合约
import {AddConsumer, CreateSubscription, FundSubscription} from "./Interactions.s.sol";

// 定义部署抽奖合约的脚本合约
contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        // 实例化网络配置助手合约
        HelperConfig helperConfig = new HelperConfig(); 
        // 实例化添加消费者脚本合约
        AddConsumer addConsumer = new AddConsumer();
        // 从助手合约获取当前的网络配置
        (
            uint64 subscriptionId,
            bytes32 gasLane,
            uint256 automationUpdateInterval,
            uint256 raffleEntranceFee,
            uint32 callbackGasLimit,
            address vrfCoordinatorV2,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        // 如果当前没有有效的订阅ID，则创建一个新的订阅
        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            // 创建订阅，并更新订阅ID和 VRF 协调器地址
            (subscriptionId, vrfCoordinatorV2) = createSubscription.createSubscription(
                vrfCoordinatorV2,
                deployerKey
            );

            // 实例化资金注入脚本合约
            FundSubscription fundSubscription = new FundSubscription();
            // 为新创建的订阅注入资金
            fundSubscription.fundSubscription(
                vrfCoordinatorV2,
                subscriptionId,
                link,
                deployerKey
            );
        }

        // 开始广播交易
        vm.startBroadcast(deployerKey);
        // 部署抽奖合约
        Raffle raffle = new Raffle(
            subscriptionId,
            gasLane,
            automationUpdateInterval,
            raffleEntranceFee,
            callbackGasLimit,
            vrfCoordinatorV2
        );
        // 停止广播交易
        vm.stopBroadcast();

        // 将新部署的抽奖合约地址添加为 VRF 订阅的消费者
        addConsumer.addConsumer(
            address(raffle),
            vrfCoordinatorV2,
            subscriptionId,
            deployerKey
        );
        // 返回部署的抽奖合约和网络配置助手合约的实例
        return (raffle, helperConfig);
    }
}
