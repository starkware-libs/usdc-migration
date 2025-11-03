use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{
    IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher, IERC20SafeDispatcherTrait,
};
use openzeppelin::upgrades::interface::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use snforge_std::{DeclareResultTrait, EventSpyTrait, EventsFilterTrait, TokenTrait, spy_events};
use starkware_utils_testing::event_test_utils::assert_number_of_events;
use starkware_utils_testing::test_utils::{
    assert_expected_event_emitted, assert_panic_with_felt_error, cheat_caller_address_once,
};
use token_migration::errors::Errors;
use token_migration::interface::{
    ITokenMigrationAdminDispatcher, ITokenMigrationAdminDispatcherTrait, ITokenMigrationDispatcher,
    ITokenMigrationDispatcherTrait, ITokenMigrationSafeDispatcher,
    ITokenMigrationSafeDispatcherTrait,
};
use token_migration::tests::test_utils::constants::{
    INITIAL_CONTRACT_SUPPLY, L1_TOKEN_ADDRESS, LEGACY_THRESHOLD,
};
use token_migration::tests::test_utils::{
    allow_swap_to_legacy, approve_and_swap_to_legacy, approve_and_swap_to_new, assert_balances,
    deploy_token_migration, generic_test_fixture, new_user, set_legacy_threshold, supply_contract,
    verify_l1_recipient, verify_owner,
};
use token_migration::tests::token_bridge_mock::WithdrawInitiated;
use token_migration::token_migration::TokenMigration::{LARGE_BATCH_SIZE, SMALL_BATCH_SIZE};

#[test]
fn test_swap_send_to_l1_multiple_sends() {
    let cfg = generic_test_fixture();
    let amount_1 = LEGACY_THRESHOLD / 2;
    let amount_2 = LEGACY_THRESHOLD * 3 / 2;
    let amount_3 = LEGACY_THRESHOLD * 4 / 3;
    let amount_4 = LEGACY_THRESHOLD * 10 / 3;
    let user_1 = new_user(id: 1, token: cfg.legacy_token, initial_balance: amount_1);
    let user_2 = new_user(id: 2, token: cfg.legacy_token, initial_balance: amount_2);
    let user_3 = new_user(id: 3, token: cfg.legacy_token, initial_balance: amount_3);
    let user_4 = new_user(id: 4, token: cfg.legacy_token, initial_balance: amount_4);
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };

    // Swap for user 1.
    approve_and_swap_to_new(:cfg, user: user_1, amount: amount_1);
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), amount_1);

    // Swap for user 2.
    approve_and_swap_to_new(:cfg, user: user_2, amount: amount_2);
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), Zero::zero());

    // Swap for user 3.
    approve_and_swap_to_new(:cfg, user: user_3, amount: amount_3);
    assert_eq!(
        legacy_dispatcher.balance_of(account: token_migration_contract), LEGACY_THRESHOLD / 3,
    );

    // Swap for user 4.
    approve_and_swap_to_new(:cfg, user: user_4, amount: amount_4);
    assert_eq!(
        legacy_dispatcher.balance_of(account: token_migration_contract), LEGACY_THRESHOLD * 2 / 3,
    );
}

