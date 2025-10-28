use core::num::traits::Zero;
use openzeppelin::access::ownable::OwnableComponent::Errors as OwnableErrors;
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::upgrades::interface::{
    IUpgradeableDispatcher, IUpgradeableDispatcherTrait, IUpgradeableSafeDispatcher,
    IUpgradeableSafeDispatcherTrait,
};
use openzeppelin::upgrades::upgradeable::UpgradeableComponent::Errors as UpgradeableErrors;
use snforge_std::{DeclareResultTrait, EventSpyTrait, EventsFilterTrait, TokenTrait, spy_events};
use starkware_utils::constants::MAX_U256;
use starkware_utils::erc20::erc20_errors::Erc20Error;
use starkware_utils::errors::Describable;
use starkware_utils_testing::event_test_utils::assert_number_of_events;
use starkware_utils_testing::test_utils::{
    assert_expected_event_emitted, assert_panic_with_error, assert_panic_with_felt_error,
    cheat_caller_address_once,
};
use token_migration::errors::Errors;
use token_migration::events::TokenMigrationEvents::{OwnerVerified, TokenMigrated};
use token_migration::interface::{
    ITokenMigrationAdminDispatcher, ITokenMigrationAdminDispatcherTrait,
    ITokenMigrationAdminSafeDispatcher, ITokenMigrationAdminSafeDispatcherTrait,
    ITokenMigrationDispatcher, ITokenMigrationDispatcherTrait, ITokenMigrationSafeDispatcher,
    ITokenMigrationSafeDispatcherTrait,
};
use token_migration::tests::test_utils::constants::{
    INITIAL_CONTRACT_SUPPLY, INITIAL_SUPPLY, LEGACY_THRESHOLD,
};
use token_migration::tests::test_utils::{
    deploy_token_migration, generic_load, generic_test_fixture, new_user, supply_contract,
};
use token_migration::token_migration::TokenMigration::{
    LARGE_BATCH_SIZE, SMALL_BATCH_SIZE, XL_BATCH_SIZE,
};

#[test]
fn test_constructor() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    // Assert contract storage is initialized correctly.
    assert_eq!(
        legacy_token_address,
        generic_load(token_migration_contract, selector!("legacy_token_dispatcher")),
    );
    assert_eq!(
        new_token_address,
        generic_load(token_migration_contract, selector!("new_token_dispatcher")),
    );
    let l1_recipient = generic_load(token_migration_contract, selector!("l1_recipient"));
    assert_eq!(cfg.l1_recipient, l1_recipient);
    assert_eq!(
        cfg.starkgate_address,
        generic_load(token_migration_contract, selector!("starkgate_address")),
    );
    assert_eq!(
        LEGACY_THRESHOLD, generic_load(token_migration_contract, selector!("legacy_threshold")),
    );
    assert_eq!(LARGE_BATCH_SIZE, generic_load(token_migration_contract, selector!("batch_size")));
    // Assert owner is set correctly.
    let ownable_dispatcher = IOwnableDispatcher { contract_address: token_migration_contract };
    assert_eq!(ownable_dispatcher.owner(), cfg.owner);
}

#[test]
fn test_set_legacy_threshold() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_admin_dispatcher = ITokenMigrationAdminDispatcher {
        contract_address: token_migration_contract,
    };
    // Set the threshold to a new value.
    let new_threshold = LEGACY_THRESHOLD * 2;
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    token_migration_admin_dispatcher.set_legacy_threshold(threshold: new_threshold);
    assert_eq!(
        new_threshold, generic_load(token_migration_contract, selector!("legacy_threshold")),
    );
    assert_eq!(LARGE_BATCH_SIZE, generic_load(token_migration_contract, selector!("batch_size")));
    // Set the threshold to a new value that is less than the current transfer unit.
    let new_threshold = LARGE_BATCH_SIZE - 1;
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    token_migration_admin_dispatcher.set_legacy_threshold(threshold: new_threshold);
    assert_eq!(
        new_threshold, generic_load(token_migration_contract, selector!("legacy_threshold")),
    );
    assert_eq!(SMALL_BATCH_SIZE, generic_load(token_migration_contract, selector!("batch_size")));
    // Set the threshold to a new value that is greater than the current transfer unit.
    let new_threshold = XL_BATCH_SIZE + 1;
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    token_migration_admin_dispatcher.set_legacy_threshold(threshold: new_threshold);
    assert_eq!(
        new_threshold, generic_load(token_migration_contract, selector!("legacy_threshold")),
    );
    assert_eq!(XL_BATCH_SIZE, generic_load(token_migration_contract, selector!("batch_size")));
}

