use constants::{
    INITIAL_CONTRACT_SUPPLY, INITIAL_SUPPLY, L1_RECIPIENT, L1_TOKEN_ADDRESS, LEGACY_THRESHOLD,
    OWNER_ADDRESS,
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, CustomToken, DeclareResultTrait, Token, TokenTrait, set_balance,
};
use starknet::{ContractAddress, EthAddress};
use starkware_utils_testing::test_utils::{Deployable, TokenConfig, cheat_caller_address_once};
use usdc_migration::interface::{IUSDCMigrationDispatcher, IUSDCMigrationDispatcherTrait};

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
    use crate::usdc_migration::USDCMigration::LARGE_BATCH_SIZE;

    // Total legacy USDC supply is ~140 million.
    pub const INITIAL_SUPPLY: u256 = 140
        * 10_u256.pow(6)
        * 10_u256.pow(6); // 140 * million * decimals
    // TODO: Change to the real value.
    pub const LEGACY_THRESHOLD: u256 = LARGE_BATCH_SIZE;
    pub const INITIAL_CONTRACT_SUPPLY: u256 = INITIAL_SUPPLY / 20;
    pub fn OWNER_ADDRESS() -> ContractAddress {
        'OWNER_ADDRESS'.try_into().unwrap()
    }
    pub fn L1_RECIPIENT() -> EthAddress {
        'L1_RECIPIENT'.try_into().unwrap()
    }
    pub fn L1_TOKEN_ADDRESS() -> EthAddress {
        'L1_TOKEN_ADDRESS'.try_into().unwrap()
    }
}

pub(crate) fn generic_test_fixture() -> USDCMigrationCfg {
    let cfg = deploy_usdc_migration();
    supply_contract(
        target: cfg.usdc_migration_contract, token: cfg.new_token, amount: INITIAL_CONTRACT_SUPPLY,
    );
    cfg
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
    let starkgate_address = deploy_token_bridge_mock(:legacy_token);
    let mut calldata = ArrayTrait::new();
    legacy_token.contract_address().serialize(ref calldata);
    new_token.contract_address().serialize(ref calldata);
    L1_RECIPIENT().serialize(ref calldata);
    OWNER_ADDRESS().serialize(ref calldata);
    starkgate_address.serialize(ref calldata);
    LEGACY_THRESHOLD.serialize(ref calldata);
    L1_TOKEN_ADDRESS().serialize(ref calldata);
    let usdc_migration_contract = snforge_std::declare("USDCMigration").unwrap().contract_class();
    let (usdc_migration_contract_address, _) = usdc_migration_contract.deploy(@calldata).unwrap();
    // Return the configuration with the deployed contract address.
    USDCMigrationCfg {
        usdc_migration_contract: usdc_migration_contract_address,
        legacy_token,
        new_token,
        l1_recipient: L1_RECIPIENT(),
        owner: OWNER_ADDRESS(),
        starkgate_address,
    }
}

pub(crate) fn deploy_token_bridge_mock(legacy_token: Token) -> ContractAddress {
    let mut calldata = ArrayTrait::new();
    L1_TOKEN_ADDRESS().serialize(ref calldata);
    legacy_token.contract_address().serialize(ref calldata);
    let token_bridge_mock_contract = snforge_std::declare("TokenBridgeMock")
        .unwrap()
        .contract_class();
    let (token_bridge_mock_contract_address, _) = token_bridge_mock_contract
        .deploy(@calldata)
        .unwrap();
    token_bridge_mock_contract_address
}

pub(crate) fn new_user(cfg: USDCMigrationCfg, id: u8, legacy_supply: u256) -> ContractAddress {
    let user_address = _generate_user_address(:id);
    set_balance(target: user_address, new_balance: legacy_supply, token: cfg.legacy_token);
    user_address
}

fn _generate_user_address(id: u8) -> ContractAddress {
    ('USER_ADDRESS' + id.into()).try_into().unwrap()
}

pub(crate) fn supply_contract(target: ContractAddress, token: Token, amount: u256) {
    let current_balance = IERC20Dispatcher { contract_address: token.contract_address() }
        .balance_of(account: target);
    set_balance(:target, new_balance: current_balance + amount, :token);
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

pub(crate) fn approve_and_swap(
    migration_contract: ContractAddress, user: ContractAddress, amount: u256, token: Token,
) {
    let legacy_token_address = token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: migration_contract, :amount);
    cheat_caller_address_once(contract_address: migration_contract, caller_address: user);
    IUSDCMigrationDispatcher { contract_address: migration_contract }.swap_to_new(:amount);
}

/// Mock contract to declare a mock class hash for testing upgrade.
#[starknet::contract]
pub mod MockContract {
    #[storage]
    struct Storage {}
}