#[test]
fn test_flow_user_swap_twice() {
    let cfg = generic_test_fixture();
    let amount = LEGACY_THRESHOLD - 2;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let migration_contract = cfg.token_migration_contract;
    let migration_dispatcher = ITokenMigrationDispatcher { contract_address: migration_contract };
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    // Swap to new twice.
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    legacy_dispatcher.approve(spender: migration_contract, :amount);
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_new(amount: amount / 2);
    assert_balances(:cfg, account: user, legacy_balance: amount / 2, new_balance: amount / 2);
    assert_balances(
        :cfg,
        account: migration_contract,
        legacy_balance: amount / 2,
        new_balance: INITIAL_CONTRACT_SUPPLY - amount / 2,
    );
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_new(amount: amount / 2);
    assert_balances(:cfg, account: user, legacy_balance: Zero::zero(), new_balance: amount);
    assert_balances(
        :cfg,
        account: migration_contract,
        legacy_balance: amount,
        new_balance: INITIAL_CONTRACT_SUPPLY - amount,
    );
    // Swap to legacy twice.
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user,
    );
    new_dispatcher.approve(spender: migration_contract, :amount);
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_legacy(amount: amount / 2);
    assert_balances(:cfg, account: user, legacy_balance: amount / 2, new_balance: amount / 2);
    assert_balances(
        :cfg,
        account: migration_contract,
        legacy_balance: amount / 2,
        new_balance: INITIAL_CONTRACT_SUPPLY - amount / 2,
    );
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_legacy(amount: amount / 2);
    assert_balances(:cfg, account: user, legacy_balance: amount, new_balance: Zero::zero());
    assert_balances(
        :cfg,
        account: migration_contract,
        legacy_balance: Zero::zero(),
        new_balance: INITIAL_CONTRACT_SUPPLY,
    );
}

// This test is failing because of a known snforge issue - state is not reverted after a failed
// transaction.
#[test]
#[feature("safe_dispatcher")]
fn test_flow_user_swap_fail_then_succeed() {
    let cfg = deploy_token_migration();
    verify_l1_recipient(:cfg);
    let amount = INITIAL_CONTRACT_SUPPLY / 100;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: 0);
    let migration_contract = cfg.token_migration_contract;
    let migration_dispatcher = ITokenMigrationDispatcher { contract_address: migration_contract };
    let migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: migration_contract,
    };
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    // No balance to user.
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    let result = migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CALLER_BALANCE);
    supply_contract(target: user, token: cfg.legacy_token, :amount);
    // No approval.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_ALLOWANCE);
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    legacy_dispatcher.approve(spender: migration_contract, :amount);
    // No balance to contract.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CONTRACT_BALANCE);
    supply_contract(target: migration_contract, token: cfg.new_token, :amount);
    // Succeed.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_new(:amount);
    assert_balances(:cfg, account: user, legacy_balance: Zero::zero(), new_balance: amount);
    assert_balances(
        :cfg, account: migration_contract, legacy_balance: amount, new_balance: Zero::zero(),
    );
    // Reverse swap.
    // No balance to user.
    let amount = amount + 1;
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CALLER_BALANCE);
    supply_contract(target: user, token: cfg.new_token, amount: 1);
    // No approval.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_ALLOWANCE);
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user,
    );
    new_dispatcher.approve(spender: migration_contract, :amount);
    // No balance to contract.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CONTRACT_BALANCE);
    supply_contract(target: migration_contract, token: cfg.legacy_token, amount: 1);
    // Succeed.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_legacy(:amount);
    assert_balances(:cfg, account: user, legacy_balance: amount, new_balance: Zero::zero());
    assert_balances(
        :cfg, account: migration_contract, legacy_balance: Zero::zero(), new_balance: amount,
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_token_allowances() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    let amount = INITIAL_CONTRACT_SUPPLY;
    supply_contract(target: cfg.token_migration_contract, token: cfg.legacy_token, :amount);
    let new_token = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    let legacy_token = IERC20Dispatcher { contract_address: cfg.legacy_token.contract_address() };
    let legacy_token_safe = IERC20SafeDispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let owner = cfg.owner;

    // Attempt to withdraw before verifying owner.
    cheat_caller_address_once(
        contract_address: legacy_token.contract_address, caller_address: owner,
    );
    let result = legacy_token_safe
        .transfer_from(sender: token_migration_contract, recipient: owner, :amount);
    assert_panic_with_felt_error(:result, expected_error: 'ERC20: insufficient allowance');

    // Verify owner.
    verify_owner(:cfg);

    // Withdraw partial legacy and new tokens.
    cheat_caller_address_once(
        contract_address: legacy_token.contract_address, caller_address: owner,
    );
    legacy_token
        .transfer_from(sender: token_migration_contract, recipient: owner, amount: amount / 2);
    cheat_caller_address_once(contract_address: new_token.contract_address, caller_address: owner);
    new_token.transfer_from(sender: token_migration_contract, recipient: owner, amount: amount / 2);

    // Check balances.
    assert_balances(:cfg, account: owner, legacy_balance: amount / 2, new_balance: amount / 2);
    assert_balances(
        :cfg,
        account: token_migration_contract,
        legacy_balance: amount / 2,
        new_balance: amount / 2,
    );

    // Withdraw the rest.
    cheat_caller_address_once(
        contract_address: legacy_token.contract_address, caller_address: owner,
    );
    legacy_token
        .transfer_from(sender: token_migration_contract, recipient: owner, amount: amount / 2);
    cheat_caller_address_once(contract_address: new_token.contract_address, caller_address: owner);
    new_token.transfer_from(sender: token_migration_contract, recipient: owner, amount: amount / 2);

    // Check balances.
    assert_balances(:cfg, account: owner, legacy_balance: amount, new_balance: amount);
    assert_balances(
        :cfg,
        account: token_migration_contract,
        legacy_balance: Zero::zero(),
        new_balance: Zero::zero(),
    );
}

