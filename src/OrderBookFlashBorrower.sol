// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import "rain.interface.orderbook/IOrderBookV2.sol";
import "rain.interface.factory/ICloneableV1.sol";
import "rain.interface.interpreter/LibEncodedDispatch.sol";
import "rain.interface.interpreter/LibContext.sol";

/// Thrown when the lender is not the trusted `OrderBook`.
/// @param badLender The untrusted lender calling `onFlashLoan`.
error BadLender(address badLender);

/// Thrown when the initiator is not `ZeroExOrderBookFlashBorrower`.
/// @param badInitiator The untrusted initiator of the flash loan.
error BadInitiator(address badInitiator);

/// Thrown when the flash loan fails somehow.
error FlashLoanFailed();

/// Thrown when calling functions while the contract is still initializing.
error Initializing();

/// Thrown when the swap fails.
error SwapFailed();

/// Thrown when the minimum output for the sender is not met after the arb.
error MinimumOutput(uint256 minimum, uint256 actual);

struct OrderBookFlashBorrowerConfig {
    address orderBook;
    EvaluableConfig evaluableConfig;
    bytes implementationData;
}

SourceIndex constant BEFORE_ARB_SOURCE_INDEX = SourceIndex.wrap(0);
uint256 constant BEFORE_ARB_MIN_OUTPUTS = 0;
uint16 constant BEFORE_ARB_MAX_OUTPUTS = 0;

