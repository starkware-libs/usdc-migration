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
use usdc_migration::errors::Errors;
use usdc_migration::events::USDCMigrationEvents::USDCMigrated;
use usdc_migration::interface::{
    IUSDCMigrationAdminDispatcher, IUSDCMigrationAdminDispatcherTrait,
    IUSDCMigrationAdminSafeDispatcher, IUSDCMigrationAdminSafeDispatcherTrait,
    IUSDCMigrationDispatcher, IUSDCMigrationDispatcherTrait, IUSDCMigrationSafeDispatcher,
    IUSDCMigrationSafeDispatcherTrait,
};
use usdc_migration::starkgate_interface::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
use usdc_migration::tests::test_utils::constants::{
    INITIAL_CONTRACT_SUPPLY, INITIAL_SUPPLY, L1_RECIPIENT, L1_TOKEN_ADDRESS, LEGACY_THRESHOLD,
};
use usdc_migration::tests::test_utils::{
    deploy_token_bridge_mock, deploy_tokens, deploy_usdc_migration, generic_test_fixture,
    load_contract_address, load_u256, new_user, supply_contract,
};
use usdc_migration::tests::token_bridge_mock::{
    ITokenBridgeMockDispatcher, ITokenBridgeMockDispatcherTrait,
};
use usdc_migration::usdc_migration::USDCMigration::{LARGE_BATCH_SIZE, SMALL_BATCH_SIZE};
#[test]
fn test_constructor() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    // Assert contract storage is initialized correctly.
    assert_eq!(
        legacy_token_address,
        load_contract_address(usdc_migration_contract, selector!("legacy_token_dispatcher")),
    );
    assert_eq!(
        new_token_address,
        load_contract_address(usdc_migration_contract, selector!("new_token_dispatcher")),
    );
    let l1_recipient = (*snforge_std::load(
        target: usdc_migration_contract, storage_address: selector!("l1_recipient"), size: 1,
    )[0])
        .try_into()
        .unwrap();
    assert_eq!(cfg.l1_recipient, l1_recipient);
    assert_eq!(
        cfg.starkgate_address,
        load_contract_address(usdc_migration_contract, selector!("starkgate_address")),
    );
    assert_eq!(LEGACY_THRESHOLD, load_u256(usdc_migration_contract, selector!("legacy_threshold")));
    assert_eq!(LARGE_BATCH_SIZE, load_u256(usdc_migration_contract, selector!("batch_size")));
    // Assert owner is set correctly.
    let ownable_dispatcher = IOwnableDispatcher { contract_address: usdc_migration_contract };
    assert_eq!(ownable_dispatcher.owner(), cfg.owner);
}

#[test]
fn test_set_legacy_threshold() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_admin_dispatcher = IUSDCMigrationAdminDispatcher {
        contract_address: usdc_migration_contract,
    };
    // Set the threshold to a new value.
    let new_threshold = LEGACY_THRESHOLD * 2;
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: cfg.owner);
    usdc_migration_admin_dispatcher.set_legacy_threshold(threshold: new_threshold);
    assert_eq!(new_threshold, load_u256(usdc_migration_contract, selector!("legacy_threshold")));
    assert_eq!(LARGE_BATCH_SIZE, load_u256(usdc_migration_contract, selector!("batch_size")));
    // Set the threshold to a new value that is less than the current transfer unit.
    let new_threshold = LARGE_BATCH_SIZE - 1;
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: cfg.owner);
    usdc_migration_admin_dispatcher.set_legacy_threshold(threshold: new_threshold);
    assert_eq!(new_threshold, load_u256(usdc_migration_contract, selector!("legacy_threshold")));
    assert_eq!(SMALL_BATCH_SIZE, load_u256(usdc_migration_contract, selector!("batch_size")));
    // Set the threshold to a new value that is greater than the current transfer unit.
    let new_threshold = LEGACY_THRESHOLD;
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: cfg.owner);
    usdc_migration_admin_dispatcher.set_legacy_threshold(threshold: new_threshold);
    assert_eq!(new_threshold, load_u256(usdc_migration_contract, selector!("legacy_threshold")));
    assert_eq!(LARGE_BATCH_SIZE, load_u256(usdc_migration_contract, selector!("batch_size")));
}