#[test]
fn test_transfer_to_contract() {
    let cfg = generic_test_fixture();
    let amount = 100;
    let contract = cfg.token_migration_contract;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };

    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    legacy_dispatcher.transfer(recipient: contract, :amount);

    assert_eq!(legacy_dispatcher.balance_of(account: contract), amount);
    assert_eq!(legacy_dispatcher.balance_of(account: user), Zero::zero());

    // Use this money for reverse swap.
    supply_contract(target: user, token: cfg.new_token, :amount);
    approve_and_swap_to_legacy(:cfg, :user, :amount);

    assert_balances(
        :cfg,
        account: contract,
        legacy_balance: Zero::zero(),
        new_balance: INITIAL_CONTRACT_SUPPLY + amount,
    );
    assert_balances(:cfg, account: user, legacy_balance: amount, new_balance: Zero::zero());
}

#[test]
fn test_swap_to_new_and_back_to_legacy() {
    let cfg = generic_test_fixture();
    let amount = LARGE_BATCH_SIZE + LARGE_BATCH_SIZE / 2;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let token_migration_contract = cfg.token_migration_contract;
    let migration_admin_dispatcher = ITokenMigrationAdminDispatcher {
        contract_address: token_migration_contract,
    };
    let owner = cfg.owner;

    // Set threshold to be bigger than batch size.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: owner);
    migration_admin_dispatcher.set_legacy_threshold(threshold: amount);

    // Swap to new.
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_balances(:cfg, account: user, legacy_balance: Zero::zero(), new_balance: amount);
    assert_balances(
        :cfg,
        account: token_migration_contract,
        legacy_balance: amount - LARGE_BATCH_SIZE,
        new_balance: INITIAL_CONTRACT_SUPPLY - amount,
    );

    // Swap back to legacy.
    approve_and_swap_to_legacy(:cfg, :user, amount: amount - LARGE_BATCH_SIZE);
    assert_balances(
        :cfg, account: user, legacy_balance: LARGE_BATCH_SIZE / 2, new_balance: LARGE_BATCH_SIZE,
    );
    assert_balances(
        :cfg,
        account: token_migration_contract,
        legacy_balance: Zero::zero(),
        new_balance: INITIAL_CONTRACT_SUPPLY - LARGE_BATCH_SIZE,
    );
}

