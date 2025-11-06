use constants::{
    DECIMALS, INITIAL_CONTRACT_SUPPLY, INITIAL_SUPPLY, L1_RECIPIENT, L1_TOKEN_ADDRESS,
    LEGACY_THRESHOLD, OWNER_ADDRESS,
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, CustomToken, DeclareResultTrait, L1HandlerTrait, Token, TokenTrait,
    set_balance,
};
use starknet::{ContractAddress, EthAddress, Store};
use starkware_utils_testing::test_utils::{Deployable, TokenConfig, cheat_caller_address_once};
use token_migration::interface::{
    ITokenMigrationAdminDispatcher, ITokenMigrationAdminDispatcherTrait, ITokenMigrationDispatcher,
    ITokenMigrationDispatcherTrait,
};
use token_migration::tests::token_bridge_mock::{
    ITokenBridgeMockDispatcher, ITokenBridgeMockDispatcherTrait,
};

#[derive(Debug, Drop, Copy)]
pub(crate) struct TokenMigrationCfg {
    pub token_migration_contract: ContractAddress,
    pub legacy_token: Token,
    pub new_token: Token,
    pub l1_recipient: EthAddress,
    pub owner: ContractAddress,
    pub starkgate_address: ContractAddress,
}

pub(crate) mod constants {
    use core::num::traits::Pow;
    use starknet::{ContractAddress, EthAddress};
    use crate::token_migration::TokenMigration::LARGE_BATCH_SIZE;

