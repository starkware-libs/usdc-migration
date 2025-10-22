use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use starkware_utils::constants::MAX_U256;
use usdc_migration::tests::test_utils::{deploy_usdc_migration, load_contract_address};
#[test]
fn test_constructor() {
    let cfg = deploy_usdc_migration();
    let usdc_migration_contract = cfg.usdc_migration_contract;
    // Assert contract storage is initialized correctly.
    assert_eq!(
        cfg.usdc_e_token, load_contract_address(usdc_migration_contract, selector!("usdc_e_token")),
    );
    assert_eq!(
        cfg.usdc_token, load_contract_address(usdc_migration_contract, selector!("usdc_token")),
    );
    assert_eq!(
        cfg.owner_l1_address,
        load_contract_address(usdc_migration_contract, selector!("owner_l1_address")),
    );
    assert_eq!(
        cfg.owner_l2_address,
        load_contract_address(usdc_migration_contract, selector!("owner_l2_address")),
    );
    // Assert infinite approval to owner_l2_address for both USDC.e and USDC.
    let usdc_e_dispacther = IERC20Dispatcher { contract_address: cfg.usdc_e_token };
    let usdc_dispacther = IERC20Dispatcher { contract_address: cfg.usdc_token };
    assert_eq!(
        usdc_e_dispacther.allowance(owner: usdc_migration_contract, spender: cfg.owner_l2_address),
        MAX_U256,
    );
    assert_eq!(
        usdc_dispacther.allowance(owner: usdc_migration_contract, spender: cfg.owner_l2_address),
        MAX_U256,
    );
}
