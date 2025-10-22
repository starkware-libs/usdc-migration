#[starknet::contract]
pub mod USDCMigration {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{
        ClassHash, ContractAddress, EthAddress, get_caller_address, get_contract_address,
    };
    use starkware_utils::constants::MAX_U256;
    use starkware_utils::erc20::erc20_utils::CheckedIERC20DispatcherTrait;
    use usdc_migration::events::USDCMigrationEvents::USDCMigrated;
    use usdc_migration::interface::{IUSDCMigration, IUSDCMigrationConfig};
    use usdc_migration::starkgate_interface::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[storage]
    struct Storage {
        /// Ownable component storage.
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        /// Upgradeable component storage.
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        /// The phased out token being swapped for the new one.
        legacy_token_dispatcher: IERC20Dispatcher,
        /// The new token swapping the legacy one.
        new_token_dispatcher: IERC20Dispatcher,
        /// Ethereum address to which the legacy token is bridged.
        l1_recipient: EthAddress,
        /// Address in L2 that gets the remaining USDC.
        owner_l2_address: ContractAddress,
        /// Token bridge dispatcher.
        starkgate_dispatcher: ITokenBridgeDispatcher,
        /// The threshold amount of legacy token balance, that triggers sending to L1.
        legacy_threshold: u256,
        /// Amount of legacy tokens to send to L1 at a time.
        l1_transfer_amount: u256,
        /// L1 USDC token address.
        l1_token_address: EthAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnableEvent: OwnableComponent::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
        USDCMigrated: USDCMigrated,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        legacy_token: ContractAddress,
        new_token: ContractAddress,
        l1_recipient: EthAddress,
        owner: ContractAddress,
        starkgate_address: ContractAddress,
        legacy_threshold: u256,
        l1_token_address: EthAddress,
    ) {
        let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token };
        let new_dispatcher = IERC20Dispatcher { contract_address: new_token };
        let starkgate_dispatcher = ITokenBridgeDispatcher { contract_address: starkgate_address };
        self.legacy_token_dispatcher.write(legacy_dispatcher);
        self.new_token_dispatcher.write(new_dispatcher);
        self.l1_recipient.write(l1_recipient);
        self.starkgate_dispatcher.write(starkgate_dispatcher);
        self.legacy_threshold.write(legacy_threshold);
        self.ownable.initializer(:owner);
        self.l1_token_address.write(l1_token_address);
        // TODO: Change with transfer amount PR.
        self.l1_transfer_amount.write(legacy_threshold);
        // Infinite approval to l2 address for both legacy and new tokens.
        legacy_dispatcher.approve(spender: owner, amount: MAX_U256);
        new_dispatcher.approve(spender: owner, amount: MAX_U256);
    }

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationImpl of IUSDCMigration<ContractState> { //impl logic
        fn swap_to_new(ref self: ContractState, amount: u256) {
            let contract_address = get_contract_address();
            self
                ._swap(
                    :contract_address,
                    from_token: self.legacy_token_dispatcher.read(),
                    to_token: self.new_token_dispatcher.read(),
                    :amount,
                );
            // TODO: send to l1 if threshold is reached.
        }

        fn send_to_l1(ref self: ContractState) {
            let contract_address = get_contract_address();
            self._send_to_l1(:contract_address);
        }
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationConfigImpl of IUSDCMigrationConfig<ContractState> { //impl logic
        fn set_legacy_threshold(ref self: ContractState, threshold: u256) {
            self.ownable.assert_only_owner();
            // TODO: Assert the given threshold is valid according to the fixed transfer units.
            // TODO: Allow threshold zero?
            self.legacy_threshold.write(threshold);
            // TODO: Update transfer unit accordingly.
        // TODO: Emit event?
        // TODO: Send to L1 here according the new threshold?
        }
    }

    #[generate_trait]
    impl InternalUSDCMigration of InternalUSDCMigrationTrait {
        fn _swap(
            ref self: ContractState,
            contract_address: ContractAddress,
            from_token: IERC20Dispatcher,
            to_token: IERC20Dispatcher,
            amount: u256,
        ) {
            let user = get_caller_address();
            from_token.checked_transfer_from(sender: user, recipient: contract_address, :amount);
            to_token.checked_transfer(recipient: user, :amount);

            self
                .emit(
                    USDCMigrated {
                        user,
                        from_token: from_token.contract_address,
                        to_token: to_token.contract_address,
                        amount,
                    },
                );
        }

        fn _send_to_l1(self: @ContractState, contract_address: ContractAddress) {
            let legacy_balance = self
                .legacy_token_dispatcher
                .read()
                .balance_of(account: contract_address);
            if (legacy_balance >= self.legacy_threshold.read()) {
                self.send_units_to_l1(amount: legacy_balance);
            }
        }

        fn send_units_to_l1(self: @ContractState, mut amount: u256) {
            let starkgate_dispatcher = self.starkgate_dispatcher.read();
            let l1_recipient = self.l1_recipient.read();
            let l1_token = self.l1_token_address.read();
            let l1_transfer_amount = self.l1_transfer_amount.read();
            let threshold = self.legacy_threshold.read();

            while (amount >= threshold) {
                starkgate_dispatcher
                    .initiate_token_withdraw(:l1_token, :l1_recipient, amount: l1_transfer_amount);
                amount -= l1_transfer_amount;
            }
        }
    }
}