#[test]
#[feature("safe_dispatcher")]
fn test_set_legacy_threshold_assertions() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_admin_safe_dispatcher = IUSDCMigrationAdminSafeDispatcher {
        contract_address: usdc_migration_contract,
    };
    // Catch the owner error.
    let result = usdc_migration_admin_safe_dispatcher
        .set_legacy_threshold(threshold: LEGACY_THRESHOLD);
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);
    // Catch the invalid threshold error.
    let invalid_threshold = 1000;
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: cfg.owner);
    let result = usdc_migration_admin_safe_dispatcher
        .set_legacy_threshold(threshold: invalid_threshold);
    assert_panic_with_felt_error(:result, expected_error: Errors::THRESHOLD_TOO_SMALL);
}

#[test]
fn test_upgrade() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let owner = cfg.owner;
    let upgradeable_dispatcher = IUpgradeableDispatcher {
        contract_address: usdc_migration_contract,
    };
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: owner);
    let new_class_hash = *snforge_std::declare("MockContract").unwrap().contract_class().class_hash;
    upgradeable_dispatcher.upgrade(new_class_hash);
    assert_eq!(snforge_std::get_class_hash(usdc_migration_contract), new_class_hash);
}

#[test]
#[feature("safe_dispatcher")]
fn test_upgrade_assertions() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let owner = cfg.owner;
    let upgradeable_safe_dispatcher = IUpgradeableSafeDispatcher {
        contract_address: usdc_migration_contract,
    };
    let new_class_hash = 'new_class_hash'.try_into().unwrap();
    // Catch only owner.
    let result = upgradeable_safe_dispatcher.upgrade(new_class_hash);
    assert_panic_with_felt_error(result, OwnableErrors::NOT_OWNER);
    // Catch zero class hash.
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: owner);
    let result = upgradeable_safe_dispatcher.upgrade(Zero::zero());
    assert_panic_with_felt_error(result, UpgradeableErrors::INVALID_CLASS);
}

#[test]
fn test_swap_to_new() {
    let cfg = generic_test_fixture();
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    let user = new_user(legacy_token: cfg.legacy_token, id: 0, legacy_supply: amount);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_dispatcher = IUSDCMigrationDispatcher {
        contract_address: usdc_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };

    // Spy events.
    let mut spy = spy_events();

    // Approve and migrate.
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: usdc_migration_contract, :amount);
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    usdc_migration_dispatcher.swap_to_new(:amount);

    // Assert user balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), 0);
    assert_eq!(new_dispatcher.balance_of(account: user), amount);

    // Assert contract balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: usdc_migration_contract), amount);
    assert_eq!(
        new_dispatcher.balance_of(account: usdc_migration_contract),
        INITIAL_CONTRACT_SUPPLY - amount,
    );

    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: usdc_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "migrate");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: USDCMigrated {
            user, from_token: legacy_token_address, to_token: new_token_address, amount,
        },
        expected_event_selector: @selector!("USDCMigrated"),
        expected_event_name: "USDCMigrated",
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_swap_to_new_assertions() {
    let cfg = deploy_usdc_migration();
    let amount = INITIAL_SUPPLY / 10;
    let user = new_user(legacy_token: cfg.legacy_token, id: 0, legacy_supply: 0);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_safe_dispatcher = IUSDCMigrationSafeDispatcher {
        contract_address: usdc_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };

    // Insufficient user balance.
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: usdc_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.usdc_migration_contract, caller_address: user);
    let res = usdc_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_BALANCE.describe());

    // Insufficient allowance.
    supply_contract(target: user, token: cfg.legacy_token, :amount);
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: usdc_migration_contract, amount: amount / 2);
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    let res = usdc_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_ALLOWANCE.describe());

    // Insufficient contract balance.
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: usdc_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.usdc_migration_contract, caller_address: user);
    let res = usdc_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_BALANCE.describe());
}

#[test]
#[feature("safe_dispatcher")]
fn test_send_legacy_balance_to_l1_assertions() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_admin_safe_dispatcher = IUSDCMigrationAdminSafeDispatcher {
        contract_address: usdc_migration_contract,
    };
    let result = usdc_migration_admin_safe_dispatcher.send_legacy_balance_to_l1();
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);
}

