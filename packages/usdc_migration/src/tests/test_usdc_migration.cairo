use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{EventSpyTrait, EventsFilterTrait, spy_events};
use starkware_utils::constants::MAX_U256;
use starkware_utils_testing::event_test_utils::assert_number_of_events;
use starkware_utils_testing::test_utils::{assert_expected_event_emitted, cheat_caller_address_once};
use usdc_migration::events::USDCMigrationEvents;
use usdc_migration::interface::{IUSDCMigrationDispatcher, IUSDCMigrationDispatcherTrait};
use usdc_migration::tests::test_utils::constants::INITIAL_SUPPLY;
use usdc_migration::tests::test_utils::{
    deploy_usdc_migration, load_contract_address, new_user, supply_migration_contract_with_native,
};
#[test]
fn test_constructor() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    // Assert contract storage is initialized correctly.
    assert_eq!(
        cfg.legacy_token, load_contract_address(usdc_migration_contract, selector!("legacy_token")),
    );
    assert_eq!(
        cfg.native_token, load_contract_address(usdc_migration_contract, selector!("native_token")),
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
    let legacy_dispacther = IERC20Dispatcher { contract_address: cfg.legacy_token };
    let native_dispacther = IERC20Dispatcher { contract_address: cfg.native_token };
    assert_eq!(
        legacy_dispacther.allowance(owner: usdc_migration_contract, spender: cfg.owner_l2_address),
        MAX_U256,
    );
    assert_eq!(
        native_dispacther.allowance(owner: usdc_migration_contract, spender: cfg.owner_l2_address),
        MAX_U256,
    );
}

#[test]
fn test_migrate() {
    let cfg = deploy_usdc_migration();
    let amount = INITIAL_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, :amount);
    supply_migration_contract_with_native(:cfg, :amount);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_dispatcher = IUSDCMigrationDispatcher {
        contract_address: usdc_migration_contract,
    };
    let legacy_dispatcher = IERC20Dispatcher { contract_address: cfg.legacy_token };
    let native_dispatcher = IERC20Dispatcher { contract_address: cfg.native_token };

    // Spy events.
    let mut spy = spy_events();

    // Approve and migrate.
    cheat_caller_address_once(contract_address: cfg.legacy_token, caller_address: user);
    legacy_dispatcher.approve(spender: usdc_migration_contract, :amount);
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    usdc_migration_dispatcher.migrate(:amount);

    // Assert balances are correct.
    assert_eq!(legacy_dispatcher.balance_of(account: user), 0);
    assert_eq!(legacy_dispatcher.balance_of(account: usdc_migration_contract), amount);
    assert_eq!(native_dispatcher.balance_of(account: user), amount);
    assert_eq!(native_dispatcher.balance_of(account: usdc_migration_contract), 0);

    // Assert event is emitted.
    let events = spy.get_events().emitted_by(contract_address: usdc_migration_contract).events;
    assert_number_of_events(actual: events.len(), expected: 1, message: "migrate");
    assert_expected_event_emitted(
        spied_event: events[0],
        expected_event: USDCMigrationEvents::USDCMigratedEvent { amount, user },
        expected_event_selector: @selector!("USDCMigrated"),
        expected_event_name: "USDCMigrated",
    );
}

#[test]
#[should_panic(expected: "Insufficient USDC balance")]
fn test_migrate_insufficient_usdc_balance() {
    let cfg = deploy_usdc_migration();
    let amount = INITIAL_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, :amount);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_dispatcher = IUSDCMigrationDispatcher {
        contract_address: usdc_migration_contract,
    };

    // Migrate with insufficient USDC balance.
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    usdc_migration_dispatcher.migrate(:amount);
}

#[test]
#[should_panic(expected: 'ERC20: insufficient allowance')]
fn test_migrate_insufficient_allowance() {
    let cfg = deploy_usdc_migration();
    let amount = INITIAL_SUPPLY / 10;
    let user = new_user(:cfg, id: 0, :amount);
    supply_migration_contract_with_native(:cfg, :amount);
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_dispatcher = IUSDCMigrationDispatcher {
        contract_address: usdc_migration_contract,
    };
    let legacy_dispatcher = IERC20Dispatcher { contract_address: cfg.legacy_token };

    // Approve and migrate.
    cheat_caller_address_once(contract_address: cfg.legacy_token, caller_address: user);
    legacy_dispatcher.approve(spender: usdc_migration_contract, amount: amount / 2);
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: user);
    usdc_migration_dispatcher.migrate(:amount);
}
