
# MasterKek-v2

## Overview

MasterKek-v2 is a smart contract module on the Aptos blockchain that facilitates the minting, burning, and staking of the KEK token. This module allows users to participate in liquidity pools (LPs) and earn rewards in KEK tokens. It also implements an event-driven system for tracking deposits, withdrawals, and administrative actions.

## Features

-   **KEK Token Minting & Burning:**
    
    -   Mint KEK tokens to a specific address if the sender has admin privileges.
        
    -   Burn KEK tokens from a user's balance.
        
-   **Liquidity Pool Management:**
    
    -   Users can deposit LP tokens and earn KEK rewards.
        
    -   Each liquidity pool has a unique allocation point determining its share of KEK emissions.
        
-   **Admin Functions:**
    
    -   Deployers can add or update LP pools.
        
    -   DAO fee distribution and governance mechanisms.
        
-   **Event Logging:**
    
    -   Tracks all major interactions such as deposits, withdrawals, and pool updates.
        

## Smart Contract Components

### 1. KEK Token Structure

-   `struct KEK {}`: Defines the KEK token.
    
-   `struct Caps`: Holds capabilities for minting, burning, and freezing KEK tokens.
    

### 2. Liquidity Pool Structures

-   `struct UserInfo<X>`: Tracks each user's deposited LP tokens and pending KEK rewards.
    
-   `struct PoolInfo<X>`: Stores reward distribution information for each liquidity pool.
    
-   `struct LPInfo`: Contains a list of registered LP tokens.
    

### 3. MasterFrenData

-   `struct MasterFrenData`:
    
    -   Tracks the admin address, DAO fee settings, KEK distribution rate, and other key protocol parameters.
        
    -   Stores the capability to sign transactions for the resource account.
        

### 4. Events

-   `struct Events<X>`: Manages deposit, withdrawal, and administrative events.
    
-   `struct DepositWithdrawEvent<X>`: Logs deposit and withdrawal amounts.
    

## Key Functions

### Minting & Burning KEK

-   `mint_KEK(admin, amount, to)`: Mints KEK tokens if called by an admin.
    
-   `burn_KEK(account, amount)`: Burns KEK tokens from a user's balance.
    

### Staking & Rewards

-   `deposit<X>(account, amount)`: Deposits LP tokens to start earning KEK rewards.
    
-   `withdraw_dao_fee()`: Allows the DAO to withdraw accumulated fees.
    
-   `update_pool<X>()`: Updates reward variables for a given liquidity pool.
    

### Admin Functions

-   `add<X>(admin, new_alloc_point)`: Adds a new liquidity pool.
    
-   `set<X>(admin, new_alloc_point)`: Updates the allocation point of an existing pool.
    

## Deployment & Initialization

1.  Deploy the module with the `init_module(admin)` function.
    
2.  Initialize KEK token and create the resource account.
    
3.  Admin registers LP tokens using `add<X>(admin, alloc_point)`.
    
4.  Users register KEK using `register_KEK(account)` before depositing LP tokens.
    

## Error Codes

-   `ERR_FORBIDDEN (103)`: Action not allowed.
    
-   `ERR_LPCOIN_NOT_EXIST (104)`: Liquidity pool not found.
    
-   `ERR_LPCOIN_ALREADY_EXIST (105)`: Liquidity pool already exists.
    
-   `ERR_INSUFFICIENT_AMOUNT (106)`: Insufficient balance.
    
-   `ERR_WAIT_FOR_NEW_BLOCK (107)`: Must wait for the next block.
    

## License

MasterKek-v2 is open-source and available under the MIT License.
