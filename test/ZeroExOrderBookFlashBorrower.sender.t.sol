// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "forge-std/Test.sol";
import "../src/ZeroExOrderBookFlashBorrower.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "rain.interface.orderbook/IOrderBookV1.sol";

contract Token is ERC20 {
    constructor() ERC20("Token", "TKN") {}

    function mint(address receiver_, uint256 amount_) external {
        _mint(receiver_, amount_);
    }
}

contract MockOrderBook is IOrderBookV1 {
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        receiver.onFlashLoan(msg.sender, token, amount, 0, data);
        return true;
    }

    function takeOrders(TakeOrdersConfig calldata config) external returns (uint256 totalInput, uint256 totalOutput) {
        return (0, 0);
    }

    function addOrder(OrderConfig calldata config) external {}
    function clear(
        Order memory alice,
        Order memory bob,
        ClearConfig calldata clearConfig,
        SignedContext[] memory aliceSignedContext,
        SignedContext[] memory bobSignedContext
    ) external {}
    function deposit(DepositConfig calldata config) external {}
    function flashFee(address token, uint256 amount) external view returns (uint256) {}
    function maxFlashLoan(address token) external view returns (uint256) {}
    function removeOrder(Order calldata order) external {}

    function vaultBalance(address owner, address token, uint256 id) external view returns (uint256 balance) {}
    function withdraw(WithdrawConfig calldata config) external {}
}

contract Mock0xProxy {
    fallback() external {
        Address.sendValue(payable(msg.sender), address(this).balance);
    }
}

contract ZeroExOrderBookFlashBorrowerTest is Test {
    function testTakeOrdersSender() public {
        MockOrderBook ob_ = new MockOrderBook();
        Mock0xProxy proxy_ = new Mock0xProxy();

        Token input_ = new Token();
        Token output_ = new Token();

        ZeroExOrderBookFlashBorrower arb_ = new ZeroExOrderBookFlashBorrower(ZeroExOrderBookFlashBorrowerConfig(
            address(ob_), address(proxy_)
        ));

        arb_.arb(
            TakeOrdersConfig(
                address(output_), address(input_), 0, type(uint256).max, type(uint256).max, new TakeOrderConfig[](0)
            ),
            address(proxy_),
            ""
        );
    }

    // Allow receiving funds at end of arb.
    fallback() external {}
}