#[test]
#[feature("safe_dispatcher")]
fn test_verify_owner_l2_address() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_admin_safe_dispatcher = IUSDCMigrationAdminSafeDispatcher {
        contract_address: usdc_migration_contract,
    };
    let result = usdc_migration_admin_safe_dispatcher.verify_owner();
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);

    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: cfg.owner);
    let result = usdc_migration_admin_safe_dispatcher.verify_owner();
    assert!(result.is_ok());
    // Assert infinite approval to owner for both legacy and new tokens.
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    assert_eq!(
        legacy_dispatcher.allowance(owner: usdc_migration_contract, spender: cfg.owner), MAX_U256,
    );
    assert_eq!(
        new_dispatcher.allowance(owner: usdc_migration_contract, spender: cfg.owner), MAX_U256,
    );
}

// TODO: Consider refactoring swap tests to use common code.
#[test]
fn test_swap_to_legacy() {
    let cfg = deploy_usdc_migration();
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    let user = new_user(legacy_token: cfg.legacy_token, id: 0, legacy_supply: 0);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_dispatcher = IUSDCMigrationDispatcher {
        contract_address: usdc_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };

    // Supply user and contract.
    supply_contract(target: user, token: cfg.new_token, :amount);
    supply_contract(target: usdc_migration_contract, token: cfg.legacy_token, :amount);

    // Spy events.
    let mut spy = spy_events();

    // Approve and migrate.
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: usdc_migration_contract, :amount);
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    usdc_migration_dispatcher.swap_to_legacy(:amount);

    // Assert user balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), amount);
    assert_eq!(new_dispatcher.balance_of(account: user), Zero::zero());

    // Assert contract balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: usdc_migration_contract), Zero::zero());
    assert_eq!(new_dispatcher.balance_of(account: usdc_migration_contract), amount);

    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: usdc_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "migrate");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: USDCMigrated {
            user, from_token: new_token_address, to_token: legacy_token_address, amount,
        },
        expected_event_selector: @selector!("USDCMigrated"),
        expected_event_name: "USDCMigrated",
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_swap_to_legacy_assertions() {
    let cfg = deploy_usdc_migration();
    let amount = INITIAL_SUPPLY / 10;
    let user = new_user(legacy_token: cfg.legacy_token, id: 0, legacy_supply: 0);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_safe_dispatcher = IUSDCMigrationSafeDispatcher {
        contract_address: usdc_migration_contract,
    };
    let new_token_address = cfg.new_token.contract_address();
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };

    // Insufficient user balance.
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: usdc_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.usdc_migration_contract, caller_address: user);
    let res = usdc_migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_BALANCE.describe());

    // Insufficient allowance.
    supply_contract(target: user, token: cfg.new_token, :amount);
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: usdc_migration_contract, amount: amount / 2);
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    let res = usdc_migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_ALLOWANCE.describe());

    // Insufficient contract balance.
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: usdc_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.usdc_migration_contract, caller_address: user);
    let res = usdc_migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_error(res, Erc20Error::INSUFFICIENT_BALANCE.describe());
}

#[test]
fn test_token_bridge_mock() {
    let starkgate_address = deploy_token_bridge_mock();
    let (legacy_token, _) = deploy_tokens(owner: starkgate_address);
    let l2_token_address = legacy_token.contract_address();
    ITokenBridgeMockDispatcher { contract_address: starkgate_address }
        .set_l2_token_address(:l2_token_address);
    let amount = 10_000_000_000_000;
    let user = new_user(:legacy_token, id: 0, legacy_supply: amount);
    let starkgate_dispatcher = ITokenBridgeDispatcher { contract_address: starkgate_address };

    cheat_caller_address_once(contract_address: starkgate_address, caller_address: user);
    starkgate_dispatcher
        .initiate_token_withdraw(
            l1_token: L1_TOKEN_ADDRESS(), l1_recipient: L1_RECIPIENT(), :amount,
        );

    assert_eq!(
        IERC20Dispatcher { contract_address: legacy_token.contract_address() }
            .balance_of(account: user),
        Zero::zero(),
    );
    assert_eq!(starkgate_dispatcher.get_l1_token(l2_token: l2_token_address), L1_TOKEN_ADDRESS());
}
