use core::num::traits::Zero;
use openzeppelin::access::ownable::OwnableComponent::Errors as OwnableErrors;
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::upgrades::interface::{
    IUpgradeableDispatcher, IUpgradeableDispatcherTrait, IUpgradeableSafeDispatcher,
    IUpgradeableSafeDispatcherTrait,
};
use openzeppelin::upgrades::upgradeable::UpgradeableComponent::Errors as UpgradeableErrors;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyTrait, EventsFilterTrait, L1HandlerTrait,
    TokenTrait, spy_events,
};
use starknet::EthAddress;
use starkware_utils::constants::MAX_U256;
use starkware_utils_testing::event_test_utils::assert_number_of_events;
use starkware_utils_testing::test_utils::{
    assert_expected_event_emitted, assert_panic_with_felt_error, cheat_caller_address_once,
};
use token_migration::errors::Errors;
use token_migration::events::TokenMigrationEvents::{
    L1RecipientVerified, ThresholdSet, TokenMigrated,
};
use token_migration::interface::{
    ITokenMigrationAdminDispatcher, ITokenMigrationAdminDispatcherTrait,
    ITokenMigrationAdminSafeDispatcher, ITokenMigrationAdminSafeDispatcherTrait,
    ITokenMigrationDispatcher, ITokenMigrationDispatcherTrait, ITokenMigrationSafeDispatcher,
    ITokenMigrationSafeDispatcherTrait,
};
use token_migration::starkgate_interface::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
use token_migration::tests::test_utils::constants::{
    INITIAL_CONTRACT_SUPPLY, INITIAL_SUPPLY, L1_RECIPIENT, L1_TOKEN_ADDRESS, LEGACY_THRESHOLD,
    OWNER_ADDRESS,
};
use token_migration::tests::test_utils::{
    allow_swap_to_legacy, approve_and_swap_to_legacy, approve_and_swap_to_new, deploy_mock_bridge,
    deploy_token_migration, deploy_tokens, generic_load, generic_test_fixture, new_user,
    set_legacy_threshold, supply_contract, verify_l1_recipient,
};
use token_migration::tests::token_bridge_mock::{
    ITokenBridgeMockDispatcher, ITokenBridgeMockDispatcherTrait,
};
use token_migration::token_migration::TokenMigration::{
    LARGE_BATCH_SIZE, MAX_BATCH_COUNT, SMALL_BATCH_SIZE, XL_BATCH_SIZE,
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
        generic_load(token_migration_contract, selector!("starkgate_dispatcher")),
    );
    assert_eq!(
        LEGACY_THRESHOLD, generic_load(token_migration_contract, selector!("legacy_threshold")),
    );
    assert_eq!(LARGE_BATCH_SIZE, generic_load(token_migration_contract, selector!("batch_size")));
    assert!(generic_load(token_migration_contract, selector!("allow_swap_to_legacy")));
    // Assert owner is set correctly.
    let ownable_dispatcher = IOwnableDispatcher { contract_address: token_migration_contract };
    assert_eq!(ownable_dispatcher.owner(), cfg.owner);
}

#[test]
fn test_constructor_assertions() {
    let starkgate_address = deploy_mock_bridge();
    let starkgate_dispatcher = ITokenBridgeMockDispatcher { contract_address: starkgate_address };
    let (legacy_token, new_token) = deploy_tokens(owner: starkgate_address);

    // LEGACY_TOKEN_BRIDGE_MISMATCH.
    starkgate_dispatcher
        .set_bridged_token(
            l2_token_address: legacy_token.contract_address(), l1_token_address: Zero::zero(),
        );
    let mut calldata = ArrayTrait::new();
    legacy_token.contract_address().serialize(ref calldata);
    new_token.contract_address().serialize(ref calldata);
    L1_RECIPIENT().serialize(ref calldata);
    OWNER_ADDRESS().serialize(ref calldata);
    starkgate_address.serialize(ref calldata);
    LEGACY_THRESHOLD.serialize(ref calldata);
    let token_migration_contract = snforge_std::declare("TokenMigration").unwrap().contract_class();
    let result = token_migration_contract.deploy(@calldata);
    assert!(result.is_err());
    assert!(*result.unwrap_err()[0] == 'LEGACY_TOKEN_BRIDGE_MISMATCH');

    // THRESHOLD_TOO_SMALL.
    starkgate_dispatcher
        .set_bridged_token(
            l2_token_address: legacy_token.contract_address(), l1_token_address: L1_TOKEN_ADDRESS(),
        );
    let legacy_threshold = LARGE_BATCH_SIZE - 1;
    let mut calldata = ArrayTrait::new();
    legacy_token.contract_address().serialize(ref calldata);
    new_token.contract_address().serialize(ref calldata);
    L1_RECIPIENT().serialize(ref calldata);
    OWNER_ADDRESS().serialize(ref calldata);
    starkgate_address.serialize(ref calldata);
    legacy_threshold.serialize(ref calldata);
    let token_migration_contract = snforge_std::declare("TokenMigration").unwrap().contract_class();
    let result = token_migration_contract.deploy(@calldata);
    assert!(result.is_err());
    assert!(*result.unwrap_err()[0] == 'THRESHOLD_TOO_SMALL');
}

