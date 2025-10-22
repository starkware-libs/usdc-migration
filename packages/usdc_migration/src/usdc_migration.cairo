#[starknet::contract]
pub mod USDCMigration {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, EthAddress, get_caller_address, get_contract_address};
    use starkware_utils::constants::MAX_U256;
    use usdc_migration::errors::USDCMigrationError;
    use usdc_migration::events::USDCMigrationEvents;
    use usdc_migration::interface::IUSDCMigration;
    use usdc_migration::starkgate_interface::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};

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
        /// Threshold for recycling.
        threshold: u256,
        /// Amount to send to L1 per recycle.
        l1_transfer_unit: u256,
        /// L1 USDC token address.
        l1_usdc_token_address: EthAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event { //event variables
        USDCMigrated: USDCMigrationEvents::USDCMigratedEvent,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        legacy_token: ContractAddress,
        native_token: ContractAddress,
        l1_recipient: EthAddress,
        owner_l2_address: ContractAddress,
        starkgate_address: ContractAddress,
    ) {
        self.legacy_token.write(legacy_token);
        self.native_token.write(native_token);
        self.l1_recipient.write(l1_recipient);
        self.owner_l2_address.write(owner_l2_address);
        self.starkgate_address.write(starkgate_address);
        // Infinite approval to l2 address for both legacy and native tokens.
        let legacy_dispacther = IERC20Dispatcher { contract_address: legacy_token };
        let native_dispacther = IERC20Dispatcher { contract_address: native_token };
        legacy_dispacther.approve(spender: owner_l2_address, amount: MAX_U256);
        native_dispacther.approve(spender: owner_l2_address, amount: MAX_U256);
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationImpl of IUSDCMigration<ContractState> { //impl logic
        fn migrate(ref self: ContractState, amount: u256) {
            let contract_address = get_contract_address();
            let native_token_dispatcher = IERC20Dispatcher {
                contract_address: self.native_token.read(),
            };
            assert!(
                amount <= native_token_dispatcher.balance_of(account: contract_address),
                "{}",
                USDCMigrationError::INSUFFICIENT_USDC_BALANCE,
            );

            let caller_address = get_caller_address();
            let legacy_token_dispatcher = IERC20Dispatcher {
                contract_address: self.legacy_token.read(),
            };
            legacy_token_dispatcher
                .transfer_from(sender: caller_address, recipient: contract_address, :amount);
            native_token_dispatcher.transfer(recipient: caller_address, :amount);

            self.emit(USDCMigrationEvents::USDCMigratedEvent { amount, user: caller_address });
            self._recycle(:contract_address);
        }

        fn recycle(ref self: ContractState) {
            let contract_address = get_contract_address();
            self._recycle(:contract_address);
        }
    }

    #[generate_trait]
    impl InternalUSDCMigration of InternalUSDCMigrationTrait {
        fn _recycle(self: @ContractState, contract_address: ContractAddress) {
            let legacy_token_dispatcher = IERC20Dispatcher {
                contract_address: self.legacy_token.read(),
            };
            let legacy_balance = legacy_token_dispatcher.balance_of(account: contract_address);
            if (legacy_balance >= self.threshold.read()) {
                self.send_units_to_l1(amount: legacy_balance);
            }
        }

        fn send_units_to_l1(self: @ContractState, mut amount: u256) {
            let starkgate_dispatcher = ITokenBridgeDispatcher {
                contract_address: self.starkgate_address.read(),
            };
            let l1_recipient = self.l1_recipient.read();
            let l1_usdc_token_address = self.l1_usdc_token_address.read();
            let l1_transfer_unit = self.l1_transfer_unit.read();
            let threshold = self.threshold.read();

            while (amount >= threshold) {
                starkgate_dispatcher
                    .initiate_token_withdraw(
                        l1_token: l1_usdc_token_address, :l1_recipient, :amount,
                    );
                amount -= l1_transfer_unit;
            }
        }
    }
}
