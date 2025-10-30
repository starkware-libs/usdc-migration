use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::TokenTrait;
use starkware_utils::erc20::erc20_errors::Erc20Error;
use starkware_utils::errors::Describable;
use starkware_utils_testing::test_utils::{assert_panic_with_error, cheat_caller_address_once};
use token_migration::interface::{ITokenMigrationSafeDispatcher, ITokenMigrationSafeDispatcherTrait};
use token_migration::tests::test_utils::constants::{INITIAL_CONTRACT_SUPPLY, LEGACY_THRESHOLD};
use token_migration::tests::test_utils::{
    approve_and_swap_to_new, generic_test_fixture, new_user, supply_contract,
};
use token_migration::token_migration::TokenMigration::LARGE_BATCH_SIZE;

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

// 3. end to end: swaps, send to L1, swap and fail, get money, swap and aucceed
#[test]
#[feature("safe_dispatcher")]
#[ignore]
fn end_to_end_swap_send_to_l1_test() {
    let cfg = generic_test_fixture();
    let amount = INITIAL_CONTRACT_SUPPLY;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount * 2);
    let legacy = IERC20Dispatcher { contract_address: cfg.legacy_token.contract_address() };
    let new = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    let token_migration_safe = ITokenMigrationSafeDispatcher {
        contract_address: cfg.token_migration_contract,
    };

    // Swap triggers send to L1.
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_eq!(legacy.balance_of(account: cfg.token_migration_contract), amount % LARGE_BATCH_SIZE);
    assert_eq!(new.balance_of(account: cfg.token_migration_contract), Zero::zero());
    assert_eq!(legacy.balance_of(account: user), amount);
    assert_eq!(new.balance_of(account: user), amount);

    // Swap fails.
    cheat_caller_address_once(contract_address: legacy.contract_address, caller_address: user);
    legacy.approve(spender: cfg.token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let result = token_migration_safe.swap_to_new(:amount);
    assert_panic_with_error(:result, expected_error: Erc20Error::INSUFFICIENT_BALANCE.describe());

    // Fund supply contract with new tokens.
    supply_contract(target: cfg.token_migration_contract, token: cfg.new_token, :amount);

    // Swap succeeds and triggers send to L1.
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_eq!(
        legacy.balance_of(account: cfg.token_migration_contract), (amount * 2) % LARGE_BATCH_SIZE,
    );
    assert_eq!(new.balance_of(account: cfg.token_migration_contract), Zero::zero());
    assert_eq!(legacy.balance_of(account: user), Zero::zero());
    assert_eq!(new.balance_of(account: user), amount * 2);
}
