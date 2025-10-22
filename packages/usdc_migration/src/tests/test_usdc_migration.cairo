use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{EventSpyTrait, EventsFilterTrait, spy_events};
use starkware_utils::constants::MAX_U256;
use starkware_utils::errors::Describable;
use starkware_utils_testing::event_test_utils::assert_number_of_events;
use starkware_utils_testing::test_utils::{
    assert_expected_event_emitted, assert_panic_with_error, assert_panic_with_felt_error,
    cheat_caller_address_once,
};
use usdc_migration::errors::USDCMigrationError;
use usdc_migration::events::USDCMigrationEvents;
use usdc_migration::interface::{
    IUSDCMigrationDispatcher, IUSDCMigrationDispatcherTrait, IUSDCMigrationSafeDispatcher,
    IUSDCMigrationSafeDispatcherTrait,
};
use usdc_migration::tests::test_utils::constants::INITIAL_SUPPLY;
use usdc_migration::tests::test_utils::{
    deploy_usdc_migration, generic_test_fixture, load_contract_address, new_user,
    supply_migration_contract_with_new_token,
};
#[test]
fn test_constructor() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    // Assert contract storage is initialized correctly.
    assert_eq!(
        cfg.legacy_token,
        load_contract_address(usdc_migration_contract, selector!("legacy_token_dispatcher")),
    );
    assert_eq!(
        cfg.new_token,
        load_contract_address(usdc_migration_contract, selector!("new_token_dispatcher")),
    );
    let l1_recipient = (*snforge_std::load(
        target: usdc_migration_contract, storage_address: selector!("l1_recipient"), size: 1,
    )[0])
        .try_into()
        .unwrap();
    assert_eq!(cfg.l1_recipient, l1_recipient);
    assert_eq!(
        cfg.owner_l2_address,
        load_contract_address(usdc_migration_contract, selector!("owner_l2_address")),
    );
    assert_eq!(
        cfg.starkgate_address,
        load_contract_address(usdc_migration_contract, selector!("starkgate_address")),
    );
    // Assert infinite approval to owner_l2_address for both USDC.e and USDC.
    let legacy_dispatcher = IERC20Dispatcher { contract_address: cfg.legacy_token };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token };
    assert_eq!(
        legacy_dispatcher.allowance(owner: usdc_migration_contract, spender: cfg.owner_l2_address),
        MAX_U256,
    );
    assert_eq!(
        new_dispatcher.allowance(owner: usdc_migration_contract, spender: cfg.owner_l2_address),
        MAX_U256,
    );
}

#[test]
fn test_exchange_legacy_for_new() {
    let cfg = generic_test_fixture();
    let amount = cfg.initial_contract_supply / 10;
    let user = new_user(:cfg, id: 0, :amount);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_dispatcher = IUSDCMigrationDispatcher {
        contract_address: usdc_migration_contract,
    };
    let legacy_dispatcher = IERC20Dispatcher { contract_address: cfg.legacy_token };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token };

    // Spy events.
    let mut spy = spy_events();

    // Approve and migrate.
    cheat_caller_address_once(contract_address: cfg.legacy_token, caller_address: user);
    legacy_dispatcher.approve(spender: usdc_migration_contract, :amount);
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    usdc_migration_dispatcher.exchange_legacy_for_new(:amount);

    // Assert user balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), 0);
    assert_eq!(new_dispatcher.balance_of(account: user), amount);

    // Assert contract balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: usdc_migration_contract), amount);
    assert_eq!(
        new_dispatcher.balance_of(account: usdc_migration_contract),
        cfg.initial_contract_supply - amount,
    );

    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: usdc_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "migrate");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: USDCMigrationEvents::USDCMigratedEvent { user, amount },
        expected_event_selector: @selector!("USDCMigrated"),
        expected_event_name: "USDCMigrated",
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_exchange_legacy_for_new_assertions() {
    let cfg = deploy_usdc_migration();
    let amount = INITIAL_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, :amount);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_safe_dispatcher = IUSDCMigrationSafeDispatcher {
        contract_address: usdc_migration_contract,
    };
    let legacy_dispatcher = IERC20Dispatcher { contract_address: cfg.legacy_token };

    // Insufficient balance.
    cheat_caller_address_once(contract_address: cfg.usdc_migration_contract, caller_address: user);
    let res = usdc_migration_safe_dispatcher.exchange_legacy_for_new(:amount);
    assert_panic_with_error(res, USDCMigrationError::INSUFFICIENT_USDC_BALANCE.describe());

    // Insufficient allowance.
    supply_migration_contract_with_new_token(:cfg, :amount);
    cheat_caller_address_once(contract_address: cfg.legacy_token, caller_address: user);
    legacy_dispatcher.approve(spender: usdc_migration_contract, amount: amount / 2);
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    let res = usdc_migration_safe_dispatcher.exchange_legacy_for_new(:amount);
    assert_panic_with_felt_error(res, 'ERC20: insufficient allowance');
}
