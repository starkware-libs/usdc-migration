use starknet::ContractAddress;

#[starknet::interface]
pub(crate) trait ITokenBridgeMock<TContractState> {
    fn set_l2_token_address(ref self: TContractState, l2_token_address: ContractAddress);
}

#[starknet::contract]
pub mod TokenBridgeMock {
    use starknet::storage::{StorableStoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, EthAddress, get_caller_address};
    use starkware_utils::interfaces::mintable_token::{
        IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
    };
    use usdc_migration::starkgate_interface::ITokenBridge;
    use usdc_migration::tests::token_bridge_mock::ITokenBridgeMock;

    #[storage]
    struct Storage {
        l1_token_address: EthAddress,
        l2_token_address: Option<ContractAddress>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, l1_token_address: EthAddress) {
        self.l1_token_address.write(l1_token_address);
        self.l2_token_address.write(Option::None);
    }

    #[abi(embed_v0)]
    pub impl TokenBridgeMockImpl of ITokenBridge<ContractState> {
        fn initiate_token_withdraw(
            ref self: ContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256,
        ) {
            assert_eq!(l1_token, self.l1_token_address.read(), "Invalid L1 token address");
            IMintableTokenDispatcher { contract_address: self.l2_token_address.read().unwrap() }
                .permissioned_burn(account: get_caller_address(), :amount);
        }
    }

    #[abi(embed_v0)]
    pub impl TokenBridgeMockAdminImpl of ITokenBridgeMock<ContractState> {
        fn set_l2_token_address(ref self: ContractState, l2_token_address: ContractAddress) {
            self.l2_token_address.write(Option::Some(l2_token_address));
        }
    }
}