#[test]
#[feature("safe_dispatcher")]
fn test_set_legacy_threshold_assertions() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_admin_safe_dispatcher = ITokenMigrationAdminSafeDispatcher {
        contract_address: token_migration_contract,
    };
    // Catch the owner error.
    let result = token_migration_admin_safe_dispatcher
        .set_legacy_threshold(threshold: LEGACY_THRESHOLD);
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);
    // Catch the invalid threshold error.
    let invalid_threshold = 1000;
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    let result = token_migration_admin_safe_dispatcher
        .set_legacy_threshold(threshold: invalid_threshold);
    assert_panic_with_felt_error(:result, expected_error: Errors::THRESHOLD_TOO_SMALL);
}

#[test]
fn test_upgrade() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let owner = cfg.owner;
    let upgradeable_dispatcher = IUpgradeableDispatcher {
        contract_address: token_migration_contract,
    };
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: owner);
    let new_class_hash = *snforge_std::declare("MockContract").unwrap().contract_class().class_hash;
    upgradeable_dispatcher.upgrade(new_class_hash);
    assert_eq!(snforge_std::get_class_hash(token_migration_contract), new_class_hash);
}

#[test]
#[feature("safe_dispatcher")]
fn test_upgrade_assertions() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let owner = cfg.owner;
    let upgradeable_safe_dispatcher = IUpgradeableSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let new_class_hash = 'new_class_hash'.try_into().unwrap();
    // Catch only owner.
    let result = upgradeable_safe_dispatcher.upgrade(new_class_hash);
    assert_panic_with_felt_error(result, OwnableErrors::NOT_OWNER);
    // Catch zero class hash.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: owner);
    let result = upgradeable_safe_dispatcher.upgrade(Zero::zero());
    assert_panic_with_felt_error(result, UpgradeableErrors::INVALID_CLASS);
}

#[test]
fn test_swap_to_new() {
    let cfg = generic_test_fixture();
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, legacy_supply: amount);
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_dispatcher = ITokenMigrationDispatcher {
        contract_address: token_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };

    // Spy events.
    let mut spy = spy_events();

    // Approve and migrate.
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    token_migration_dispatcher.swap_to_new(:amount);

    // Assert user balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), 0);
    assert_eq!(new_dispatcher.balance_of(account: user), amount);

    // Assert contract balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), amount);
    assert_eq!(
        new_dispatcher.balance_of(account: token_migration_contract),
        INITIAL_CONTRACT_SUPPLY - amount,
    );

    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: token_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "migrate");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: TokenMigrated {
            user, from_token: legacy_token_address, to_token: new_token_address, amount,
        },
        expected_event_selector: @selector!("TokenMigrated"),
        expected_event_name: "TokenMigrated",
    );
}

#[test]
fn test_swap_to_new_zero() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_dispatcher = ITokenMigrationDispatcher {
        contract_address: token_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, legacy_supply: amount);

    // Zero swap.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    token_migration_dispatcher.swap_to_new(amount: Zero::zero());

    // Assert balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), amount);
    assert_eq!(new_dispatcher.balance_of(account: user), Zero::zero());
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), Zero::zero());
    assert_eq!(new_dispatcher.balance_of(account: token_migration_contract), Zero::zero());
}

