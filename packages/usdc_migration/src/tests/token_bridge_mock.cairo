#[starknet::contract]
pub mod TokenBridgeMock {
    use starknet::storage::{StorableStoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, EthAddress, get_caller_address};
    use starkware_utils::erc20::erc20_mocks::{
        IERC20BurnableDispatcher, IERC20BurnableDispatcherTrait,
    };
    use usdc_migration::starkgate_interface::ITokenBridge;

    #[storage]
    struct Storage {
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, l1_token_address: EthAddress, l2_token_address: ContractAddress,
    ) {
        self.l1_token_address.write(l1_token_address);
        self.l2_token_address.write(l2_token_address);
    }

    #[abi(embed_v0)]
    pub impl TokenBridgeMockImpl of ITokenBridge<ContractState> {
        fn initiate_token_withdraw(
            ref self: ContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256,
        ) {
            assert_eq!(l1_token, self.l1_token_address.read(), "Invalid L1 token address");
            IERC20BurnableDispatcher { contract_address: self.l2_token_address.read() }
                .burn(account: get_caller_address(), :amount);
        }
    }
}
