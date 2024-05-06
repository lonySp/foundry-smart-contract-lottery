// SPDX-License-Identifier: MIT

// @dev 该合约已经适配以适用于dappTools
pragma solidity ^0.8.0;

// 导入 ERC20 标准合约
import {ERC20} from "@solmate/tokens/ERC20.sol";

// 定义 ERC677Receiver 接口，用于接收带有额外数据的代币转账
interface ERC677Receiver {
    function onTokenTransfer(
        address _sender,
        uint256 _value,
        bytes memory _data
    ) external;
}

// LinkToken 合约，继承自 ERC20 合约
contract LinkToken is ERC20 {
    uint256 constant INITIAL_SUPPLY = 1000000000000000000000000; // 初始供应量
    uint8 constant DECIMALS = 18; // 代币的小数位数

    // 构造函数，初始化代币的名称、代号和小数位数，并向部署者铸造初始供应量
    constructor() ERC20("LinkToken", "LINK", DECIMALS) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    // 转账事件，包括额外的数据字段
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value,
        bytes data
    );

    /**
     * @dev 向合约地址转账代币并附带额外数据。如果接收方是合约，则触发回调。
     * @param _to 转账目标地址。
     * @param _value 转账金额。
     * @param _data 附加数据。
     */
    function transferAndCall(
        address _to,
        uint256 _value,
        bytes memory _data
    ) public virtual returns (bool success) {
        super.transfer(_to, _value); // 调用 ERC20 标准的转账函数
        emit Transfer(msg.sender, _to, _value, _data); // 发出转账事件
        if (isContract(_to)) { // 如果接收地址是合约，则进行回调
            contractFallback(_to, _value, _data);
        }
        return true;
    }

    // PRIVATE

    // 私有函数，用于处理合约回调
    function contractFallback(
        address _to,
        uint256 _value,
        bytes memory _data
    ) private {
        ERC677Receiver receiver = ERC677Receiver(_to);
        receiver.onTokenTransfer(msg.sender, _value, _data); // 触发接收合约的 onTokenTransfer 函数
    }

    // 检查一个地址是否是合约
    function isContract(address _addr) private view returns (bool hasCode) {
        uint256 length;
        assembly {
            length := extcodesize(_addr) // 获取地址的代码大小
        }
        return length > 0;
    }
}