#[test]
#[feature("safe_dispatcher")]
fn end_to_end_swap_send_to_l1_test() {
    let cfg = generic_test_fixture();
    let amount = INITIAL_CONTRACT_SUPPLY;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount * 2);
    let legacy = IERC20Dispatcher { contract_address: cfg.legacy_token.contract_address() };
    let token_migration_safe = ITokenMigrationSafeDispatcher {
        contract_address: cfg.token_migration_contract,
    };

    // Swap triggers send to L1.
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_balances(
        :cfg,
        account: cfg.token_migration_contract,
        legacy_balance: amount % LARGE_BATCH_SIZE,
        new_balance: Zero::zero(),
    );
    assert_balances(:cfg, account: user, legacy_balance: amount, new_balance: amount);

    // Swap fails.
    cheat_caller_address_once(contract_address: legacy.contract_address, caller_address: user);
    legacy.approve(spender: cfg.token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let result = token_migration_safe.swap_to_new(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CONTRACT_BALANCE);

    // Supply contract with new tokens.
    supply_contract(target: cfg.token_migration_contract, token: cfg.new_token, :amount);

    // Swap succeeds and triggers send to L1.
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_balances(
        :cfg,
        account: cfg.token_migration_contract,
        legacy_balance: (amount * 2) % LARGE_BATCH_SIZE,
        new_balance: Zero::zero(),
    );
    assert_balances(:cfg, account: user, legacy_balance: Zero::zero(), new_balance: amount * 2);
}

#[test]
#[feature("safe_dispatcher")]
fn swap_fail_after_send_money_from_contract() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    let migration_admin_dispatcher = ITokenMigrationAdminDispatcher {
        contract_address: token_migration_contract,
    };
    let migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let owner = cfg.owner;

    let amount = INITIAL_CONTRACT_SUPPLY - 5;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    approve_and_swap_to_new(:cfg, :user, :amount);
    let contract_legacy_balance = amount % LARGE_BATCH_SIZE;
    assert_balances(
        :cfg,
        account: token_migration_contract,
        legacy_balance: contract_legacy_balance,
        new_balance: 5,
    );

    // Transfer all legacy from contract.
    verify_owner(:cfg);
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: owner,
    );
    legacy_dispatcher
        .transfer_from(
            sender: token_migration_contract, recipient: owner, amount: contract_legacy_balance,
        );
    assert_balances(
        :cfg, account: token_migration_contract, legacy_balance: Zero::zero(), new_balance: 5,
    );

    // Reverse swap should fail.
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user,
    );
    new_dispatcher.approve(spender: token_migration_contract, amount: 1);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_legacy(amount: 1);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CONTRACT_BALANCE);

    // Transfer legacy back to contract.
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: owner,
    );
    legacy_dispatcher
        .transfer(recipient: token_migration_contract, amount: contract_legacy_balance);
    assert_balances(
        :cfg,
        account: token_migration_contract,
        legacy_balance: contract_legacy_balance,
        new_balance: 5,
    );

    // Send all legacy to L1.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: owner);
    migration_admin_dispatcher.send_legacy_balance_to_l1();
    assert_balances(
        :cfg, account: token_migration_contract, legacy_balance: Zero::zero(), new_balance: 5,
    );

    // Reverse swap should fail.
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user,
    );
    new_dispatcher.approve(spender: token_migration_contract, amount: 1);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_legacy(amount: 1);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CONTRACT_BALANCE);

    // Check balances.
    assert_balances(:cfg, account: user, legacy_balance: Zero::zero(), new_balance: amount);
    assert_balances(
        :cfg, account: token_migration_contract, legacy_balance: Zero::zero(), new_balance: 5,
    );

    // Transfer all new from contract.
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: owner,
    );
    new_dispatcher.transfer_from(sender: token_migration_contract, recipient: owner, amount: 5);
    assert_balances(
        :cfg,
        account: token_migration_contract,
        legacy_balance: Zero::zero(),
        new_balance: Zero::zero(),
    );

    // Swap should fail.
    supply_contract(target: user, token: cfg.legacy_token, amount: 1);
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    legacy_dispatcher.approve(spender: token_migration_contract, amount: 1);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_new(amount: 1);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CONTRACT_BALANCE);
}

