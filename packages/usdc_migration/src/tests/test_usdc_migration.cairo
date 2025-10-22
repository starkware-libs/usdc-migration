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
use usdc_migration::tests::test_utils::{deploy_usdc_migration, load_contract_address};

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
    // Assert owner is set correctly.
    let ownable_dispatcher = IOwnableDispatcher { contract_address: usdc_migration_contract };
    assert_eq!(ownable_dispatcher.owner(), cfg.owner_l2_address);
}

#[test]
fn test_upgrade() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let owner = cfg.owner_l2_address;
    let mut spy = snforge_std::spy_events();
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
    let owner = cfg.owner_l2_address;
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
