use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use starkware_utils::constants::MAX_U256;
use usdc_migration::interface::{IUSDCMigrationOwnerDispatcher, IUSDCMigrationOwnerDispatcherTrait};
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
        cfg.owner_l2_address,
        load_contract_address(usdc_migration_contract, selector!("owner_l2_address")),
    );
    assert_eq!(
        cfg.starkgate_address,
        load_contract_address(usdc_migration_contract, selector!("starkgate_address")),
    );
    assert_eq!(LEGACY_THRESHOLD, load_u256(usdc_migration_contract, selector!("legacy_threshold")));
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
fn test_set_legacy_threshold() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    let usdc_migration_owner_dispatcher = IUSDCMigrationOwnerDispatcher {
        contract_address: usdc_migration_contract,
    };
    // Set the threshold to a new value.
    let new_threshold = LEGACY_THRESHOLD * 2;
    usdc_migration_owner_dispatcher.set_legacy_threshold(threshold: new_threshold);
    assert_eq!(new_threshold, load_u256(usdc_migration_contract, selector!("legacy_threshold")));
}
