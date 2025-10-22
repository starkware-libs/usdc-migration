#[starknet::contract]
pub mod USDCMigration {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::StoragePointerWriteAccess;
    use starknet::{ContractAddress, EthAddress};
    use starkware_utils::constants::MAX_U256;
    use usdc_migration::interface::{IUSDCMigration, IUSDCMigrationConfig};

    #[storage]
    struct Storage {
        /// The phased out token being swapped for the new one.
        // TODO: Consider change to dispatcher.
        legacy_token: ContractAddress,
        /// The new token swapping the legacy one.
        // TODO: Consider change to dispatcher.
        native_token: ContractAddress,
        /// Ethereum address to which the legacy token is bridged.
        l1_recipient: EthAddress,
        /// Address in L2 that gets the remaining USDC.
        owner_l2_address: ContractAddress,
        /// Token bridge address.
        starkgate_address: ContractAddress,
        /// The threshold amount that triggers transferring the legacy token to the L1 recipient.
        legacy_threshold: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event { //event variables
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        legacy_token: ContractAddress,
        native_token: ContractAddress,
        l1_recipient: EthAddress,
        owner_l2_address: ContractAddress,
        starkgate_address: ContractAddress,
        legacy_threshold: u256,
    ) {
        self.legacy_token.write(legacy_token);
        self.native_token.write(native_token);
        self.l1_recipient.write(l1_recipient);
        self.owner_l2_address.write(owner_l2_address);
        self.starkgate_address.write(starkgate_address);
        self.legacy_threshold.write(legacy_threshold);
        // Infinite approval to l2 address for both legacy and native tokens.
        let legacy_dispacther = IERC20Dispatcher { contract_address: legacy_token };
        let native_dispacther = IERC20Dispatcher { contract_address: native_token };
        legacy_dispacther.approve(spender: owner_l2_address, amount: MAX_U256);
        native_dispacther.approve(spender: owner_l2_address, amount: MAX_U256);
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationImpl of IUSDCMigration<ContractState> { //impl logic
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationConfigImpl of IUSDCMigrationConfig<ContractState> { //impl logic
        fn set_legacy_threshold(ref self: ContractState, legacy_threshold: u256) {
            // TODO: Assert caller is owner.
            // TODO: Assert the given threshold is valid according to the fixed transfer units.
            // TODO: Allow threshold zero?
            self.legacy_threshold.write(legacy_threshold);
            // TODO: Update transfer unit accordingly.
        // TODO: Emit event?
        // TODO: Send to L1 here according the new threshold?
        }
    }
}
