use constants::{INITIAL_SUPPLY, OWNER_ADDRESS};
use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::ContractAddress;
use starkware_utils_testing::test_utils::{Deployable, TokenConfig};

#[derive(Debug, Drop, Copy)]
pub(crate) struct USDCMigrationCfg {
    pub usdc_migration_contract: ContractAddress,
    pub usdc_e_token: ContractAddress,
    pub usdc_token: ContractAddress,
    pub owner_l1_address: ContractAddress,
    pub owner_l2_address: ContractAddress,
}

pub(crate) mod constants {
    use starknet::ContractAddress;

    pub const INITIAL_SUPPLY: u256 = 1000000000000000000000000000;
    pub fn OWNER_ADDRESS() -> ContractAddress {
        'OWNER_ADDRESS'.try_into().unwrap()
    }
}

pub(crate) fn deploy_usdc_migration() -> USDCMigrationCfg {
    // Deploy USDC-E and USDC tokens.
    let usdc_e_config = TokenConfig {
        name: "USDC-E", symbol: "USDC-E", initial_supply: INITIAL_SUPPLY, owner: OWNER_ADDRESS(),
    };
    let usdc_config = TokenConfig {
        name: "USDC", symbol: "USDC", initial_supply: INITIAL_SUPPLY, owner: OWNER_ADDRESS(),
    };
    let usdc_e_state = usdc_e_config.deploy();
    let usdc_state = usdc_config.deploy();
    let usdc_e_token = usdc_e_state.address;
    let usdc_token = usdc_state.address;
    // Deploy USDCMigration contract.
    let mut calldata = ArrayTrait::new();
    usdc_e_token.serialize(ref calldata);
    usdc_token.serialize(ref calldata);
    OWNER_ADDRESS().serialize(ref calldata);
    OWNER_ADDRESS().serialize(ref calldata);
    let usdc_migration_contract = snforge_std::declare("USDCMigration").unwrap().contract_class();
    let (usdc_migration_contract_address, _) = usdc_migration_contract.deploy(@calldata).unwrap();
    // Return the configuration with the deployed contract address.
    USDCMigrationCfg {
        usdc_migration_contract: usdc_migration_contract_address,
        usdc_e_token,
        usdc_token,
        owner_l2_address: OWNER_ADDRESS(),
        owner_l1_address: OWNER_ADDRESS(),
    }
}

// TODO: Move to starkware_utils_testing.
pub(crate) fn load_contract_address(
    target: ContractAddress, storage_address: felt252,
) -> ContractAddress {
    let value = snforge_std::load(:target, :storage_address, size: 1);
    (*value[0]).try_into().unwrap()
}
