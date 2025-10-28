use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{
    IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher, IERC20SafeDispatcherTrait,
};
use snforge_std::{
    DeclareResultTrait, EventSpyTrait, EventsFilterTrait, L1HandlerTrait, TokenTrait, spy_events,
};
use starkware_utils::erc20::erc20_errors::Erc20Error;
use starkware_utils::errors::Describable;
use starkware_utils_testing::test_utils::{
    assert_expected_event_emitted, assert_panic_with_error, assert_panic_with_felt_error,
    cheat_caller_address_once,
};
use token_migration::interface::{
    ITokenMigrationDispatcher, ITokenMigrationDispatcherTrait, ITokenMigrationSafeDispatcher,
    ITokenMigrationSafeDispatcherTrait,
};
use token_migration::tests::test_utils::constants::INITIAL_CONTRACT_SUPPLY;
use token_migration::tests::test_utils::{
    deploy_token_migration, generic_test_fixture, new_user, supply_contract,
};

#[test]
fn test_flow_user_swap_twice() {
    let cfg = generic_test_fixture();
    let amount = INITIAL_CONTRACT_SUPPLY / 100;
    let user = new_user(:cfg, id: 0, legacy_supply: amount);
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
    let user = new_user(:cfg, id: 0, legacy_supply: 0);
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
