use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::TokenTrait;
use token_migration::tests::test_utils::constants::LEGACY_THRESHOLD;
use token_migration::tests::test_utils::{approve_and_swap_to_new, generic_test_fixture, new_user};

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
fn test_swap_send_to_l1_multiple_batches() {
    let cfg = generic_test_fixture();
    let to_send = LEGACY_THRESHOLD * 10;
    let left_over = LEGACY_THRESHOLD / 2;
    let amount = to_send + left_over;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };

    // Swap for 10 batches.
    approve_and_swap_to_new(:cfg, :user, :amount);

    // Assert contract balance (send has been triggered).
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), left_over);
}
