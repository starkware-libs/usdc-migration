use constants::{INITIAL_SUPPLY, L1_RECIPIENT, OWNER_ADDRESS, STARKGATE_ADDRESS};
use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::{ContractAddress, EthAddress};
use starkware_utils_testing::test_utils::{Deployable, TokenConfig};

#[derive(Debug, Drop, Copy)]
pub(crate) struct USDCMigrationCfg {
    pub usdc_migration_contract: ContractAddress,
    pub legacy_token: ContractAddress,
    pub native_token: ContractAddress,
    pub l1_recipient: EthAddress,
    pub owner_l2_address: ContractAddress,
    pub starkgate_address: ContractAddress,
}

pub(crate) mod constants {
    use starknet::{ContractAddress, EthAddress};

    pub const INITIAL_SUPPLY: u256 = 1000000000000000000000000000;
    pub fn OWNER_ADDRESS() -> ContractAddress {
        'OWNER_ADDRESS'.try_into().unwrap()
    }
    pub fn L1_RECIPIENT() -> EthAddress {
        'L1_RECIPIENT'.try_into().unwrap()
    }
    pub fn STARKGATE_ADDRESS() -> ContractAddress {
        'STARKGATE_ADDRESS'.try_into().unwrap()
    }
}

pub(crate) fn deploy_usdc_migration() -> USDCMigrationCfg {
    // Deploy legacy and native tokens.
    let legacy_config = TokenConfig {
        name: "Legacy-USDC",
        symbol: "Legacy-USDC",
        initial_supply: INITIAL_SUPPLY,
        owner: OWNER_ADDRESS(),
    };
    let native_config = TokenConfig {
        name: "Native-USDC",
        symbol: "Native-USDC",
        initial_supply: INITIAL_SUPPLY,
        owner: OWNER_ADDRESS(),
    };
    let legacy_state = legacy_config.deploy();
    let native_state = native_config.deploy();
    let legacy_token = legacy_state.address;
    let native_token = native_state.address;
    // Deploy USDCMigration contract.
    let mut calldata = ArrayTrait::new();
    legacy_token.serialize(ref calldata);
    native_token.serialize(ref calldata);
    L1_RECIPIENT().serialize(ref calldata);
    OWNER_ADDRESS().serialize(ref calldata);
    STARKGATE_ADDRESS().serialize(ref calldata);
    let usdc_migration_contract = snforge_std::declare("USDCMigration").unwrap().contract_class();
    let (usdc_migration_contract_address, _) = usdc_migration_contract.deploy(@calldata).unwrap();
    // Return the configuration with the deployed contract address.
    USDCMigrationCfg {
        usdc_migration_contract: usdc_migration_contract_address,
        legacy_token,
        native_token,
        l1_recipient: L1_RECIPIENT(),
        owner_l2_address: OWNER_ADDRESS(),
        starkgate_address: STARKGATE_ADDRESS(),
    }
}

// TODO: Move to starkware_utils_testing.
pub(crate) fn load_contract_address(
    target: ContractAddress, storage_address: felt252,
) -> ContractAddress {
    let value = snforge_std::load(:target, :storage_address, size: 1);
    (*value[0]).try_into().unwrap()
}

/// Mock contract to declare a mock class hash for testing upgrade.
#[starknet::contract]
pub mod MockContract {
    #[storage]
    struct Storage {}
}