#[test]
fn test_set_legacy_threshold() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    // Set the threshold to a new value.
    let mut spy = spy_events();
    let new_threshold = LEGACY_THRESHOLD * 2;
    set_legacy_threshold(:cfg, threshold: new_threshold);
    assert_eq!(
        new_threshold, generic_load(token_migration_contract, selector!("legacy_threshold")),
    );
    assert_eq!(LARGE_BATCH_SIZE, generic_load(token_migration_contract, selector!("batch_size")));
    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: token_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "set_legacy_threshold");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: ThresholdSet {
            old_threshold: LEGACY_THRESHOLD,
            new_threshold: new_threshold,
            old_batch_size: LARGE_BATCH_SIZE,
            new_batch_size: LARGE_BATCH_SIZE,
        },
        expected_event_selector: @selector!("ThresholdSet"),
        expected_event_name: "ThresholdSet",
    );
    // Set the threshold to a new value that is less than the current transfer unit.
    let new_threshold = LARGE_BATCH_SIZE - 1;
    set_legacy_threshold(:cfg, threshold: new_threshold);
    assert_eq!(
        new_threshold, generic_load(token_migration_contract, selector!("legacy_threshold")),
    );
    assert_eq!(SMALL_BATCH_SIZE, generic_load(token_migration_contract, selector!("batch_size")));
    // Set the threshold to a new value that is greater than the current transfer unit.
    let new_threshold = XL_BATCH_SIZE + 1;
    set_legacy_threshold(:cfg, threshold: new_threshold);
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

    // Catch l1 recipient not verified.
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    let result = token_migration_admin_safe_dispatcher
        .set_legacy_threshold(threshold: LEGACY_THRESHOLD);
    assert_panic_with_felt_error(:result, expected_error: Errors::L1_RECIPIENT_NOT_VERIFIED);
}

#[test]
fn test_set_legacy_threshold_trigger_send_to_l1() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    let amount = LEGACY_THRESHOLD - 1;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };

    // Swap without triggering send to l1.
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), amount);

    // Set threshold to balance.
    set_legacy_threshold(:cfg, threshold: amount);

    // Assert balance was sent to l1.
    let new_batch_size = SMALL_BATCH_SIZE;
    assert_eq!(
        legacy_dispatcher.balance_of(account: token_migration_contract), amount % new_batch_size,
    );
}

#[test]
fn test_set_legacy_threshold_without_triggering_send_to_l1() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    let amount = LARGE_BATCH_SIZE - 2;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };

    // Swap without triggering send to l1.
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), amount);

    // Set threshold, not changing the batch size, without triggering send to l1.
    set_legacy_threshold(:cfg, threshold: LARGE_BATCH_SIZE);
    assert_eq!(generic_load(token_migration_contract, selector!("batch_size")), LARGE_BATCH_SIZE);

    // Assert balance was not sent to l1.
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), amount);

    // Set threshold, changing the batch size, without triggering send to l1.
    set_legacy_threshold(:cfg, threshold: LARGE_BATCH_SIZE - 1);
    assert_eq!(generic_load(token_migration_contract, selector!("batch_size")), SMALL_BATCH_SIZE);

    // Assert balance was not sent to l1.
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), amount);
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
    let amount = LEGACY_THRESHOLD - 1;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };

    // Spy events.
    let mut spy = spy_events();

    // Approve and swap.
    approve_and_swap_to_new(:cfg, :user, :amount);

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
    assert_number_of_events(actual: events.len(), expected: 1, message: "swap_to_new");
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
    verify_l1_recipient(:cfg);
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);

    // Zero swap.
    approve_and_swap_to_new(:cfg, :user, amount: Zero::zero());

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
    let amount = LEGACY_THRESHOLD - 1;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: 0);
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_safe_dispatcher = ITokenMigrationSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };

    // Insufficient user balance.
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_felt_error(res, Errors::INSUFFICIENT_CALLER_BALANCE);

    // Insufficient allowance.
    supply_contract(target: user, token: cfg.legacy_token, :amount);
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, amount: amount / 2);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_felt_error(res, Errors::INSUFFICIENT_ALLOWANCE);

    // Insufficient contract balance.
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_felt_error(res, Errors::INSUFFICIENT_CONTRACT_BALANCE);

    // L1 recipient not verified.
    supply_contract(target: token_migration_contract, token: cfg.new_token, :amount);
    supply_contract(target: user, token: cfg.legacy_token, :amount);
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let result = token_migration_safe_dispatcher.swap_to_new(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::L1_RECIPIENT_NOT_VERIFIED);
}

