module MasterFrenDepolyer::MasterKekV1 {
    use std::signer;
    use std::string::utf8;
    use std::type_info::{Self, TypeInfo};
    use std::event;
    use std::vector;
    use aptos_framework::coin::{Self, MintCapability, FreezeCapability, BurnCapability};
    use aptos_framework::timestamp;
    use aptos_framework::account::{Self, SignerCapability};

    // use std::debug;    // For debug

    /// When user is not admin.
    const ERR_FORBIDDEN: u64 = 103;
    /// When Coin not registerd by admin.
    const ERR_LPCOIN_NOT_EXIST: u64 = 104;
    /// When Coin already registerd by adin.
    const ERR_LPCOIN_ALREADY_EXIST: u64 = 105;
    /// When not enough amount.
    const ERR_INSUFFICIENT_AMOUNT: u64 = 106;
    /// When need waiting for more blocks.
    const ERR_WAIT_FOR_NEW_BLOCK: u64 = 107;

    const ACC_KEK_PRECISION: u128 = 1000000000000;  // 1e12
    const DEPLOYER: address = @MasterFrenDepolyer;
    const RESOURCE_ACCOUNT_ADDRESS: address = @MasterFrenResourceAccount;   // gas saving

    // KEK coin
    struct KEK {}
    struct Caps has key {
        direct_mint: bool,
        mint: MintCapability<KEK>,
        freeze: FreezeCapability<KEK>,
        burn: BurnCapability<KEK>,
    }

      /**
     * KEK mint & burn
     */
    public entry fun mint_KEK(
        admin: &signer,
        amount: u64,
        to: address
    ) acquires MasterFrenData, Caps {
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        let caps = borrow_global<Caps>(RESOURCE_ACCOUNT_ADDRESS);
        let direct_mint = caps.direct_mint;
        assert!(direct_mint == true, ERR_FORBIDDEN);
        let coins = coin::mint<KEK>(amount, &caps.mint);
        coin::deposit(to, coins);
    }

    public entry fun burn_KEK(
        account: &signer,
        amount: u64
    ) acquires Caps {
        let coin_b = &borrow_global<Caps>(RESOURCE_ACCOUNT_ADDRESS).burn;
        let coins = coin::withdraw<KEK>(account, amount);
        coin::burn(coins, coin_b)
    }

 // events
    struct Events<phantom X> has key {
        add_event: event::EventHandle<CoinMeta<X>>,
        set_event: event::EventHandle<CoinMeta<X>>,
        deposit_event: event::EventHandle<DepositWithdrawEvent<X>>,
        withdraw_event: event::EventHandle<DepositWithdrawEvent<X>>,
        emergency_withdraw_event: event::EventHandle<DepositWithdrawEvent<X>>,
    }

    // add/set event data
    struct CoinMeta<phantom X> has drop, store, copy {
        alloc_point: u64,
    }

    // deposit/withdraw event data
    struct DepositWithdrawEvent<phantom X> has drop, store {
        amount: u64,
        amount_KEK: u64,
    }

    // info of each user, store at user's address
    struct UserInfo<phantom X> has key, store, copy {
        amount: u64,    // `amount` LP coin amount the user has provided.
        reward_debt: u128,    // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of KEKs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.acc_KEK_per_share) - user.reward_debt
        //
        // Whenever a user deposits or withdraws LP coins to a pool. Here's what happens:
        //   1. The pool's `acc_KEK_per_share` (and `last_reward_timestamp`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `reward_debt` gets updated.
    }

    // info of each pool, store at deployer's address
    struct PoolInfo<phantom X> has key, store {
        acc_KEK_per_share: u128,    // times ACC_KEK_PRECISION
        last_reward_timestamp: u64,
        alloc_point: u64,
    }