#[test]
#[feature("safe_dispatcher")]
fn test_upgrade_flow() {
    let cfg = generic_test_fixture();

    // Swap works.
    let amount = 100;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount * 2);
    approve_and_swap_to_new(:cfg, :user, :amount);

    // Remember balances of the contract.
    let token_migration_contract = cfg.token_migration_contract;
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    let new_balance = new_dispatcher.balance_of(account: token_migration_contract);
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let legacy_balance = legacy_dispatcher.balance_of(account: token_migration_contract);

    // Upgrade.
    let owner = cfg.owner;
    let upgradeable_dispatcher = IUpgradeableDispatcher {
        contract_address: token_migration_contract,
    };
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: owner);
    let new_class_hash = *snforge_std::declare("MockContract").unwrap().contract_class().class_hash;
    upgradeable_dispatcher.upgrade(new_class_hash);

    // Assert balances are the same.
    assert_eq!(new_dispatcher.balance_of(account: token_migration_contract), new_balance);
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), legacy_balance);

    // Swap doesn't work.
    let migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: token_migration_contract,
    };
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_new(:amount);
    assert!(result.is_err());

    // Reverse swap doesn't work.
    let amount = legacy_balance;
    assert!(new_dispatcher.balance_of(account: user) >= amount);
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user,
    );
    new_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert!(result.is_err());
}

#[test]
#[feature("safe_dispatcher")]
fn test_disallow_swap_to_legacy() {
    let cfg = generic_test_fixture();
    allow_swap_to_legacy(:cfg, allow_swap: false);

    // Try to swap to legacy.
    let amount = 100;
    let user = new_user(id: 0, token: cfg.new_token, initial_balance: amount);
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user,
    );
    new_dispatcher.approve(spender: cfg.token_migration_contract, :amount);
    let migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: cfg.token_migration_contract,
    };
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::REVERSE_SWAP_DISABLED);

    // Swap to new.
    supply_contract(target: user, token: cfg.legacy_token, :amount);
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_balances(:cfg, account: user, legacy_balance: Zero::zero(), new_balance: amount * 2);
    assert_balances(
        :cfg,
        account: cfg.token_migration_contract,
        legacy_balance: amount,
        new_balance: INITIAL_CONTRACT_SUPPLY - amount,
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_swap_fail_gets_money_from_reverse() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    let migration_dispatcher = ITokenMigrationDispatcher {
        contract_address: token_migration_contract,
    };
    let migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };

    // Swap almost all contract balance, leave small remainder of legacy tokens in contract.
    let amount = INITIAL_CONTRACT_SUPPLY - 1;
    let user_1 = new_user(id: 1, token: cfg.legacy_token, initial_balance: amount);
    approve_and_swap_to_new(:cfg, user: user_1, :amount);

    // Swap to new and fail.
    let amount = amount % LARGE_BATCH_SIZE;
    assert!(amount.is_non_zero());
    let user_2 = new_user(id: 2, token: cfg.legacy_token, initial_balance: amount);
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user_2,
    );
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user_2);
    let result = migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CONTRACT_BALANCE);

    // Contract gets money from reverse swap.
    let user_3 = new_user(id: 3, token: cfg.new_token, initial_balance: amount);
    approve_and_swap_to_legacy(:cfg, user: user_3, :amount);

    // Try again and succeed.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user_2);
    migration_dispatcher.swap_to_new(:amount);

    // Check balances.
    assert_balances(:cfg, account: user_2, legacy_balance: Zero::zero(), new_balance: amount);
    assert_balances(
        :cfg, account: token_migration_contract, legacy_balance: amount, new_balance: 1,
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_reverse_swap_fail_gets_money_from_swap() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    let migration_dispatcher = ITokenMigrationDispatcher {
        contract_address: token_migration_contract,
    };
    let migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };

    // Swap to legacy and fail.
    let amount = LARGE_BATCH_SIZE - 1;
    let user_1 = new_user(id: 1, token: cfg.new_token, initial_balance: amount);
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user_1,
    );
    new_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user_1);
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::INSUFFICIENT_CONTRACT_BALANCE);

    // Contract gets money from swap.
    let user_2 = new_user(id: 2, token: cfg.legacy_token, initial_balance: amount);
    approve_and_swap_to_new(:cfg, user: user_2, :amount);

    // Try again and succeed.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user_1);
    migration_dispatcher.swap_to_legacy(:amount);

    // Check balances.
    assert_balances(:cfg, account: user_1, legacy_balance: amount, new_balance: Zero::zero());
    assert_balances(
        :cfg,
        account: token_migration_contract,
        legacy_balance: Zero::zero(),
        new_balance: INITIAL_CONTRACT_SUPPLY,
    );
}