#[test]
fn test_send_legacy_balance_to_l1() {
    let cfg = generic_test_fixture();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_admin_dispatcher = ITokenMigrationAdminDispatcher {
        contract_address: token_migration_contract,
    };
    let amount = LEGACY_THRESHOLD - 1;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };

    // Send zero legacy balance to l1.
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    token_migration_admin_dispatcher.send_legacy_balance_to_l1();

    // Assert balances.
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), Zero::zero());
    assert_eq!(
        new_dispatcher.balance_of(account: token_migration_contract), INITIAL_CONTRACT_SUPPLY,
    );

    // Swap without triggering send to l1.
    approve_and_swap_to_new(:cfg, :user, :amount);
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), amount);

    // Send balance to l1.
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    token_migration_admin_dispatcher.send_legacy_balance_to_l1();

    // Assert balances.
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), Zero::zero());
    assert_eq!(
        new_dispatcher.balance_of(account: token_migration_contract),
        INITIAL_CONTRACT_SUPPLY - amount,
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_send_legacy_balance_to_l1_assertions() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_admin_safe_dispatcher = ITokenMigrationAdminSafeDispatcher {
        contract_address: token_migration_contract,
    };

    // Catch only owner.
    let result = token_migration_admin_safe_dispatcher.send_legacy_balance_to_l1();
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);

    // Catch l1 recipient not verified.
    supply_contract(target: token_migration_contract, token: cfg.legacy_token, amount: 1);
    cheat_caller_address_once(
        contract_address: token_migration_contract, caller_address: cfg.owner,
    );
    let result = token_migration_admin_safe_dispatcher.send_legacy_balance_to_l1();
    assert_panic_with_felt_error(:result, expected_error: Errors::L1_RECIPIENT_NOT_VERIFIED);
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
}

#[test]
fn test_swap_to_legacy() {
    let cfg = deploy_token_migration();
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: 0);
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };

    // Supply user and contract.
    supply_contract(target: user, token: cfg.new_token, :amount);
    supply_contract(target: token_migration_contract, token: cfg.legacy_token, :amount);

    // Spy events.
    let mut spy = spy_events();

    // Approve and swap.
    approve_and_swap_to_legacy(:cfg, :user, :amount);

    // Assert user balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), amount);
    assert_eq!(new_dispatcher.balance_of(account: user), Zero::zero());

    // Assert contract balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), Zero::zero());
    assert_eq!(new_dispatcher.balance_of(account: token_migration_contract), amount);

    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: token_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "swap_to_legacy");
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
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);

    // Zero swap.
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    token_migration_dispatcher.swap_to_legacy(amount: Zero::zero());

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
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: 0);
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
    assert_panic_with_felt_error(res, Errors::INSUFFICIENT_CALLER_BALANCE);

    // Insufficient allowance.
    supply_contract(target: user, token: cfg.new_token, :amount);
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: token_migration_contract, amount: amount / 2);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_felt_error(res, Errors::INSUFFICIENT_ALLOWANCE);

    // Insufficient contract balance.
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let res = token_migration_safe_dispatcher.swap_to_legacy(:amount);
    assert_panic_with_felt_error(res, Errors::INSUFFICIENT_CONTRACT_BALANCE);
}

