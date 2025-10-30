use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::TokenTrait;
use starkware_utils::erc20::erc20_errors::Erc20Error;
use starkware_utils::errors::Describable;
use starkware_utils_testing::test_utils::{assert_panic_with_error, cheat_caller_address_once};
use token_migration::interface::{
    ITokenMigrationDispatcher, ITokenMigrationDispatcherTrait, ITokenMigrationSafeDispatcher,
    ITokenMigrationSafeDispatcherTrait,
};
use token_migration::tests::test_utils::constants::{INITIAL_CONTRACT_SUPPLY, LEGACY_THRESHOLD};
use token_migration::tests::test_utils::{
    approve_and_swap_to_new, deploy_token_migration, generic_test_fixture, new_user,
    supply_contract,
};

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
    assert_eq!(legacy_dispatcher.balance_of(user), amount / 2);
    assert_eq!(new_dispatcher.balance_of(user), amount / 2);
    assert_eq!(legacy_dispatcher.balance_of(migration_contract), amount / 2);
    assert_eq!(new_dispatcher.balance_of(migration_contract), INITIAL_CONTRACT_SUPPLY - amount / 2);
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_new(amount: amount / 2);
    assert_eq!(legacy_dispatcher.balance_of(user), Zero::zero());
    assert_eq!(new_dispatcher.balance_of(user), amount);
    assert_eq!(legacy_dispatcher.balance_of(migration_contract), amount);
    assert_eq!(new_dispatcher.balance_of(migration_contract), INITIAL_CONTRACT_SUPPLY - amount);
    // Swap to legacy twice.
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user,
    );
    new_dispatcher.approve(spender: migration_contract, :amount);
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_legacy(amount: amount / 2);
    assert_eq!(legacy_dispatcher.balance_of(user), amount / 2);
    assert_eq!(new_dispatcher.balance_of(user), amount / 2);
    assert_eq!(legacy_dispatcher.balance_of(migration_contract), amount / 2);
    assert_eq!(new_dispatcher.balance_of(migration_contract), INITIAL_CONTRACT_SUPPLY - amount / 2);
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_legacy(amount: amount / 2);
    assert_eq!(legacy_dispatcher.balance_of(user), amount);
    assert_eq!(new_dispatcher.balance_of(user), Zero::zero());
    assert_eq!(legacy_dispatcher.balance_of(migration_contract), Zero::zero());
    assert_eq!(new_dispatcher.balance_of(migration_contract), INITIAL_CONTRACT_SUPPLY);
}

// This test is failing because of a known snforge issue - state is not reverted after a failed
// transaction.
#[test]
#[feature("safe_dispatcher")]
#[ignore]
fn test_flow_user_swap_fail_then_succeed() {
    let cfg = deploy_token_migration();
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
    assert_panic_with_error(:result, expected_error: Erc20Error::INSUFFICIENT_BALANCE.describe());
    supply_contract(target: user, token: cfg.legacy_token, :amount);
    // No approval.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_error(:result, expected_error: Erc20Error::INSUFFICIENT_ALLOWANCE.describe());
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    legacy_dispatcher.approve(spender: migration_contract, :amount);
    // No balance to contract.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_error(:result, expected_error: Erc20Error::INSUFFICIENT_BALANCE.describe());
    supply_contract(target: migration_contract, token: cfg.new_token, :amount);
    // Succeed.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_new(:amount);
    assert_eq!(legacy_dispatcher.balance_of(user), Zero::zero());
    assert_eq!(new_dispatcher.balance_of(user), amount);
    assert_eq!(legacy_dispatcher.balance_of(migration_contract), amount);
    assert_eq!(new_dispatcher.balance_of(migration_contract), INITIAL_CONTRACT_SUPPLY - amount);
    // Reverse swap.
    // No balance to user.
    let amount = amount + 1;
    cheat_caller_address_once(
        contract_address: legacy_dispatcher.contract_address, caller_address: user,
    );
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(:result, expected_error: Erc20Error::INSUFFICIENT_BALANCE.describe());
    supply_contract(target: user, token: cfg.new_token, amount: 1);
    // No approval.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(:result, expected_error: Erc20Error::INSUFFICIENT_ALLOWANCE.describe());
    cheat_caller_address_once(
        contract_address: new_dispatcher.contract_address, caller_address: user,
    );
    new_dispatcher.approve(spender: migration_contract, :amount);
    // No balance to contract.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    let result = migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(:result, expected_error: Erc20Error::INSUFFICIENT_BALANCE.describe());
    supply_contract(target: migration_contract, token: cfg.legacy_token, amount: 1);
    // Succeed.
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    migration_dispatcher.swap_to_legacy(:amount);
    assert_eq!(legacy_dispatcher.balance_of(user), amount);
    assert_eq!(new_dispatcher.balance_of(user), Zero::zero());
    assert_eq!(legacy_dispatcher.balance_of(migration_contract), amount);
    assert_eq!(new_dispatcher.balance_of(migration_contract), INITIAL_CONTRACT_SUPPLY - amount);
}
