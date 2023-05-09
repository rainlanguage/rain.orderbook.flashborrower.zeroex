// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "rain.interface.orderbook/ierc3156/IERC3156FlashLender.sol";
import "rain.interface.orderbook/ierc3156/IERC3156FlashBorrower.sol";

import "./OrderBookFlashBorrower.sol";

interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

contract CurveOrderBookFlashBorrower is OrderBookFlashBorrower {
    using SafeERC20 for IERC20;
    using Address for address;

    ICurvePool public pool;

    function beforeInitialize(bytes memory data_) internal virtual override {
        (address pool_) = abi.decode(data_, (address));
        pool = ICurvePool(pool_);
    }

    function exchange(TakeOrdersConfig memory takeOrders_, bytes memory data_) internal virtual override {
        (int128 i_, int128 j_) = abi.decode(data_, (int128, int128));
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        IERC20(takeOrders_.input).safeApprove(address(pool), type(uint256).max);
        // OB will handle slippage.
        pool.exchange(i_, j_, takeOrders_.minimumInput, 0);
    }

    /// Allow receiving gas.
    fallback() external onlyNotInitializing {}
}