#[test]
fn test_verify_l1_recipient() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let l1_recipient_verified = generic_load(
        token_migration_contract, selector!("l1_recipient_verified"),
    );
    assert!(!l1_recipient_verified);
    // Verify the L1 recipient with the wrong address.
    let wrong_address: EthAddress = 'WRONG_ADDRESS'.try_into().unwrap();
    let l1_handler = L1HandlerTrait::new(
        cfg.token_migration_contract, selector!("verify_l1_recipient"),
    );
    let result = l1_handler
        .execute(from_address: wrong_address.into(), payload: ArrayTrait::new().span());
    assert!(result.is_ok());
    let l1_recipient_verified = generic_load(
        token_migration_contract, selector!("l1_recipient_verified"),
    );
    assert!(!l1_recipient_verified);
    // Verify the L1 recipient with the correct address.
    let mut spy = spy_events();
    let l1_handler = L1HandlerTrait::new(
        cfg.token_migration_contract, selector!("verify_l1_recipient"),
    );
    let result = l1_handler
        .execute(from_address: cfg.l1_recipient.into(), payload: ArrayTrait::new().span());
    assert!(result.is_ok());
    let l1_recipient_verified = generic_load(
        token_migration_contract, selector!("l1_recipient_verified"),
    );
    assert!(l1_recipient_verified);
    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: token_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "verify_l1_recipient");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: L1RecipientVerified { l1_recipient: cfg.l1_recipient },
        expected_event_selector: @selector!("L1RecipientVerified"),
        expected_event_name: "L1RecipientVerified",
    );
}

#[test]
fn test_token_bridge_mock() {
    let starkgate_address = deploy_mock_bridge();
    let (legacy_token, _) = deploy_tokens(owner: starkgate_address);
    let l2_token_address = legacy_token.contract_address();
    ITokenBridgeMockDispatcher { contract_address: starkgate_address }
        .set_bridged_token(:l2_token_address, l1_token_address: L1_TOKEN_ADDRESS());
    let amount = 10_000_000_000_000;
    let user = new_user(id: 0, token: legacy_token, initial_balance: amount);
    let l2_bridge = ITokenBridgeDispatcher { contract_address: starkgate_address };

    cheat_caller_address_once(contract_address: starkgate_address, caller_address: user);
    l2_bridge
        .initiate_token_withdraw(
            l1_token: L1_TOKEN_ADDRESS(), l1_recipient: L1_RECIPIENT(), amount: amount / 2,
        );

    assert_eq!(
        IERC20Dispatcher { contract_address: legacy_token.contract_address() }
            .balance_of(account: user),
        amount / 2,
    );
    assert_eq!(l2_bridge.get_l1_token(l2_token: l2_token_address), L1_TOKEN_ADDRESS());
}

#[test]
fn test_swap_send_to_l1() {
    let cfg = generic_test_fixture();
    let amount_1 = LEGACY_THRESHOLD - 1;
    let amount_2 = 1;
    let user_1 = new_user(id: 1, token: cfg.legacy_token, initial_balance: amount_1);
    let user_2 = new_user(id: 2, token: cfg.legacy_token, initial_balance: amount_2);
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };

    // Swap without passing the threshold.
    approve_and_swap_to_new(:cfg, user: user_1, amount: amount_1);

    // Assert contract balance (send has not been triggered).
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), amount_1);

    // Pass the threshold.
    approve_and_swap_to_new(:cfg, user: user_2, amount: amount_2);

    // Assert contract balance (send has been triggered).
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), 0);
}

#[test]
fn test_swap_send_to_l1_too_many_batches() {
    let cfg = deploy_token_migration();
    verify_l1_recipient(:cfg);
    let amount = LEGACY_THRESHOLD * MAX_BATCH_COUNT.into() + LEGACY_THRESHOLD / 2 + 1;
    let user_1 = new_user(id: 1, token: cfg.legacy_token, initial_balance: amount);
    let user_2 = new_user(id: 2, token: cfg.legacy_token, initial_balance: amount);
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };

    // Trigger `MAX_BATCH_COUNT` batches.
    supply_contract(target: token_migration_contract, token: cfg.new_token, :amount);
    approve_and_swap_to_new(:cfg, user: user_1, :amount);
    assert_eq!(
        legacy_dispatcher.balance_of(account: token_migration_contract), LEGACY_THRESHOLD / 2 + 1,
    );

    // Attempt to trigger `MAX_BATCH_COUNT + 1` batches.
    supply_contract(target: token_migration_contract, token: cfg.new_token, :amount);
    approve_and_swap_to_new(:cfg, user: user_2, :amount);
    assert_eq!(
        legacy_dispatcher.balance_of(account: token_migration_contract), LEGACY_THRESHOLD + 2,
    );

    // Trigger with zero swap.
    approve_and_swap_to_new(:cfg, user: user_2, amount: Zero::zero());
    assert_eq!(legacy_dispatcher.balance_of(account: token_migration_contract), 2);
}

