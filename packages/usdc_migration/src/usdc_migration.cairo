#[starknet::contract]
pub mod USDCMigration {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::StoragePointerWriteAccess;
    use starknet::{ContractAddress, EthAddress};
    use starkware_utils::constants::MAX_U256;
    use usdc_migration::interface::IUSDCMigration;

    #[storage]
    struct Storage {
        /// The phased out token being swapped for the new one.
        // TODO: Consider change to dispatcher.
        legacy_token: ContractAddress,
        /// The new token swapping the legacy one.
        // TODO: Consider change to dispatcher.
        new_token: ContractAddress,
        /// Ethereum address to which the legacy token is bridged.
        l1_recipient: EthAddress,
        /// Address in L2 that gets the remaining USDC.
        owner_l2_address: ContractAddress,
        /// Token bridge address.
        starkgate_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event { //event variables
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        legacy_token: ContractAddress,
        new_token: ContractAddress,
        l1_recipient: EthAddress,
        owner_l2_address: ContractAddress,
        starkgate_address: ContractAddress,
    ) {
        self.legacy_token.write(legacy_token);
        self.new_token.write(new_token);
        self.l1_recipient.write(l1_recipient);
        self.owner_l2_address.write(owner_l2_address);
        self.starkgate_address.write(starkgate_address);
        // Infinite approval to l2 address for both legacy and new tokens.
        let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token };
        let new_dispatcher = IERC20Dispatcher { contract_address: new_token };
        legacy_dispatcher.approve(spender: owner_l2_address, amount: MAX_U256);
        new_dispatcher.approve(spender: owner_l2_address, amount: MAX_U256);
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationImpl of IUSDCMigration<ContractState> { //impl logic
    }
}
