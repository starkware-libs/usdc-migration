use constants::{INITIAL_SUPPLY, L1_RECIPIENT, LEGACY_THRESHOLD, OWNER_ADDRESS, STARKGATE_ADDRESS};
use snforge_std::{ContractClassTrait, CustomToken, DeclareResultTrait, Token, TokenTrait};
use starknet::{ContractAddress, EthAddress};
use starkware_utils_testing::test_utils::{Deployable, TokenConfig};

#[derive(Debug, Drop, Copy)]
pub(crate) struct USDCMigrationCfg {
    pub usdc_migration_contract: ContractAddress,
    pub legacy_token: Token,
    pub new_token: Token,
    pub l1_recipient: EthAddress,
    pub owner: ContractAddress,
    pub starkgate_address: ContractAddress,
}

pub(crate) mod constants {
    use core::num::traits::Pow;
    use starknet::{ContractAddress, EthAddress};

    // Total legacy USDC supply is ~140 million.
    pub const INITIAL_SUPPLY: u256 = 140
        * 10_u256.pow(6)
        * 10_u256.pow(6); // 140 * million * decimals
    // TODO: Change to the real value.
    pub const LEGACY_THRESHOLD: u256 = 100_000;
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

fn deploy_tokens() -> (Token, Token) {
    let legacy_config = TokenConfig {
        name: "Legacy-USDC",
        symbol: "Legacy-USDC",
        initial_supply: INITIAL_SUPPLY,
        owner: OWNER_ADDRESS(),
    };
    let new_config = TokenConfig {
        name: "new-USDC",
        symbol: "new-USDC",
        initial_supply: INITIAL_SUPPLY,
        owner: OWNER_ADDRESS(),
    };
    let legacy_state = legacy_config.deploy();
    let new_state = new_config.deploy();
    let legacy_token = Token::Custom(
        CustomToken {
            contract_address: legacy_state.address,
            balances_variable_selector: selector!("ERC20_balances"),
        },
    );
    let new_token = Token::Custom(
        CustomToken {
            contract_address: new_state.address,
            balances_variable_selector: selector!("ERC20_balances"),
        },
    );
    (legacy_token, new_token)
}

pub(crate) fn deploy_usdc_migration() -> USDCMigrationCfg {
    let (legacy_token, new_token) = deploy_tokens();
    let mut calldata = ArrayTrait::new();
    legacy_token.contract_address().serialize(ref calldata);
    new_token.contract_address().serialize(ref calldata);
    L1_RECIPIENT().serialize(ref calldata);
    OWNER_ADDRESS().serialize(ref calldata);
    STARKGATE_ADDRESS().serialize(ref calldata);
    LEGACY_THRESHOLD.serialize(ref calldata);
    let usdc_migration_contract = snforge_std::declare("USDCMigration").unwrap().contract_class();
    let (usdc_migration_contract_address, _) = usdc_migration_contract.deploy(@calldata).unwrap();
    // Return the configuration with the deployed contract address.
    USDCMigrationCfg {
        usdc_migration_contract: usdc_migration_contract_address,
        legacy_token,
        new_token,
        l1_recipient: L1_RECIPIENT(),
        owner: OWNER_ADDRESS(),
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

// TODO: Move to starkware_utils_testing.
pub(crate) fn load_u256(target: ContractAddress, storage_address: felt252) -> u256 {
    let value = snforge_std::load(:target, :storage_address, size: 2);
    let low = (*value[0]).try_into().unwrap();
    let high = (*value[1]).try_into().unwrap();
    u256 { low, high }
}

/// Mock contract to declare a mock class hash for testing upgrade.
#[starknet::contract]
pub mod MockContract {
    #[storage]
    struct Storage {}
}