#[test]
#[feature("safe_dispatcher")]
fn test_swap_send_to_l1_without_l1_recipient_verified() {
    let cfg = deploy_token_migration();
    let token_migration_safe = ITokenMigrationSafeDispatcher {
        contract_address: cfg.token_migration_contract,
    };
    let legacy_token = IERC20Dispatcher { contract_address: cfg.legacy_token.contract_address() };
    let amount = LEGACY_THRESHOLD;
    supply_contract(target: cfg.token_migration_contract, token: cfg.new_token, :amount);
    let user = new_user(id: 0, token: cfg.legacy_token, initial_balance: amount);

    cheat_caller_address_once(
        contract_address: cfg.legacy_token.contract_address(), caller_address: user,
    );
    legacy_token.approve(spender: cfg.token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: cfg.token_migration_contract, caller_address: user);
    let result = token_migration_safe.swap_to_new(:amount);
    assert_panic_with_felt_error(:result, expected_error: Errors::L1_RECIPIENT_NOT_VERIFIED);
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

#[test]
#[feature("safe_dispatcher")]
fn test_allow_swap_to_legacy() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration = ITokenMigrationDispatcher { contract_address: token_migration_contract };
    let token_migration_safe = ITokenMigrationSafeDispatcher {
        contract_address: token_migration_contract,
    };
    let legacy = IERC20Dispatcher { contract_address: cfg.legacy_token.contract_address() };
    let new = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };

    // Check reverse swap is allowed by default.
    assert!(token_migration.can_swap_to_legacy());

    // Supply contract and user.
    let amount = INITIAL_CONTRACT_SUPPLY / 10;
    supply_contract(target: token_migration_contract, token: cfg.legacy_token, :amount);
    let user = new_user(id: 0, token: cfg.new_token, initial_balance: 0);
    supply_contract(target: user, token: cfg.new_token, :amount);

    // Swap to legacy.
    approve_and_swap_to_legacy(:cfg, :user, amount: amount / 2);

    // Check balances.
    assert_eq!(legacy.balance_of(account: user), amount / 2);
    assert_eq!(new.balance_of(account: user), amount / 2);
    assert_eq!(legacy.balance_of(account: token_migration_contract), amount / 2);
    assert_eq!(new.balance_of(account: token_migration_contract), amount / 2);

    // Set to false and try to swap to legacy again.
    allow_swap_to_legacy(:cfg, allow_swap: false);
    assert!(!token_migration.can_swap_to_legacy());
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    let res = token_migration_safe.swap_to_legacy(amount: amount / 2);
    assert_panic_with_felt_error(result: res, expected_error: Errors::REVERSE_SWAP_DISABLED);

    // Check balances.
    assert_eq!(legacy.balance_of(account: user), amount / 2);
    assert_eq!(new.balance_of(account: user), amount / 2);
    assert_eq!(legacy.balance_of(account: token_migration_contract), amount / 2);
    assert_eq!(new.balance_of(account: token_migration_contract), amount / 2);

    // Set to true and try to swap to legacy again.
    allow_swap_to_legacy(:cfg, allow_swap: true);
    assert!(token_migration.can_swap_to_legacy());
    approve_and_swap_to_legacy(:cfg, :user, amount: amount / 2);

    // Check balances.
    assert_eq!(legacy.balance_of(account: user), amount);
    assert_eq!(new.balance_of(account: user), Zero::zero());
    assert_eq!(legacy.balance_of(account: token_migration_contract), Zero::zero());
    assert_eq!(new.balance_of(account: token_migration_contract), amount);
}

#[test]
#[feature("safe_dispatcher")]
fn test_allow_swap_to_legacy_assertions() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration_admin_safe_dispatcher = ITokenMigrationAdminSafeDispatcher {
        contract_address: token_migration_contract,
    };

    // Catch only owner.
    let result = token_migration_admin_safe_dispatcher.allow_swap_to_legacy(allow_swap: true);
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);
}

#[test]
fn test_token_getters() {
    let cfg = deploy_token_migration();
    let token_migration_contract = cfg.token_migration_contract;
    let token_migration = ITokenMigrationDispatcher { contract_address: token_migration_contract };
    let legacy_token_address = cfg.legacy_token.contract_address();
    let new_token_address = cfg.new_token.contract_address();
    assert_eq!(token_migration.get_legacy_token(), legacy_token_address);
    assert_eq!(token_migration.get_new_token(), new_token_address);
}
