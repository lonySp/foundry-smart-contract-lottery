// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Raffle} from "../src/Raffle.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {VRFCoordinatorV2Mock} from "../test/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract CreateSubscription is Script {
    // 使用配置创建订阅并返回订阅ID和VRF协调器地址
    function createSubscriptionUsingConfig() public returns (uint64, address) {
        HelperConfig helperConfig = new HelperConfig(); // 创建HelperConfig实例
        (
            ,
            ,
            ,
            ,
            ,
            address vrfCoordinatorV2,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig(); // 从配置获取VRF协调器地址和部署者密钥
        return createSubscription(vrfCoordinatorV2, deployerKey); // 调用createSubscription函数
    }

    // 创建一个VRF订阅
    function createSubscription(
        address vrfCoordinatorV2,
        uint256 deployerKey
    ) public returns (uint64, address) {
        console.log("Creating subscription on chainId: ", block.chainid);
        vm.startBroadcast(deployerKey); // 开始广播，使用提供的密钥
        uint64 subId = VRFCoordinatorV2Mock(vrfCoordinatorV2)
            .createSubscription(); // 调用模拟VRF协调器的createSubscription
        vm.stopBroadcast(); // 停止广播
        console.log("Your subscription Id is: ", subId);
        console.log("Please update the subscriptionId in HelperConfig.s.sol");
        return (subId, vrfCoordinatorV2);
    }

    function run() external returns (uint64, address) {
        return createSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    // 添加一个消费者到VRF订阅
    function addConsumer(
        address contractToAddToVrf,
        address vrfCoordinator,
        uint64 subId,
        uint256 deployerKey
    ) public {
        console.log("Adding consumer contract: ", contractToAddToVrf);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("On ChainID: ", block.chainid);
        vm.startBroadcast(deployerKey); // 开始广播，使用提供的密钥
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(
            subId,
            contractToAddToVrf
        ); // 调用模拟VRF协调器的addConsumer
        vm.stopBroadcast(); // 停止广播
    }

    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint64 subId,
            ,
            ,
            ,
            ,
            address vrfCoordinatorV2,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        addConsumer(mostRecentlyDeployed, vrfCoordinatorV2, subId, deployerKey);
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether; // 资金金额常量

    // 使用配置为订阅提供资金
    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint64 subId,
            ,
            ,
            ,
            ,
            address vrfCoordinatorV2,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (subId == 0) {
            CreateSubscription createSub = new CreateSubscription();
            (uint64 updatedSubId, address updatedVRFv2) = createSub.run();
            subId = updatedSubId;
            vrfCoordinatorV2 = updatedVRFv2;
            console.log(
                "New SubId Created! ",
                subId,
                "VRF Address: ",
                vrfCoordinatorV2
            );
        }

        fundSubscription(vrfCoordinatorV2, subId, link, deployerKey);
    }

    // 为订阅提供资金
    function fundSubscription(
        address vrfCoordinatorV2,
        uint64 subId,
        address link,
        uint256 deployerKey
    ) public {
        console.log("Funding subscription: ", subId);
        console.log("Using vrfCoordinator: ", vrfCoordinatorV2);
        console.log("On ChainID: ", block.chainid);
        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey); // 开始广播，使用提供的密钥
            VRFCoordinatorV2Mock(vrfCoordinatorV2).fundSubscription(
                subId,
                FUND_AMOUNT
            ); // 调用模拟VRF协调器的fundSubscription
            vm.stopBroadcast(); // 停止广播
        } else {
            console.log(LinkToken(link).balanceOf(msg.sender));
            console.log(msg.sender);
            console.log(LinkToken(link).balanceOf(address(this)));
            console.log(address(this));
            vm.startBroadcast(deployerKey); // 开始广播，使用提供的密钥
            LinkToken(link).transferAndCall(
                vrfCoordinatorV2,
                FUND_AMOUNT,
                abi.encode(subId)
            ); // 转账并调用，提供资金
            vm.stopBroadcast(); // 停止广播
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}