    struct MasterFrenData has drop, key {
        signer_cap: SignerCapability,
        total_alloc_point: u64,
        admin_address: address,
        dao_address: address,   // dao fee to address
        dao_percent: u64,   // dao fee percent
        bonus_multiplier: u64,  // Bonus muliplier for early KEK makers.
        last_timestamp_dao_withdraw: u64,  // Last timestamp then develeper withdraw dao fee
        start_timestamp: u64,   // mc mint KEK start from this ts
        per_second_KEK: u128, // default KEK per second, 1 KEK/second = 86400 KEK/day, remember times bonus_multiplier
    }

    // all added lp
    struct LPInfo has key {
        lp_list: vector<TypeInfo>,
    }

    // resource account signer
    fun get_resource_account(): signer acquires MasterFrenData {
        let signer_cap = &borrow_global<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }


    // initialize
    fun init_module(admin: &signer){
        // create resource account
        let (resource_account, capability) = account::create_resource_account(admin, x"CF");
        // init KEK Coin
        let (coin_b, coin_f, coin_m) =
            coin::initialize<KEK>(admin, utf8(b"Kek Token"), utf8(b"KEK"), 8, true);
        move_to(&resource_account, Caps { direct_mint: true, mint: coin_m, freeze: coin_f, burn: coin_b });
        register_coin<KEK>(&resource_account);
    
        
        
        // MasterFrenData
        move_to(&resource_account, MasterFrenData {
            signer_cap: capability,
            total_alloc_point: 0,
            admin_address: DEPLOYER,
            dao_address: DEPLOYER,
            dao_percent: 10,    // 10%
            bonus_multiplier: 10,   // 10x
            last_timestamp_dao_withdraw: timestamp::now_seconds(),
            start_timestamp: timestamp::now_seconds(),
            per_second_KEK: 10000000,   // 0.1 KEK
        });
        // init lp info
        move_to(&resource_account, LPInfo{
            lp_list: vector::empty()
        });
        // KEK staking
        //add<KEK>(admin, 1000);
    }

    // user should call this first, for approve KEK 
    public entry fun register_KEK(account: &signer) {
        register_coin<KEK>(account);
    }

    fun register_coin<X>(account: &signer) {
        let account_addr = signer::address_of(account);
        if (!coin::is_account_registered<X>(account_addr)) {
            coin::register<X>(account);
        };
    }
        fun get_multiplier(
        from: u64,
        to: u64,
        bonus_multiplier: u64
    ): u128 {
        ((to - from) as u128) * (bonus_multiplier as u128)
    }

    // anyone can call this
    public entry fun withdraw_dao_fee() acquires MasterFrenData, Caps {
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(mc_data.last_timestamp_dao_withdraw < timestamp::now_seconds(), ERR_WAIT_FOR_NEW_BLOCK);

        let multiplier = get_multiplier(mc_data.last_timestamp_dao_withdraw, timestamp::now_seconds(), mc_data.bonus_multiplier);
        let reward_KEK = multiplier * mc_data.per_second_KEK * (mc_data.dao_percent as u128) / 100u128;
        let coin_m = &borrow_global<Caps>(RESOURCE_ACCOUNT_ADDRESS).mint;
        let coins = coin::mint<KEK>((reward_KEK as u64), coin_m);
        coin::deposit(mc_data.dao_address, coins);
        mc_data.last_timestamp_dao_withdraw = timestamp::now_seconds();
    }

