// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "rain.interface.orderbook/ierc3156/IERC3156FlashLender.sol";
import "rain.interface.orderbook/ierc3156/IERC3156FlashBorrower.sol";

import "./OrderBookFlashBorrower.sol";

contract ZeroExOrderBookFlashBorrower is OrderBookFlashBorrower {
    using SafeERC20 for IERC20;
    using Address for address;

    /// 0x exchange proxy as per reference implementation.
    address public zeroExExchangeProxy;

    function beforeInitialize(bytes memory data_) internal virtual override {
        (address zeroExExchangeProxy_) = abi.decode(data_, (address));
        zeroExExchangeProxy = zeroExExchangeProxy_;
    }

    function exchange(TakeOrdersConfig memory takeOrders_, bytes memory data_) internal virtual override {
        (address zeroExSpender_, bytes memory zeroExData_) = abi.decode(data_, (address, bytes));
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        IERC20(takeOrders_.input).safeApprove(zeroExSpender_, type(uint256).max);
        bytes memory returnData_ = zeroExExchangeProxy.functionCallWithValue(zeroExData_, address(this).balance);
        (returnData_);
    }

    /// Allow receiving gas.
    fallback() external onlyNotInitializing {}
}
