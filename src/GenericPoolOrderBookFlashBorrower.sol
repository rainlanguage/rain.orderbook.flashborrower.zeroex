// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "rain.interface.orderbook/ierc3156/IERC3156FlashLender.sol";
import "rain.interface.orderbook/ierc3156/IERC3156FlashBorrower.sol";

import "./OrderBookFlashBorrower.sol";

contract GenericPoolOrderBookFlashBorrower is OrderBookFlashBorrower {
    using SafeERC20 for IERC20;
    using Address for address;

    function exchange(TakeOrdersConfig memory takeOrders, bytes memory data) internal virtual override {
        (address pool, bytes memory callData) = abi.decode(data, (address, bytes));

        IERC20(takeOrders.input).safeApprove(pool, type(uint256).max);
        bytes memory returnData = pool.functionCall(callData);
        // Nothing can be done with returnData.
        (returnData);
    }

    /// Allow receiving gas.
    fallback() external onlyNotInitializing {}
}
