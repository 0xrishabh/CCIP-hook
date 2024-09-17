// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey, Currency as PoolKeyCurrency} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
/**
 * @title Hook for bridging from tokens after swap
 * @author Rishabh Shukla
 */
contract CCIP_SWAP is BaseHook {
    using PoolIdLibrary for PoolKey;

    struct EVMTokenAmount {
        address token; // token address on the local chain.
        uint256 amount; // Amount of tokens.
    }
    struct EVM2AnyMessage {
        bytes receiver; // abi.encode(receiver address) for dest EVM chains
        bytes data; // Data payload
        EVMTokenAmount[] tokenAmounts; // Token transfers
        address feeToken; // Address of feeToken. address(0) means you will send msg.value.
        bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV2)
    }

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------
    IRouterClient immutable CCIP_ROUTER;
    address immutable LINK_TOKEN;

    struct BridgeInfo {
        address reciever;
        uint64 destinationChainSelector;
        bytes message;
    }

    constructor(
        IPoolManager _poolManager,
        IRouterClient _ccipRouter,
        address _linkToken
    ) BaseHook(_poolManager) {
        CCIP_ROUTER = _ccipRouter;
        LINK_TOKEN = _linkToken;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        // Decode hookData to a struct named bridgeInfo

        BridgeInfo memory bridgeInfo = abi.decode(hookData, (BridgeInfo));

        // Get the amountOut Token & amount
        Currency tokenOut = params.zeroForOne ? key.currency1 : key.currency0;
        int128 amount = params.zeroForOne ? delta.amount1() : delta.amount0();

        // console.log("working");
        // console.logInt(delta.amount0());
        // console.logInt(delta.amount1());

        // Calculate Bridiging fees
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount(
            Currency.unwrap(tokenOut),
            uint256(int256(amount))
        );

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(bridgeInfo.reciever),
            data: bridgeInfo.message,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1(100_000)),
            feeToken: address(LINK_TOKEN)
        });

        // Get the fee required to send the CCIP message
        uint256 fees = CCIP_ROUTER.getFee(
            bridgeInfo.destinationChainSelector,
            message
        );

        // Enforce the i_token approval is enough from sender

        IPoolManager(msg.sender).take(tokenOut, address(this), uint256(int256(amount)));
        IERC20(Currency.unwrap(tokenOut)).approve(
            address(CCIP_ROUTER),
            uint256(int256(amount))
        );
        IERC20(LINK_TOKEN).approve(address(CCIP_ROUTER), fees);

        // Make the bridiging Transaction
        CCIP_ROUTER.ccipSend(bridgeInfo.destinationChainSelector, message);
        return (this.afterSwap.selector, amount);
    }
}
