use openzeppelin::token::erc20::mocks::DualCaseERC20Mock;

#[starknet::contract]
pub mod TokenBridgeMock {
    use starknet::storage::{StorableStoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, EthAddress};
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
        fn get_l1_token(self: @ContractState, l2_token: ContractAddress) -> EthAddress {
            assert_eq!(l2_token, self.l2_token_address.read(), "Invalid L2 token address");
            self.l1_token_address.read()
        }

        fn initiate_token_withdraw(
            ref self: ContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256,
        ) {
            assert_eq!(l1_token, self.l1_token_address.read(), "Invalid L1 token address");
        }
    }
}
