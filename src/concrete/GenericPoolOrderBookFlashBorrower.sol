// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "rain.orderbook/src/interface/ierc3156/IERC3156FlashLender.sol";
import "rain.orderbook/src/interface/ierc3156/IERC3156FlashBorrower.sol";

import "src/abstract/OrderBookFlashBorrower.sol";

contract GenericPoolOrderBookFlashBorrower is OrderBookFlashBorrower {
    using SafeERC20 for IERC20;
    using Address for address;

    function _exchange(TakeOrdersConfig memory takeOrders, bytes memory data) internal virtual override {
        (address spender, address pool, bytes memory callData) = abi.decode(data, (address, address, bytes));

        IERC20(takeOrders.input).safeApprove(spender, 0);
        IERC20(takeOrders.input).safeApprove(spender, type(uint256).max);
        bytes memory returnData = pool.functionCallWithValue(callData, address(this).balance);
        // Nothing can be done with returnData as 3156 does not support it.
        (returnData);
        IERC20(takeOrders.input).safeApprove(spender, 0);
    }

    /// Allow receiving gas.
    fallback() external onlyNotInitializing {}
}
