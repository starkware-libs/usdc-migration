use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::TokenTrait;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use token_migration::interface::{
    ITokenMigrationAdminDispatcher, ITokenMigrationAdminDispatcherTrait,
};
use token_migration::tests::test_utils::constants::{INITIAL_CONTRACT_SUPPLY, LEGACY_THRESHOLD};
use token_migration::tests::test_utils::{
    approve_and_swap_to_new, generic_test_fixture, new_user, supply_contract,
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
fn test_token_allowances() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    let amount = INITIAL_CONTRACT_SUPPLY;
    supply_contract(target: cfg.token_migration_contract, token: cfg.legacy_token, :amount);
    let new_token = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    let legacy_token = IERC20Dispatcher { contract_address: cfg.legacy_token.contract_address() };
    let owner = cfg.owner;

    // Verify owner.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: owner);
    ITokenMigrationAdminDispatcher { contract_address: token_migration_contract }.verify_owner();

    // Withdraw all legacy and new tokens.
    cheat_caller_address_once(
        contract_address: legacy_token.contract_address, caller_address: owner,
    );
    legacy_token.transfer_from(sender: token_migration_contract, recipient: owner, :amount);
    cheat_caller_address_once(contract_address: new_token.contract_address, caller_address: owner);
    new_token.transfer_from(sender: token_migration_contract, recipient: owner, :amount);

    // Check balances.
    assert_eq!(legacy_token.balance_of(account: owner), amount);
    assert_eq!(new_token.balance_of(account: owner), amount);
    assert_eq!(legacy_token.balance_of(account: token_migration_contract), Zero::zero());
    assert_eq!(new_token.balance_of(account: token_migration_contract), Zero::zero());
}