    // Add a new LP to the pool. Can only be called by the owner.
    // DO NOT add the same LP coin more than once. Rewards will be messed up if you do.
    public entry fun add<X>(
        admin: &signer,
        new_alloc_point: u64
    ) acquires MasterFrenData, LPInfo {
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        let resource_account_signer = account::create_signer_with_capability(&mc_data.signer_cap);
        assert!(!exists<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS), ERR_LPCOIN_ALREADY_EXIST);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);

        // change mc data
        mc_data.total_alloc_point = mc_data.total_alloc_point + new_alloc_point;
        let last_reward_timestamp = (if (timestamp::now_seconds() > mc_data.start_timestamp) timestamp::now_seconds() else mc_data.start_timestamp);
        move_to(&resource_account_signer, PoolInfo<X> {
            acc_KEK_per_share: 0,
            last_reward_timestamp,
            alloc_point: new_alloc_point,
        });
        // register coin
        register_coin<X>(&resource_account_signer);
        // add lp_info
        let lp_info = borrow_global_mut<LPInfo>(RESOURCE_ACCOUNT_ADDRESS);
        vector::push_back<TypeInfo>(&mut lp_info.lp_list, type_info::type_of<X>());
        // event
        let events = Events<X> {
            add_event: account::new_event_handle<CoinMeta<X>>(&resource_account_signer),
            set_event: account::new_event_handle<CoinMeta<X>>(&resource_account_signer),
            deposit_event: account::new_event_handle<DepositWithdrawEvent<X>>(&resource_account_signer),
            withdraw_event: account::new_event_handle<DepositWithdrawEvent<X>>(&resource_account_signer),
            emergency_withdraw_event: account::new_event_handle<DepositWithdrawEvent<X>>(&resource_account_signer),
        };
        event::emit_event(&mut events.add_event, CoinMeta<X> {
            alloc_point: new_alloc_point,
        });
        move_to(&resource_account_signer, events);
    }

    // Update the given pool's KEK allocation point
    public entry fun set<X>(
        admin: &signer,
        new_alloc_point: u64
    ) acquires MasterFrenData, PoolInfo, Events {
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(exists<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS), ERR_LPCOIN_NOT_EXIST);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        let pool_info = borrow_global_mut<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS);

        mc_data.total_alloc_point = mc_data.total_alloc_point - pool_info.alloc_point + new_alloc_point;
        pool_info.alloc_point = new_alloc_point;
        // event
        let events = borrow_global_mut<Events<X>>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.set_event, CoinMeta<X> {
            alloc_point: new_alloc_point,
        });
    }

    // Update reward variables of the given pool.
    public entry fun update_pool<X>() acquires MasterFrenData, PoolInfo, Caps {
        let mc_data = borrow_global<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(exists<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS), ERR_LPCOIN_NOT_EXIST);
        let pool = borrow_global_mut<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS);
        if (timestamp::now_seconds() <= pool.last_reward_timestamp) return;
        let lp_supply = coin::balance<X>(RESOURCE_ACCOUNT_ADDRESS);
        if (lp_supply <= 0) {
            pool.last_reward_timestamp = timestamp::now_seconds();
            return
        };
        let multipler = get_multiplier(pool.last_reward_timestamp, timestamp::now_seconds(), mc_data.bonus_multiplier);
        let reward_KEK = multipler * mc_data.per_second_KEK * (pool.alloc_point as u128) / (mc_data.total_alloc_point as u128) * ((100 - mc_data.dao_percent) as u128) / 100u128;
        let coin_m = &borrow_global<Caps>(RESOURCE_ACCOUNT_ADDRESS).mint;
        let coins = coin::mint<KEK>((reward_KEK as u64), coin_m);
        coin::deposit(RESOURCE_ACCOUNT_ADDRESS, coins);
        pool.acc_KEK_per_share = pool.acc_KEK_per_share + reward_KEK * ACC_KEK_PRECISION / (lp_supply as u128);
        pool.last_reward_timestamp = timestamp::now_seconds();
    }

    // Deposit LP coins to MC for KEK allocation.
    public entry fun deposit<X>(
        account: &signer,
        amount: u64
    ) acquires MasterFrenData, PoolInfo, UserInfo, Caps, Events {
        let mc_data = borrow_global<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        let resource_account_signer = account::create_signer_with_capability(&mc_data.signer_cap);
        assert!(exists<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS), ERR_LPCOIN_NOT_EXIST);

        update_pool<X>();
        let acc_addr = signer::address_of(account);
        let pool = borrow_global<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS);

        register_KEK(account);
        let pending: u64 = 0;
        // exist user, check acc
        if (exists<UserInfo<X>>(acc_addr)) {
            let user_info = borrow_global_mut<UserInfo<X>>(acc_addr);
            // transfer earned KEK
            if (user_info.amount > 0) {
                pending = (((user_info.amount as u128) * pool.acc_KEK_per_share / ACC_KEK_PRECISION - user_info.reward_debt) as u64);
                safe_transfer_KEK(&resource_account_signer, signer::address_of(account), pending);
            };
            user_info.amount = user_info.amount + amount;
            user_info.reward_debt = (user_info.amount as u128) * pool.acc_KEK_per_share / ACC_KEK_PRECISION;
        } else {
            let user_info = UserInfo<X> {
                amount: amount,
                reward_debt: (amount as u128) * pool.acc_KEK_per_share / ACC_KEK_PRECISION,
            };
            move_to(account, user_info);
        };
        coin::transfer<X>(account, RESOURCE_ACCOUNT_ADDRESS, amount);
        // event
        let events = borrow_global_mut<Events<X>>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.deposit_event, DepositWithdrawEvent<X> {
            amount,
            amount_KEK: pending,
        });
    }

    // Withdraw LP coins from MC.
    public entry fun withdraw<X>(
        account: &signer,
        amount: u64
    ) acquires MasterFrenData, PoolInfo, UserInfo, Caps, Events {
        let mc_data = borrow_global<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        let resource_account_signer = account::create_signer_with_capability(&mc_data.signer_cap);
        assert!(exists<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS), ERR_LPCOIN_NOT_EXIST);

        update_pool<X>();
        let acc_addr = signer::address_of(account);
        let pool = borrow_global<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(exists<UserInfo<X>>(acc_addr), ERR_INSUFFICIENT_AMOUNT);
        let user_info = borrow_global_mut<UserInfo<X>>(acc_addr);
        assert!(user_info.amount >= amount, ERR_INSUFFICIENT_AMOUNT);

        register_KEK(account);
        let pending = (((user_info.amount as u128) * pool.acc_KEK_per_share / ACC_KEK_PRECISION - user_info.reward_debt) as u64);
        safe_transfer_KEK(&resource_account_signer, signer::address_of(account), pending);

        user_info.amount = user_info.amount - amount;
        user_info.reward_debt = (user_info.amount as u128) * pool.acc_KEK_per_share / ACC_KEK_PRECISION;
        coin::transfer<X>(&resource_account_signer, acc_addr, amount);
        // event
        let events = borrow_global_mut<Events<X>>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.withdraw_event, DepositWithdrawEvent<X> {
            amount,
            amount_KEK: pending,
        });
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    public entry fun emergency_withdraw<X>(
        account: &signer
    ) acquires MasterFrenData, UserInfo, Events {
        let mc_data = borrow_global<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        let resource_account_signer = account::create_signer_with_capability(&mc_data.signer_cap);

        let acc_addr = signer::address_of(account);
        assert!(exists<UserInfo<X>>(acc_addr), ERR_INSUFFICIENT_AMOUNT);
        let user_info = borrow_global_mut<UserInfo<X>>(acc_addr);

        register_KEK(account);
        let amount = user_info.amount;
        coin::transfer<X>(&resource_account_signer, acc_addr, amount);
        user_info.amount = 0;
        user_info.reward_debt = 0;

        // event
        let events = borrow_global_mut<Events<X>>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.emergency_withdraw_event, DepositWithdrawEvent<X> {
            amount,
            amount_KEK: 0,
        });
    }

    // Stake KEK coins to MC
    public entry fun enter_staking(
        account: &signer,
        amount: u64
    ) acquires MasterFrenData, PoolInfo, UserInfo, Caps, Events {
        deposit<KEK>(account, amount);
    }

    // Withdraw KEK coins from STAKING.
    public entry fun leave_staking(
        account: &signer,
        amount: u64
    ) acquires MasterFrenData, PoolInfo, UserInfo, Caps, Events {
        withdraw<KEK>(account, amount);
    }

    fun safe_transfer_KEK(
        resource_account_signer: &signer,
        to: address,
        amount: u64
    ) {
        let balance = coin::balance<KEK>(signer::address_of(resource_account_signer));
        if (amount > balance) {
            coin::transfer<KEK>(resource_account_signer, to, balance);
        } else {
            coin::transfer<KEK>(resource_account_signer, to, amount);
        };
    }

    public entry fun set_admin_address(
        admin: &signer,
        new_admin_address: address
    ) acquires MasterFrenData {
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.admin_address = new_admin_address;
    }

    public entry fun set_dao_address(
        admin: &signer,
        new_dao_address: address
    ) acquires MasterFrenData {
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.dao_address = new_dao_address;
    }

    public entry fun set_dao_percent(
        admin: &signer,
        new_dao_percent: u64
    ) acquires MasterFrenData {
        assert!(new_dao_percent <= 100, ERR_FORBIDDEN);
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.dao_percent = new_dao_percent;
    }

    public entry fun set_per_second_KEK(
        admin: &signer,
        per_second_KEK: u128
    ) acquires MasterFrenData {
        assert!(per_second_KEK >= 1000000 && per_second_KEK <= 10000000000, ERR_FORBIDDEN);   // 0.01 - 100 KEK/s
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.per_second_KEK = per_second_KEK;
    }

    public entry fun set_bonus_multiplier(
        admin: &signer,
        bonus_multiplier: u64
    ) acquires MasterFrenData {
        assert!(bonus_multiplier >= 1 && bonus_multiplier <= 10, ERR_FORBIDDEN);
        let mc_data = borrow_global_mut<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.bonus_multiplier = bonus_multiplier;
    }

    // after call this, direct mint will be disabled forever
    public entry fun set_disable_direct_mint(
        admin: &signer
    ) acquires MasterFrenData, Caps {
        let mc_data = borrow_global<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        let caps = borrow_global_mut<Caps>(RESOURCE_ACCOUNT_ADDRESS);
        caps.direct_mint = false;
    }

    /**
     *  public functions for other contract
     */

    // vie function to see deposit amount
    public fun get_user_info_amount<X>(
        acc_addr: address
    ): u64 acquires UserInfo {
        if (exists<UserInfo<X>>(acc_addr)) {
            let user_info = borrow_global<UserInfo<X>>(acc_addr);
            return user_info.amount
        } else {
            return 0
        }
    }

    // View function to see pending KEKs
    public fun pending_KEK<X>(
        acc_addr: address
    ): u64 acquires MasterFrenData, PoolInfo, UserInfo, Caps {
        assert!(exists<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS), ERR_LPCOIN_NOT_EXIST);

        update_pool<X>();
        let pool = borrow_global<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(exists<UserInfo<X>>(acc_addr), ERR_INSUFFICIENT_AMOUNT);
        let user_info = borrow_global<UserInfo<X>>(acc_addr);

        let pending = (user_info.amount as u128) * pool.acc_KEK_per_share / ACC_KEK_PRECISION - user_info.reward_debt;
        (pending as u64)
    }

    public fun get_mc_data(): (u64, u64, u64, u64, u128) acquires MasterFrenData {
        let mc_data = borrow_global<MasterFrenData>(RESOURCE_ACCOUNT_ADDRESS);
        (mc_data.total_alloc_point, mc_data.dao_percent, mc_data.bonus_multiplier, mc_data.start_timestamp, mc_data.per_second_KEK)
    }

    public fun get_pool_info<X>(): (u128, u64, u64) acquires PoolInfo {
        let pool_info = borrow_global<PoolInfo<X>>(RESOURCE_ACCOUNT_ADDRESS);
        (pool_info.acc_KEK_per_share, pool_info.last_reward_timestamp, pool_info.alloc_point)
    }

    public fun get_user_info<X>(acc_addr: address): (u64, u128) acquires UserInfo {
        let user_info = borrow_global<UserInfo<X>>(acc_addr);
        (user_info.amount, user_info.reward_debt)
    }

    public fun get_lp_list(): vector<TypeInfo> acquires LPInfo {
        let lp_info = borrow_global<LPInfo>(RESOURCE_ACCOUNT_ADDRESS);
        lp_info.lp_list
    }
}