// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13; 

import "lib/forge-std/src/Test.sol"; 
import "lib/forge-std/src/console.sol";  
import "lib/rain.interface.orderbook/src/IOrderBookV2.sol" ;  
import "lib/rain.interface.interpreter/src/IExpressionDeployerV1.sol" ;  
import "lib/sol.lib.memory/src/LibUint256Array.sol" ;
import "lib/forge-std/src/interfaces/IERC20.sol" ; 
import "src/LibFixedPointMath.sol" ;   

 
contract Curve is Test{ 

    using LibFixedPointMath for uint256;

    // the identifiers of the forks
    uint256 mainnetFork; 
    string MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");  

    event Deposit(address sender, DepositConfig config);  

    event Withdraw(address sender, WithdrawConfig config, uint256 amount);

    event AddOrder(address sender, IExpressionDeployerV1 expressionDeployer, Order order, uint256 orderHash);


    address deployer = address(0xA25f22b0Ab021A9cA1513C892e6FaacC50e92907) ; 

    // Tokens which are already deployed on mumbai. 
    // Can be deployed natively or can be cloned from flow. 
    address tokenA = address(0x05cE0B29D94Cb8b156638D06336228b935212652) ;  
    address tokenB = address(0x3b55b7b2Eec07cf5F0634B130eFbb1A1e4eDEd0a) ; 

    address ob = address(0xaCf6069F4A6A9c66DB8B9a087592278bbccdE5c3)  ;  
    address expDep = address(0x32BA42606ca2A2b91f28eBb0472a683b346E7cC7) ; 


    function setUp() public {
        mainnetFork = vm.createFork(MUMBAI_RPC_URL);
    }    


    function getTokenA(address account, uint256 amount) internal { 

        vm.prank(deployer); 
        // Deposit TokenA
        IERC20 TokenA = IERC20(tokenA) ;  
        TokenA.transfer(account, amount); 
        vm.stopPrank(); 

        assertEq(TokenA.balanceOf(account),amount);  

        vm.prank(account); 
        //Give allowance to OB
        TokenA.approve(ob, amount); 
        vm.stopPrank();  

        assertEq(TokenA.allowance(account, ob),amount);  
        
    }

    function getTokenB(address account, uint256 amount) internal { 

        vm.prank(deployer); 

        // Deposit TokenB
        IERC20 TokenB = IERC20(tokenB) ;  
        TokenB.transfer(account, amount);
        
        vm.stopPrank(); 

        assertEq(TokenB.balanceOf(account),amount); 

        vm.prank(account); 
        //Give allowance to OB
        TokenB.approve(ob, amount); 
        vm.stopPrank();  

        assertEq(TokenB.allowance(account, ob),amount);   

    }   

    function testDeposit(address alice_, uint256 vaultId_, uint256 depositAmount_) public {    

            
        vm.assume(depositAmount_ < 10000) ; 
        vm.assume(alice_ != address(0)) ; 

        vm.selectFork(mainnetFork);
        vm.rollFork(34_191_503);   

        getTokenB(alice_,depositAmount_) ; 
         
        IOrderBookV2 orderBook_ = IOrderBookV2(ob); 

        vm.prank(alice_); 
        DepositConfig memory depositConfigAlice = DepositConfig(tokenB,vaultId_,depositAmount_) ;  

        vm.expectEmit(false, false, false, true);
        emit Deposit(alice_,depositConfigAlice);   
        orderBook_.deposit(depositConfigAlice) ;  

        assertEq(orderBook_.vaultBalance(alice_,tokenB,vaultId_),depositAmount_);    

        vm.stopPrank() ; 

    }  
    
    function testWithdraw(address alice_, uint256 vaultId_, uint256 depositAmount_) public {    

        vm.assume(depositAmount_ < 1000e18) ; 
        vm.assume(alice_ != address(0)) ; 

        vm.selectFork(mainnetFork);
        vm.rollFork(34_191_503);   

        getTokenB(alice_,depositAmount_) ; 
          
        IOrderBookV2 orderBook_ = IOrderBookV2(ob);  

        // Deposit
        {
            vm.prank(alice_); 

            DepositConfig memory depositConfigAlice = DepositConfig(tokenB,vaultId_,depositAmount_) ;   

            //Check Event Data
            vm.expectEmit(false, false, false, true);
            emit Deposit(alice_,depositConfigAlice);   
            orderBook_.deposit(depositConfigAlice) ;   

            assertEq(orderBook_.vaultBalance(alice_,tokenB,vaultId_),depositAmount_);   

            vm.stopPrank() ; 
        } 

        // Withdraw
        {
            vm.prank(alice_);  

            WithdrawConfig memory withdrawAliceConfig = WithdrawConfig(tokenB,vaultId_,depositAmount_) ; 
            
            // Check Event Data 
            vm.expectEmit(false, false, false, true);
            emit Withdraw(alice_,withdrawAliceConfig,depositAmount_);   
            orderBook_.withdraw(withdrawAliceConfig) ;  

            assertEq(orderBook_.vaultBalance(alice_,tokenB,vaultId_),0);   
            assertEq(IERC20(tokenB).balanceOf(alice_),depositAmount_);   

            vm.stopPrank() ;  
        }

    }       

    function testAddTakeOrder(
        address alice_,
        address bob_,
        uint256 vaultId_,
        uint256 depositAmount_,
        uint256 ratio_
    ) public {   
        
        // wip depositAmount
        vm.assume(depositAmount_ <= 1000e18) ;  

        vm.assume(alice_ != address(0)) ; 
        vm.assume(bob_ != address(0)) ;  

        // wip ratio
        vm.assume(ratio_ > 1 && ratio_ < 11e20 ) ; 


        vm.selectFork(mainnetFork);
        vm.rollFork(34_191_503);   

        getTokenB(alice_,depositAmount_) ; 

         
        IOrderBookV2 orderBook_ = IOrderBookV2(ob); 

        // Deposit Tokens 
        {
            vm.prank(alice_); 
            DepositConfig memory depositConfigAlice = DepositConfig(tokenB,vaultId_,depositAmount_) ;    
            orderBook_.deposit(depositConfigAlice) ; 

            assertEq(orderBook_.vaultBalance(alice_,tokenB,vaultId_),depositAmount_);   

            vm.stopPrank() ; 
        }

        // Build Order Conifg Object .  
          
          // Continued in later scope 
          Vm.Log memory addOrderEvent ;
        {
            IO[] memory validInputs = new IO[](1); 
            validInputs[0] =  IO(tokenA,18,vaultId_)  ;    

            IO[] memory validOutputs = new IO[](1); 
            validOutputs[0] =  IO(tokenB,18,vaultId_)  ;    

            uint256[] memory constants = new uint256[](2) ; 
            constants[0] = 11e70 ; 
            constants[1] = ratio_ ;

            bytes[] memory sources = new bytes[](2) ; 
            sources[0] = hex"000d0001000d0003" ; 
            sources[1] = hex"" ;
            
            bytes memory meta = hex"ff0a89c674ee7874" ;   
    
            EvaluableConfig memory config = EvaluableConfig(IExpressionDeployerV1(expDep),sources,constants) ; 

            OrderConfig memory aliceOrder = OrderConfig(validInputs,validOutputs,config,meta) ;   
        

            // Start recording logs
            vm.recordLogs(); 

            // Alice Places Orders
            vm.prank(alice_) ;  
            orderBook_.addOrder(aliceOrder) ;    
            vm.stopPrank();    

            Vm.Log[] memory entries = vm.getRecordedLogs();  

            addOrderEvent = entries[2] ;  
        } 

        // Deposit For Bob
        {
            uint256 depositAmountBob = depositAmount_.fixedPointMul(
                ratio_ ,
                Math.Rounding.Up
            ) ; 

            getTokenA(bob_,depositAmountBob) ; 
        }
        
       {
            (
            address sender_,
            IExpressionDeployerV1 deployer_,
            Order memory order_, 
            uint256 orderHash_
            ) = abi.decode(
                addOrderEvent.data,
                (
                    address,
                    IExpressionDeployerV1,
                    Order,
                    uint256
                )
            ) ;  
            
            // Bob Takes Orders.
            vm.prank(bob_) ; 
            TakeOrderConfig[] memory bobTakeOrder = new TakeOrderConfig[](1);   
            SignedContextV1[] memory context = new SignedContextV1[](0);   

            bobTakeOrder[0] =  TakeOrderConfig(order_,0,0,context) ;

            TakeOrdersConfig memory takeOrder = TakeOrdersConfig(tokenA,tokenB,depositAmount_,depositAmount_,1e18,bobTakeOrder) ; 

            orderBook_.takeOrders(takeOrder)  ;

            vm.stopPrank() ; 

       }    

    }  

    function testAddClearOrder(
        address alice_ ,
        address bob_ ,
        address carol ,
        uint256 aliceVaultId_,
        uint256 bobVaultId_,
        uint256 carolInputVaultId_,
        uint256 carolOutputVaultId_,
        uint256 depositAmount_ 
    ) public { 

         // wip depositAmount
        vm.assume(depositAmount_ <= 1000e18) ;  

        vm.assume(alice_ != address(0)) ; 
        vm.assume(bob_ != address(0)) ;  
        vm.assume(carol != address(0)) ;  

        uint256 ratio_ = FIXED_POINT_ONE ; 

        vm.selectFork(mainnetFork);
        vm.rollFork(34_191_503);   
 
        IOrderBookV2 orderBook_ = IOrderBookV2(ob); 

        // Deposit Tokens for alice and bob 
        {   
            getTokenB(alice_,depositAmount_) ;  
            getTokenA(bob_,depositAmount_) ;  


            vm.prank(alice_); 
            DepositConfig memory depositConfigAlice = DepositConfig(tokenB,aliceVaultId_,depositAmount_) ;    
            orderBook_.deposit(depositConfigAlice) ; 
            assertEq(orderBook_.vaultBalance(alice_,tokenB,aliceVaultId_),depositAmount_);   
            vm.stopPrank() ;  

            vm.prank(bob_); 
            DepositConfig memory depositConfigBob = DepositConfig(tokenA,bobVaultId_,depositAmount_) ;    
            orderBook_.deposit(depositConfigBob) ; 
            assertEq(orderBook_.vaultBalance(bob_,tokenA,bobVaultId_),depositAmount_);   
            vm.stopPrank() ; 
        }  

        // Start recording logs
        vm.recordLogs(); 
        
        // Alice Add Order 
          Vm.Log memory aliceAddOrderEvent ;
        {
            OrderConfig memory aliceOrder ;
            {
                IO[] memory validInputs = new IO[](1); 
                validInputs[0] =  IO(tokenA,18,aliceVaultId_)  ;    

                IO[] memory validOutputs = new IO[](1); 
                validOutputs[0] =  IO(tokenB,18,aliceVaultId_)  ;    

                uint256[] memory constants = new uint256[](2) ; 
                constants[0] = 11e70 ; 
                constants[1] = ratio_ ;

                bytes[] memory sources = new bytes[](2) ; 
                sources[0] = hex"000d0001000d0003" ; 
                sources[1] = hex"" ;
                
                bytes memory meta = hex"ff0a89c674ee7874" ;   
        
                EvaluableConfig memory config = EvaluableConfig(IExpressionDeployerV1(expDep),sources,constants) ; 

                aliceOrder = OrderConfig(validInputs,validOutputs,config,meta) ; 
            }  
            {
                // Alice Places Orders
                vm.prank(alice_) ;  
                orderBook_.addOrder(aliceOrder) ;    
                vm.stopPrank();    

                Vm.Log[] memory entries = vm.getRecordedLogs();  

                aliceAddOrderEvent = entries[2] ;  
            }
            
        } 

        // Bob Add Order 
          Vm.Log memory bobAddOrderEvent ;
        { 
            OrderConfig memory bobOrder ;

            {
                IO[] memory validInputs = new IO[](1); 
                validInputs[0] =  IO(tokenB,18,bobVaultId_)  ;    

                IO[] memory validOutputs = new IO[](1); 
                validOutputs[0] =  IO(tokenA,18,bobVaultId_)  ;    

                uint256[] memory constants = new uint256[](2) ; 
                constants[0] = 11e70 ; 
                constants[1] = FIXED_POINT_ONE.fixedPointDiv(ratio_,Math.Rounding.Up) ; 

                bytes[] memory sources = new bytes[](2) ; 
                sources[0] = hex"000d0001000d0003" ; 
                sources[1] = hex"" ;
                
                bytes memory meta = hex"ff0a89c674ee7874" ;   
        
                EvaluableConfig memory config = EvaluableConfig(IExpressionDeployerV1(expDep),sources,constants) ; 

                bobOrder = OrderConfig(validInputs,validOutputs,config,meta) ;
            }   
            { 
                // Bob Places Orders
                vm.prank(bob_) ;  
                orderBook_.addOrder(bobOrder) ;    
                vm.stopPrank();    

                Vm.Log[] memory entries = vm.getRecordedLogs();  

                bobAddOrderEvent = entries[2] ;  
            }    
        }  

        // Clear Order 
        {  
            Order memory orderA_ ; 
            Order memory orderB_ ; 
            {
                (
                    address senderA_,
                    IExpressionDeployerV1 deployerA_,
                    Order memory orderAlice_ , 
                    uint256 orderHashA_
                ) = abi.decode(
                    aliceAddOrderEvent.data,
                    (
                        address,
                        IExpressionDeployerV1,
                        Order,
                        uint256
                    )
                ) ;  
                orderA_ = orderAlice_ ;
            }

            {
                (
                    address senderB_,
                    IExpressionDeployerV1 deployerB_,
                    Order memory orderBob_, 
                    uint256 orderHashB_
                ) = abi.decode(
                    bobAddOrderEvent.data,
                    (
                        address,
                        IExpressionDeployerV1,
                        Order,
                        uint256
                    )
                ) ; 
                orderB_ = orderBob_ ;

            }

            
            ClearConfig memory clearConfig = ClearConfig(0,0,0,0,carolInputVaultId_,carolOutputVaultId_) ;  

            vm.prank(carol) ;  

            orderBook_.clear(
                orderA_,
                orderB_,
                clearConfig,
                new SignedContextV1[](0),
                new SignedContextV1[](0)
            );  

            vm.stopPrank();  



        }

        
    }                                   

}