    // Total legacy Token supply is ~140 million.
    pub const INITIAL_SUPPLY: u256 = 140
        * 10_u256.pow(6)
        * 10_u256.pow(6); // 140 * million * decimals
    // TODO: Change to the real value.
    pub const LEGACY_THRESHOLD: u256 = LARGE_BATCH_SIZE;
    pub const INITIAL_CONTRACT_SUPPLY: u256 = INITIAL_SUPPLY / 20;
    pub const DECIMALS: u8 = 6;
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

pub(crate) fn generic_test_fixture() -> TokenMigrationCfg {
    let cfg = deploy_token_migration();
    supply_contract(
        target: cfg.token_migration_contract, token: cfg.new_token, amount: INITIAL_CONTRACT_SUPPLY,
    );
    verify_l1_recipient(:cfg);
    cfg
}

pub(crate) fn verify_l1_recipient(cfg: TokenMigrationCfg) {
    let l1_handler = L1HandlerTrait::new(
        cfg.token_migration_contract, selector!("verify_l1_recipient"),
    );
    let _ = l1_handler
        .execute(from_address: cfg.l1_recipient.into(), payload: ArrayTrait::new().span());
}

pub(crate) fn deploy_tokens(owner: ContractAddress) -> (Token, Token) {
    let legacy_config = TokenConfig {
        name: "Token", symbol: "Token", decimals: DECIMALS, initial_supply: INITIAL_SUPPLY, owner,
    };
    let new_config = TokenConfig {
        name: "Token", symbol: "Token", decimals: DECIMALS, initial_supply: INITIAL_SUPPLY, owner,
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

pub(crate) fn deploy_token_migration() -> TokenMigrationCfg {
    // Setup tokens and token bridge mock.
    let starkgate_address = deploy_mock_bridge();
    let (legacy_token, new_token) = deploy_tokens(owner: starkgate_address);
    ITokenBridgeMockDispatcher { contract_address: starkgate_address }
        .set_bridged_token(
            l2_token_address: legacy_token.contract_address(), l1_token_address: L1_TOKEN_ADDRESS(),
        );

    // Deploy Token migration contract.
    let mut calldata = ArrayTrait::new();
    legacy_token.contract_address().serialize(ref calldata);
    new_token.contract_address().serialize(ref calldata);
    L1_RECIPIENT().serialize(ref calldata);
    OWNER_ADDRESS().serialize(ref calldata);
    starkgate_address.serialize(ref calldata);
    LEGACY_THRESHOLD.serialize(ref calldata);
    let token_migration_contract = snforge_std::declare("TokenMigration").unwrap().contract_class();
    let (token_migration_contract_address, _) = token_migration_contract.deploy(@calldata).unwrap();
    // Return the configuration with the deployed contract address.
    TokenMigrationCfg {
        token_migration_contract: token_migration_contract_address,
        legacy_token,
        new_token,
        l1_recipient: L1_RECIPIENT(),
        owner: OWNER_ADDRESS(),
        starkgate_address,
    }
}

// L2 token address needs to be set after deployment.
pub(crate) fn deploy_mock_bridge() -> ContractAddress {
    let token_bridge_mock_contract = snforge_std::declare("TokenBridgeMock")
        .unwrap()
        .contract_class();
    let (token_bridge_mock_contract_address, _) = token_bridge_mock_contract
        .deploy(@ArrayTrait::new())
        .unwrap();
    token_bridge_mock_contract_address
}

pub(crate) fn new_user(id: u8, token: Token, initial_balance: u256) -> ContractAddress {
    let user_address = _generate_user_address(:id);
    set_balance(target: user_address, new_balance: initial_balance, :token);
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
pub(crate) fn generic_load<T, +Store<T>, +Serde<T>>(
    target: ContractAddress, storage_address: felt252,
) -> T {
    let mut value = snforge_std::load(:target, :storage_address, size: Store::<T>::size().into())
        .span();
    Serde::deserialize(ref value).unwrap()
}

pub(crate) fn approve_and_swap_to_new(cfg: TokenMigrationCfg, user: ContractAddress, amount: u256) {
    let token_migration_contract = cfg.token_migration_contract;
    let legacy_token_address = cfg.legacy_token.contract_address();
    let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token_address };
    let token_migration_dispatcher = ITokenMigrationDispatcher {
        contract_address: token_migration_contract,
    };
    cheat_caller_address_once(contract_address: legacy_token_address, caller_address: user);
    legacy_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    token_migration_dispatcher.swap_to_new(:amount);
}

pub(crate) fn approve_and_swap_to_legacy(
    cfg: TokenMigrationCfg, user: ContractAddress, amount: u256,
) {
    let token_migration_contract = cfg.token_migration_contract;
    let new_token_address = cfg.new_token.contract_address();
    let new_dispatcher = IERC20Dispatcher { contract_address: new_token_address };
    let token_migration_dispatcher = ITokenMigrationDispatcher {
        contract_address: token_migration_contract,
    };
    cheat_caller_address_once(contract_address: new_token_address, caller_address: user);
    new_dispatcher.approve(spender: token_migration_contract, :amount);
    cheat_caller_address_once(contract_address: token_migration_contract, caller_address: user);
    token_migration_dispatcher.swap_to_legacy(:amount);
}

pub(crate) fn allow_swap_to_legacy(cfg: TokenMigrationCfg, allow_swap: bool) {
    cheat_caller_address_once(
        contract_address: cfg.token_migration_contract, caller_address: cfg.owner,
    );
    ITokenMigrationAdminDispatcher { contract_address: cfg.token_migration_contract }
        .allow_swap_to_legacy(:allow_swap);
}

pub(crate) fn verify_owner(cfg: TokenMigrationCfg) {
    cheat_caller_address_once(
        contract_address: cfg.token_migration_contract, caller_address: cfg.owner,
    );
    ITokenMigrationAdminDispatcher { contract_address: cfg.token_migration_contract }
        .verify_owner();
}

pub(crate) fn set_legacy_threshold(cfg: TokenMigrationCfg, threshold: u256) {
    cheat_caller_address_once(
        contract_address: cfg.token_migration_contract, caller_address: cfg.owner,
    );
    ITokenMigrationAdminDispatcher { contract_address: cfg.token_migration_contract }
        .set_legacy_threshold(:threshold);
}

pub(crate) fn assert_balances(
    cfg: TokenMigrationCfg, account: ContractAddress, legacy_balance: u256, new_balance: u256,
) {
    let legacy_dispatcher = IERC20Dispatcher {
        contract_address: cfg.legacy_token.contract_address(),
    };
    let new_dispatcher = IERC20Dispatcher { contract_address: cfg.new_token.contract_address() };
    assert_eq!(legacy_dispatcher.balance_of(:account), legacy_balance);
    assert_eq!(new_dispatcher.balance_of(:account), new_balance);
}

/// Mock contract to declare a mock class hash for testing upgrade.
#[starknet::contract]
pub mod MockContract {
    #[storage]
    struct Storage {}
}
