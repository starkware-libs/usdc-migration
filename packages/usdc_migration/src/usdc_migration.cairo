#[starknet::contract]
pub mod USDCMigration {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, EthAddress, get_caller_address, get_contract_address};
    use starkware_utils::constants::MAX_U256;
    use usdc_migration::errors::Error;
    use usdc_migration::interface::{IUSDCMigration, IUSDCMigrationOwner};

    #[storage]
    struct Storage {
        /// The phased out token being swapped for the new one.
        legacy_token_dispatcher: IERC20Dispatcher,
        /// The new token swapping the legacy one.
        new_token_dispatcher: IERC20Dispatcher,
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
        new_token: ContractAddress,
        l1_recipient: EthAddress,
        owner_l2_address: ContractAddress,
        starkgate_address: ContractAddress,
        legacy_threshold: u256,
    ) {
        let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token };
        let new_dispatcher = IERC20Dispatcher { contract_address: new_token };
        self.legacy_token_dispatcher.write(legacy_dispatcher);
        self.new_token_dispatcher.write(new_dispatcher);
        self.l1_recipient.write(l1_recipient);
        self.owner_l2_address.write(owner_l2_address);
        self.starkgate_address.write(starkgate_address);
        self.legacy_threshold.write(legacy_threshold);
        // Infinite approval to l2 address for both legacy and new tokens.
        legacy_dispatcher.approve(spender: owner_l2_address, amount: MAX_U256);
        new_dispatcher.approve(spender: owner_l2_address, amount: MAX_U256);
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationImpl of IUSDCMigration<ContractState> { //impl logic
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationOwnerImpl of IUSDCMigrationOwner<ContractState> { //impl logic
        fn set_legacy_threshold(ref self: ContractState, threshold: u256) {
            // TODO: Assert caller is owner.
            // TODO: Assert the given threshold is valid according to the fixed transfer units.
            // TODO: Allow threshold zero?
            self.legacy_threshold.write(threshold);
            // TODO: Update transfer unit accordingly.
        // TODO: Emit event?
        // TODO: Send to L1 here according the new threshold?
        }

        // TODO: Test once send_legacy_to_l1 is implemented.
        fn send_legacy_to_l1(self: @ContractState) -> u256 {
            // TODO: Assert caller is owner.
            let legacy_dispacther = self.legacy_token_dispatcher.read();
            let legacy_balance = legacy_dispacther.balance_of(account: get_contract_address());
            self._send_legacy_to_l1(amount: legacy_balance);
            return legacy_balance;
        }

        fn verify_owner(self: @ContractState) {
            assert!(
                get_caller_address() == self.owner_l2_address.read(), "{}", Error::VERIFY_L2_FAILED,
            );
            // TODO: Emit event?
        }
    }

    /// Verify the L1 recipient address is a reachable address.
    #[l1_handler]
    fn verify_l1_recipient(self: @ContractState, from_address: felt252) {
        assert!(from_address == self.l1_recipient.read().into(), "{}", Error::VERIFY_L1_FAILED);
        // TODO: Emit event?
    }

    #[generate_trait]
    impl InternalFunctions of InternalUSDCMigrationTrait {
        fn _send_legacy_to_l1(self: @ContractState, amount: u256) {
            // TODO: implement this.
            // TODO: Event.
            return;
        }
    }
}