#[test]
fn test_batch_sizes() {
    let cfg = generic_test_fixture();
    let amount = LARGE_BATCH_SIZE * 15 + SMALL_BATCH_SIZE * 2 + 1;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let mut spy = spy_events();
    approve_and_swap_to_new(:cfg, :user, :amount);

    // Test balances.
    let new_contract_balance = INITIAL_CONTRACT_SUPPLY - amount;
    assert_balances(
        :cfg,
        account: cfg.token_migration_contract,
        legacy_balance: SMALL_BATCH_SIZE * 2 + 1,
        new_balance: new_contract_balance,
    );

    // Assert batches by starkgate events.
    let events = spy.get_events().emitted_by(contract_address: cfg.starkgate_address).events;
    assert_number_of_events(actual: events.len(), expected: 15, message: "withdraw_initiated");
    for event in events.span() {
        assert_expected_event_emitted(
            spied_event: event,
            expected_event: WithdrawInitiated {
                l1_token: L1_TOKEN_ADDRESS(),
                l1_recipient: cfg.l1_recipient,
                caller_address: cfg.token_migration_contract,
                amount: LARGE_BATCH_SIZE,
            },
            expected_event_selector: @selector!("WithdrawInitiated"),
            expected_event_name: "WithdrawInitiated",
        );
    }

    let mut spy = spy_events();
    // Set batch size to small.
    set_legacy_threshold(:cfg, threshold: SMALL_BATCH_SIZE);

    // Test balances.
    assert_balances(
        :cfg,
        account: cfg.token_migration_contract,
        legacy_balance: 1,
        new_balance: new_contract_balance,
    );

    // Assert batches by starkgate events.
    let events = spy.get_events().emitted_by(contract_address: cfg.starkgate_address).events;
    assert_number_of_events(actual: events.len(), expected: 2, message: "withdraw_initiated");
    for event in events.span() {
        assert_expected_event_emitted(
            spied_event: event,
            expected_event: WithdrawInitiated {
                l1_token: L1_TOKEN_ADDRESS(),
                l1_recipient: cfg.l1_recipient,
                caller_address: cfg.token_migration_contract,
                amount: SMALL_BATCH_SIZE,
            },
            expected_event_selector: @selector!("WithdrawInitiated"),
            expected_event_name: "WithdrawInitiated",
        );
    }

    let amount = SMALL_BATCH_SIZE + 1;
    let user = new_user(id: 1, token: cfg.legacy_token, initial_balance: amount);
    let mut spy = spy_events();
    approve_and_swap_to_new(:cfg, :user, :amount);

    // Test balances.
    assert_balances(
        :cfg,
        account: cfg.token_migration_contract,
        legacy_balance: 2,
        new_balance: new_contract_balance - amount,
    );

    // Assert batches by starkgate events.
    let events = spy.get_events().emitted_by(contract_address: cfg.starkgate_address).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "withdraw_initiated");
    for event in events.span() {
        assert_expected_event_emitted(
            spied_event: event,
            expected_event: WithdrawInitiated {
                l1_token: L1_TOKEN_ADDRESS(),
                l1_recipient: cfg.l1_recipient,
                caller_address: cfg.token_migration_contract,
                amount: SMALL_BATCH_SIZE,
            },
            expected_event_selector: @selector!("WithdrawInitiated"),
            expected_event_name: "WithdrawInitiated",
        );
    }
}
