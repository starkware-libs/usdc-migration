use starknet::{ContractAddress, EthAddress};

#[starknet::interface]
pub(crate) trait ITokenBridgeMock<TContractState> {
    fn set_bridged_token(
        ref self: TContractState, l2_token_address: ContractAddress, l1_token_address: EthAddress,
    );
}

#[starknet::contract]
pub mod TokenBridgeMock {
    use core::num::traits::Zero;
    use starknet::storage::{StorableStoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, EthAddress, get_caller_address};
    use starkware_utils::interfaces::mintable_token::{
        IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
    };
    use token_migration::starkgate_interface::ITokenBridge;
    use token_migration::tests::token_bridge_mock::ITokenBridgeMock;

    #[storage]
    struct Storage {
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    pub impl TokenBridgeMockImpl of ITokenBridge<ContractState> {
        fn initiate_token_withdraw(
            ref self: ContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256,
        ) {
            let bridged_token_l2 = self.l2_token_address.read();
            let bridged_token_l1 = self.l1_token_address.read();
            assert_eq!(bridged_token_l2, Zero::zero(), "No bridged token set");
            assert_eq!(l1_token, bridged_token_l1, "Invalid L1 token address");

            IMintableTokenDispatcher { contract_address: bridged_token_l2 }
                .permissioned_burn(account: get_caller_address(), :amount);
        }

        fn get_l1_token(self: @ContractState, l2_token: ContractAddress) -> EthAddress {
            let bridged_token_l2 = self.l2_token_address.read();
            assert_eq!(bridged_token_l2, Zero::zero(), "No bridged token set");
            assert_eq!(l2_token, bridged_token_l2, "Invalid L2 token address");
            self.l1_token_address.read()
        }
    }

    #[abi(embed_v0)]
    pub impl TokenBridgeMockAdminImpl of ITokenBridgeMock<ContractState> {
        fn set_bridged_token(
            ref self: ContractState,
            l2_token_address: ContractAddress,
            l1_token_address: EthAddress,
        ) {
            self.l2_token_address.write(l2_token_address);
            self.l1_token_address.write(l1_token_address);
        }
    }
}