#[test]
#[feature("safe_dispatcher")]
fn test_swap_to_new_assertions() {
    let cfg = deploy_token_migration();
    let amount = INITIAL_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, legacy_supply: 0);
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };

    // Insufficient user balance.
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_BALANCE.describe());

    // Insufficient allowance.
    supply_contract(target: user, token: cfg.legacy_token, :amount);
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, amount: amount / 2);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_ALLOWANCE.describe());

    // Insufficient contract balance.
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_BALANCE.describe());
}

#[test]
#[feature("safe_dispatcher")]
fn test_send_legacy_balance_to_l1_assertions() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_admin_safe_dispatcher = ITokenMigrationAdminSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let result = token_migration_admin_safe_dispatcher.send_legacy_balance_to_l1();
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);
}

#[test]
#[feature("safe_dispatcher")]
fn test_verify_owner_l2_address() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_admin_safe_dispatcher = ITokenMigrationAdminSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let result = token_migration_admin_safe_dispatcher.verify_owner();
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);

    let mut spy = spy_events();
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    let result = token_migration_admin_safe_dispatcher.verify_owner();
    assert!(result.is_ok());
    // Assert infinite approval to owner for both legacy and new tokens.
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    assert_eq!(
        legacy_dispatcher.allowance(owner: token_migration_contract, spender: cfg.owner), MAX_U256,
    );
    assert_eq!(
        new_dispatcher.allowance(owner: token_migration_contract, spender: cfg.owner), MAX_U256,
    );
    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: token_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "verify_owner");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: OwnerVerified { owner: cfg.owner },
        expected_event_selector: @selector!("OwnerVerified"),
        expected_event_name: "OwnerVerified",
    );
}

// TODO: Consider refactoring swap tests to use common code.
#[test]
fn test_swap_to_legacy() {
    let cfg = deploy_token_migration();
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, legacy_supply: 0);
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_dispatcher = ITokenMigrationDispatcher {
        contract_address: token_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };

    // Supply user and contract.
    supply_contract(target: user, token: cfg.new_token, :amount);
    supply_contract(target: token_migration_contract, token: cfg.legacy_token, :amount);

    // Spy events.
    let mut spy = spy_events();

    // Approve and migrate.
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    token_migration_dispatcher.swap_to_legacy(:amount);

    // Assert user balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), amount);
    assert_eq!(new_dispatcher.balance_of(account: user), Zero::zero());

    // Assert contract balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), Zero::zero());
    assert_eq!(new_dispatcher.balance_of(account: token_migration_contract), amount);

    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: token_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "migrate");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: TokenMigrated {
            user, from_token: new_token_address, to_token: legacy_token_address, amount,
        },
        expected_event_selector: @selector!("TokenMigrated"),
        expected_event_name: "TokenMigrated",
    );
}

#[test]
fn test_swap_to_legacy_zero() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_dispatcher = ITokenMigrationDispatcher {
        contract_address: token_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, legacy_supply: amount);

    // Zero swap.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    token_migration_dispatcher.swap_to_new(amount: Zero::zero());

    // Assert balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), amount);
    assert_eq!(new_dispatcher.balance_of(account: user), Zero::zero());
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), Zero::zero());
    assert_eq!(new_dispatcher.balance_of(account: token_migration_contract), Zero::zero());
}

#[test]
#[feature("safe_dispatcher")]
fn test_swap_to_legacy_assertions() {
    let cfg = deploy_token_migration();
    let amount = INITIAL_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, legacy_supply: 0);
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let new_token_address = cfg.new_token.contract_address();
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };

    // Insufficient user balance.
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_BALANCE.describe());

    // Insufficient allowance.
    supply_contract(target: user, token: cfg.new_token, :amount);
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: token_migration_contract, amount: amount / 2);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_ALLOWANCE.describe());

    // Insufficient contract balance.
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_BALANCE.describe());
}
