// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// 引入测试目录下的 Chainlink VRF 协调器模拟合约
import {VRFCoordinatorV2Mock} from "../test/mocks/VRFCoordinatorV2Mock.sol";
// 引入测试目录下的 Link Token 模拟合约
import {LinkToken} from "../test/mocks/LinkToken.sol";
// 引入 forge-std 库中的 Script 组件，用于编写部署脚本
import {Script} from "forge-std/Script.sol";

// 定义 HelperConfig 合约，继承自 Script
contract HelperConfig is Script {
    // 定义 NetworkConfig 结构体，用于存储网络配置信息
    NetworkConfig public activeNetworkConfig;

    // 网络配置的结构，包括 VRF 相关的参数和链接相关的地址
    struct NetworkConfig {
        uint64 subscriptionId; // Chainlink VRF 订阅 ID
        bytes32 gasLane; // Chainlink VRF gas lane
        uint256 automationUpdateInterval; // 自动更新间隔
        uint256 raffleEntranceFee; // 抽奖入场费
        uint32 callbackGasLimit; // 回调的 gas 限制
        address vrfCoordinatorV2; // Chainlink VRF 协调器地址
        address link; // LINK 代币地址
        uint256 deployerKey; // 部署者的私钥
    }

    // 默认的 Anvil 网络私钥
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // 定义事件，用于标记创建了模拟的 VRF 协调器
    event HelperConfig__CreatedMockVRFCoordinator(address vrfCoordinator);

    // 构造函数中根据链 ID 来决定使用哪个网络配置
    constructor() {
        if (block.chainid == 11155111) {
            // Sepolia 测试网络
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            // 默认使用 Anvil 测试环境
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    // 获取主网的配置
    function getMainnetEthConfig()
        public
        view
        returns (NetworkConfig memory mainnetNetworkConfig)
    {
        mainnetNetworkConfig = NetworkConfig({
            subscriptionId: 0, // 默认情况下脚本将创建订阅
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            automationUpdateInterval: 30, // 更新间隔为30秒
            raffleEntranceFee: 0.01 ether,
            callbackGasLimit: 500000, // 回调的 gas 限制为 500,000
            vrfCoordinatorV2: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909,
            link: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    // 获取 Sepolia 测试网络的配置
    function getSepoliaEthConfig()
        public
        view
        returns (NetworkConfig memory sepoliaNetworkConfig)
    {
        sepoliaNetworkConfig = NetworkConfig({
            subscriptionId: 0, // 默认情况下脚本将创建订阅
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            automationUpdateInterval: 30, // 更新间隔为30秒
            raffleEntranceFee: 0.01 ether,
            callbackGasLimit: 500000, // 回调的 gas 限制为 500,000
            vrfCoordinatorV2: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    // 获取或创建 Anvil 测试环境的配置
    function getOrCreateAnvilEthConfig()
        public
        returns (NetworkConfig memory anvilNetworkConfig)
    {
        // 检查是否已设置活动的网络配置
        if (activeNetworkConfig.vrfCoordinatorV2 != address(0)) {
            return activeNetworkConfig;
        }

        uint96 baseFee = 0.25 ether; // 基础费用
        uint96 gasPriceLink = 1e9; // gas 价格

        vm.startBroadcast(DEFAULT_ANVIL_PRIVATE_KEY); // 开始广播交易
        VRFCoordinatorV2Mock vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(
            baseFee,
            gasPriceLink
        );

        LinkToken link = new LinkToken();
        vm.stopBroadcast(); // 停止广播

        // 触发事件，表明创建了模拟的 VRF 协调器
        emit HelperConfig__CreatedMockVRFCoordinator(
            address(vrfCoordinatorV2Mock)
        );

        // 设置 Anvil 网络配置
        anvilNetworkConfig = NetworkConfig({
            subscriptionId: 0, // 默认情况下脚本将创建订阅
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, // 这里的 gas lane 实际上不重要
            automationUpdateInterval: 30, // 更新间隔为30秒
            raffleEntranceFee: 0.01 ether,
            callbackGasLimit: 500000, // 回调的 gas 限制为 500,000
            vrfCoordinatorV2: address(vrfCoordinatorV2Mock),
            link: address(link),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