/// @title OrderBookFlashBorrower
/// @notice Base contract that liq-source specifialized contracts can extend to
/// provide flash loan based arbitrage against external liquidity sources to fill
/// orderbook orders.
///
/// For example consider a simple order:
///
/// input = DAI
/// output = USDT
/// IORatio = 1.01e18
/// Order amount = 100e18
///
/// Assume external liq is offering 102 DAI per USDT so it exceeds the IO ratio
/// but the order itself has no way to interact with the external contract.
/// The `OrderBookFlashBorrower` can:
///
/// - Flash loan 100 USDT from `Orderbook`
/// - Sell the 100 USDT for 102 DAI on external liq
/// - Take the order, giving 101 DAI and paying down 100 USDT loan
/// - Keep 1 DAI profit
contract OrderBookFlashBorrower is IERC3156FlashBorrower, ICloneableV1, ReentrancyGuard, Initializable {
    using Address for address;
    using SafeERC20 for IERC20;

    event Initialize(address sender, OrderBookFlashBorrowerConfig config);

    /// `OrderBook` contract to lend and arb against.
    IOrderBookV2 public sOrderBook;

    IInterpreterV1 public sI9r;
    IInterpreterStoreV1 public sI9rStore;
    EncodedDispatch public sI9rDispatch;

    /// Initialize immutable contracts to arb and trade against.
    constructor() {
        _disableInitializers();
    }

    /// Hook called before initialize happens. Inheriting contracts can perform
    /// internal state maintenance before any external contract calls are made.
    /// @param data Arbitrary bytes the child may use to initialize.
    function _beforeInitialize(bytes memory data) internal virtual {}

    /// Standard initialization as
    function initialize(bytes memory data_) external initializer nonReentrant {
        (OrderBookFlashBorrowerConfig memory config_) = abi.decode(data_, (OrderBookFlashBorrowerConfig));
        _beforeInitialize(config_.implementationData);

        orderBook = IOrderBookV2(config_.orderBook);

        emit Initialize(msg.sender, config_);

        if (config_.evaluableConfig.sources.length > 0 && config_.evaluableConfig.sources[0].length > 0) {
            address expression_;
            uint256[] memory entrypoints_ = new uint256[](1);
            // 0 outputs.
            entrypoints_[SourceIndex.unwrap(BEFORE_ARB_SOURCE_INDEX)] = BEFORE_ARB_MIN_OUTPUTS;
            // We have to trust the deployer because it produces the expression
            // address for the dispatch anyway.
            // All external functions on this contract have `onlyNotInitializing`
            // modifier on them so can't be reentered here anyway.
            //slither-disable-next-line reentrancy-benign
            (interpreter, store, expression_) = config_.evaluableConfig.deployer.deployExpression(
                config_.evaluableConfig.sources, config_.evaluableConfig.constants, entrypoints_
            );
            dispatch = LibEncodedDispatch.encode(expression_, BEFORE_ARB_SOURCE_INDEX, BEFORE_ARB_MAX_OUTPUTS);
        }
    }

    modifier onlyNotInitializing() {
        if (_isInitializing()) {
            revert Initializing();
        }
        _;
    }

    ///slither-disable-next-line dead-code
    function _exchange(TakeOrdersConfig memory takeOrders_, bytes memory data_) internal virtual {}

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(address initiator_, address, uint256, uint256, bytes calldata data_)
        external
        onlyNotInitializing
        returns (bytes32)
    {
        if (msg.sender != address(orderBook)) {
            revert BadLender(msg.sender);
        }
        if (initiator_ != address(this)) {
            revert BadInitiator(initiator_);
        }

        (TakeOrdersConfig memory takeOrders_, bytes memory exchangeData_) = abi.decode(data_, (TakeOrdersConfig, bytes));

        exchange(takeOrders_, exchangeData_);

        // At this point `exchange` should have sent the tokens required to match
        // the orders so take orders now.
        // We don't do anything with the total input/output amounts here because
        // the flash loan itself will take back what it needs, and we simply
        // keep anything left over according to active balances.
        (uint256 totalInput_, uint256 totalOutput_) = orderBook.takeOrders(takeOrders_);
        (totalInput_, totalOutput_);

        return ON_FLASH_LOAN_CALLBACK_SUCCESS;
    }

    /// Anon can call the `arb` function with the orders to take on the
    /// `OrderBook` side and the 0x data required to provide the external
    /// liquidity to complete the trade. Any profits will be forwarded to
    /// `msg.sender` at the completion of the arbitrage. The `msg.sender` is
    /// responsible for all matchmaking, gas, 0x interactions and other
    /// onchain and offchain responsibilities related to the transaction.
    /// `ZeroExOrderBookFlashBorrower` only provides the necessary logic to
    /// faciliate the flash loan, external trade and repayment.
    /// @param takeOrders_ As per `IOrderBookV2.takeOrders`.
    /// @param minimumSenderOutput_ The minimum output that must be sent to the sender
    /// by the end of the arb call.
    function arb(TakeOrdersConfig calldata takeOrders_, uint256 minimumSenderOutput_, bytes calldata exchangeData_)
        external
        nonReentrant
        onlyNotInitializing
    {
        // This data needs to be encoded so that it can be passed to the
        // `onFlashLoan` callback.
        bytes memory data_ = abi.encode(takeOrders_, exchangeData_);
        // The token we receive from taking the orders is what we will use to
        // repay the flash loan.
        address flashLoanToken_ = takeOrders_.input;
        // We can't repay more than the minimum that the orders are going to
        // give us and there's no reason to borrow less.
        uint256 flashLoanAmount_ = takeOrders_.minimumInput;

        EncodedDispatch dispatch_ = dispatch;
        if (EncodedDispatch.unwrap(dispatch_) > 0) {
            (uint256[] memory stack_, uint256[] memory kvs_) = interpreter.eval(
                store,
                DEFAULT_STATE_NAMESPACE,
                dispatch_,
                LibContext.build(new uint256[][](0), new SignedContextV1[](0))
            );
            require(stack_.length == 0);
            if (kvs_.length > 0) {
                store.set(DEFAULT_STATE_NAMESPACE, kvs_);
            }
        }

        // This is overkill to infinite approve every time.
        // @todo make this hammer smaller.
        IERC20(takeOrders_.output).safeApprove(address(orderBook), type(uint256).max);

        if (!orderBook.flashLoan(this, flashLoanToken_, flashLoanAmount_, data_)) {
            revert FlashLoanFailed();
        }

        // Send all unspent input tokens to the sender.
        uint256 inputBalance_ = IERC20(takeOrders_.input).balanceOf(address(this));
        if (inputBalance_ > 0) {
            IERC20(takeOrders_.input).safeTransfer(msg.sender, inputBalance_);
        }
        // Send all unspent output tokens to the sender.
        uint256 outputBalance_ = IERC20(takeOrders_.output).balanceOf(address(this));
        if (outputBalance_ < minimumSenderOutput_) {
            revert MinimumOutput(minimumSenderOutput_, outputBalance_);
        }
        if (outputBalance_ > 0) {
            IERC20(takeOrders_.output).safeTransfer(msg.sender, outputBalance_);
        }

        // Send all unspent 0x protocol fees to the sender.
        // Slither false positive here. This is near verbatim from the reference
        // implementation. We want to send everything to the sender because the
        // borrower contract should be empty of all gas and tokens between uses.
        // Issue also seems related https://github.com/crytic/slither/issues/1658
        // as here we assume all balances of `ZeroExOrderBookFlashBorrower` were
        // first either sent by `msg.sender` or the result of a successful arb
        // via. the `flashLoan` call above.
        // If for some strange reason you send tokens or ETH directly to this
        // contract other than for the intended purpose, expect your funds to be
        // immediately drained by the next caller.
        Address.sendValue(payable(msg.sender), address(this).balance);
    }
}
