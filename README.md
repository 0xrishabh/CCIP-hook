# CCIP + v4 HOOK swap

This is for the project which wants to launch its tokens on the ETH mainnet for discovery and availability and will now still be able to access the accessibility and cheap Fees of L2. Not only that but with CCIP + hook, the ease for the end user is as good as it goes as there is no switching and hopping on five other platforms, now it can be done from one platform with one click!

# Future Work

1. CCIP take fees in LINK or native, since the hooks are so connected to uniswap already we can easily increase the supported fees token by simply accepting token X and swapping it for LINK or native.
2. Create SDK for projects that want to integrate, the SDK will take care of all the data coming in or going to hooks, including function parameters & events emission! 
3. Create a Reciever contract and deploy it to multiple chains and use it as a base for calling uniswap for swapping on the destination chain or any other contracts on the destination chain.

# Testing

1. Create a .env file with `ETHEREUM_SEPOLIA_RPC_URL` and `ARBITRUM_SEPOLIA_RPC_URL` RPC
2. forge test --mc CCIP_SWAPTest -vv


# Flow
![image](https://github.com/user-attachments/assets/ae32a7fa-9e71-4a3e-882a-193b5141d3fd)
