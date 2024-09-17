// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {CCIP_SWAP} from "../src/CCIP_SWAP.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
contract CCIP_SWAPTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    struct BridgeInfo {
        address reciever;
        uint64 destinationChainSelector;
        bytes message;
    }
    CCIP_SWAP hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    // CCIP STORAGE
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    uint256 public sourceFork;
    uint256 public destinationFork;
    address public alice;
    address public bob;
    IRouterClient public sourceRouter;
    uint64 public destinationChainSelector;
    BurnMintERC677Helper public sourceCCIPBnMToken;
    BurnMintERC677Helper public destinationCCIPBnMToken;
    IERC20 public sourceLinkToken;

    function setUp() public {
        string memory DESTINATION_RPC_URL = vm.envString(
            "ETHEREUM_SEPOLIA_RPC_URL"
        );
        string memory SOURCE_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        destinationFork = vm.createSelectFork(DESTINATION_RPC_URL);
        sourceFork = vm.createFork(SOURCE_RPC_URL);


        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        Register.NetworkDetails
            memory destinationNetworkDetails = ccipLocalSimulatorFork
                .getNetworkDetails(block.chainid);

        destinationCCIPBnMToken = BurnMintERC677Helper(
            destinationNetworkDetails.ccipBnMAddress
        );
        destinationChainSelector = destinationNetworkDetails.chainSelector;

        vm.selectFork(sourceFork);
        Register.NetworkDetails
            memory sourceNetworkDetails = ccipLocalSimulatorFork
                .getNetworkDetails(block.chainid);
        sourceCCIPBnMToken = BurnMintERC677Helper(
            sourceNetworkDetails.ccipBnMAddress
        );
        sourceLinkToken = IERC20(sourceNetworkDetails.linkAddress);
        sourceRouter = IRouterClient(sourceNetworkDetails.routerAddress);

        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        // deployMintAndApprove2Currencies();

        deployPosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)
        );
        bytes memory constructorArgs = abi.encode(
            manager,
            sourceRouter,
            address(sourceLinkToken)
        ); //Add all the necessary constructor arguments from the hook
        deployCodeTo("CCIP_SWAP.sol:CCIP_SWAP", constructorArgs, flags);
        hook = CCIP_SWAP(flags);

        Currency currency0 = Currency.wrap(address(0));
        Currency currency1 = Currency.wrap(address(sourceCCIPBnMToken));

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);
        deal(address(this), 100 ether);
        deal(address(posm), 100 ether);
        vm.label(address(sourceCCIPBnMToken), "Token1");
        vm.label(address(sourceLinkToken), "LINK");
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));
        sourceCCIPBnMToken.drip(address(this));

        approvePosmCurrency(currency1);
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(key.toId());
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickLower),
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickUpper),
            10e18,
            10e18
        );
        (tokenId, ) = posm.mint(
            key,
            LIQUIDITY_PARAMS.tickLower,
            LIQUIDITY_PARAMS.tickUpper,
            liquidityDelta,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testCounterHooks() public {
        vm.selectFork(sourceFork);
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(hook), 10 ether);


        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BridgeInfo memory _bridgeInfo = BridgeInfo(
            address(this),
            destinationChainSelector,
            new bytes(0)
        );
        bytes memory hookData = abi.encode(_bridgeInfo);
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            hookData
        );

        uint256 balanceBefore = sourceCCIPBnMToken.balanceOf(address(this));
        ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationFork);
        uint256 balanceAfter = destinationCCIPBnMToken.balanceOf(address(this));

        console.log("balanceBefore: ", balanceBefore);
        console.log("balanceAfter: ", balanceAfter);
        assert(balanceAfter > balanceBefore);

    }

    fallback() external payable {}
}
