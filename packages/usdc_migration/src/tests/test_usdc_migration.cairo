use core::num::traits::Zero;
use openzeppelin::access::ownable::OwnableComponent::Errors as OwnableErrors;
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::upgrades::interface::{
    IUpgradeableDispatcher, IUpgradeableDispatcherTrait, IUpgradeableSafeDispatcher,
    IUpgradeableSafeDispatcherTrait,
};
use openzeppelin::upgrades::upgradeable::UpgradeableComponent::Errors as UpgradeableErrors;
use snforge_std::DeclareResultTrait;
use starkware_utils::constants::MAX_U256;
use starkware_utils_testing::test_utils::{assert_panic_with_felt_error, cheat_caller_address_once};
use usdc_migration::interface::{
    IUSDCMigrationConfigDispatcher, IUSDCMigrationConfigDispatcherTrait,
    IUSDCMigrationConfigSafeDispatcher, IUSDCMigrationConfigSafeDispatcherTrait,
};
use usdc_migration::tests::test_utils::constants::LEGACY_THRESHOLD;
use usdc_migration::tests::test_utils::{deploy_usdc_migration, load_contract_address, load_u256};

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
        cfg.starkgate_address,
        load_contract_address(usdc_migration_contract, selector!("starkgate_address")),
    );
    assert_eq!(LEGACY_THRESHOLD, load_u256(usdc_migration_contract, selector!("legacy_threshold")));
    // Assert owner is set correctly.
    let ownable_dispatcher = IOwnableDispatcher { contract_address: usdc_migration_contract };
    assert_eq!(ownable_dispatcher.owner(), cfg.owner);
    // Assert infinite approval to owner for both legacy and new tokens.
    let legacy_dispatcher = IERC20Dispatcher { contract_address: cfg.legacy_token };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token };
    assert_eq!(
        legacy_dispatcher.allowance(owner: usdc_migration_contract, spender: cfg.owner), MAX_U256,
    );
    assert_eq!(
        new_dispatcher.allowance(owner: usdc_migration_contract, spender: cfg.owner), MAX_U256,
    );
}

#[test]
fn test_set_legacy_threshold() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_cfg_dispatcher = IUSDCMigrationConfigDispatcher {
        contract_address: usdc_migration_contract,
    };
    // Set the threshold to a new value.
    let new_threshold = LEGACY_THRESHOLD * 2;
    cheat_caller_address_once(contract_address: usdc_migration_contract, caller_address: cfg.owner);
    usdc_migration_cfg_dispatcher.set_legacy_threshold(threshold: new_threshold);
    assert_eq!(new_threshold, load_u256(usdc_migration_contract, selector!("legacy_threshold")));
}

#[test]
#[feature("safe_dispatcher")]
fn test_set_legacy_threshold_assertions() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_cfg_dispatcher = IUSDCMigrationConfigSafeDispatcher {
        contract_address: usdc_migration_contract,
    };
    // Catch the owner error.
    let result = usdc_migration_cfg_dispatcher.set_legacy_threshold(threshold: LEGACY_THRESHOLD);
    assert_panic_with_felt_error(:result, expected_error: OwnableErrors::NOT_OWNER);
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
