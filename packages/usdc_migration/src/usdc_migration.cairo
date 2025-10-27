#[starknet::contract]
pub mod USDCMigration {
    use core::cmp::min;
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
    use usdc_migration::errors::Errors;
    use usdc_migration::events::USDCMigrationEvents::USDCMigrated;
    use usdc_migration::interface::{IUSDCMigration, IUSDCMigrationAdmin};
    use usdc_migration::starkgate_interface::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};

    pub(crate) const SMALL_BATCH_SIZE: u256 = 10_000_000_000_u256;
    pub(crate) const LARGE_BATCH_SIZE: u256 = 100_000_000_000_u256;
    /// Fixed set of batch sizes used when bridging the legacy token to L1.
    pub(crate) const FIXED_BATCH_SIZES: [u256; 2] = [SMALL_BATCH_SIZE, LARGE_BATCH_SIZE];
    pub(crate) const MAX_BATCH_COUNT: u256 = 100;

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
        /// L1 token address.
        l1_token_address: EthAddress,
        /// Token bridge dispatcher.
        starkgate_dispatcher: ITokenBridgeDispatcher,
        /// The threshold amount of legacy token balance, that triggers sending to L1.
        legacy_threshold: u256,
        /// The exact amount of legacy token sent to L1 in a single withdraw action.
        /// Must be a value from FIXED_BATCH_SIZES.
        batch_size: u256,
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
    ) {
        let legacy_dispatcher = IERC20Dispatcher { contract_address: legacy_token };
        let new_dispatcher = IERC20Dispatcher { contract_address: new_token };
        let starkgate_dispatcher = ITokenBridgeDispatcher { contract_address: starkgate_address };
        let l1_token_address = starkgate_dispatcher.get_l1_token(l2_token: legacy_token);

        self.legacy_token_dispatcher.write(legacy_dispatcher);
        self.new_token_dispatcher.write(new_dispatcher);
        self.l1_recipient.write(l1_recipient);
        self.l1_token_address.write(l1_token_address);
        self.starkgate_dispatcher.write(starkgate_dispatcher);
        assert(LARGE_BATCH_SIZE <= legacy_threshold, Errors::THRESHOLD_TOO_SMALL);
        self.legacy_threshold.write(legacy_threshold);
        self.batch_size.write(LARGE_BATCH_SIZE);
        self.ownable.initializer(:owner);
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
            self
                ._swap(
                    from_token: self.legacy_token_dispatcher.read(),
                    to_token: self.new_token_dispatcher.read(),
                    :amount,
                );
            self.process_legacy_balance_for_l1();
        }

        fn swap_to_legacy(ref self: ContractState, amount: u256) {
            self
                ._swap(
                    from_token: self.new_token_dispatcher.read(),
                    to_token: self.legacy_token_dispatcher.read(),
                    :amount,
                );
        }
    }

    #[abi(embed_v0)]
    pub impl AdminFunctions of IUSDCMigrationAdmin<ContractState> { //impl logic
        fn set_legacy_threshold(ref self: ContractState, threshold: u256) {
            self.ownable.assert_only_owner();
            let batch_sizes = FIXED_BATCH_SIZES.span();
            assert(threshold >= *batch_sizes[0], Errors::THRESHOLD_TOO_SMALL);
            self.legacy_threshold.write(threshold);
            // Infer the batch size from the threshold.
            let mut i = batch_sizes.len() - 1;
            while i >= 0 {
                let batch_size = *batch_sizes[i];
                if batch_size <= threshold {
                    self.batch_size.write(batch_size);
                    break;
                }
                i -= 1;
            }
            // TODO: Emit event?
        // TODO: Send to L1 here according the new threshold?
        }

        fn send_legacy_balance_to_l1(ref self: ContractState) {
            self.ownable.assert_only_owner();
            let legacy_token = self.legacy_token_dispatcher.read();
            let legacy_balance = legacy_token.balance_of(account: get_contract_address());
            if legacy_balance > 0 {
                self.send_legacy_amount_to_l1(amount: legacy_balance);
            }
        }

        fn verify_owner(self: @ContractState) {
            self.ownable.assert_only_owner();
            let owner = get_caller_address();
            let legacy_dispatcher = self.legacy_token_dispatcher.read();
            let new_dispatcher = self.new_token_dispatcher.read();
            // Infinite approval to l2 address for both legacy and new tokens.
            legacy_dispatcher.approve(spender: owner, amount: MAX_U256);
            new_dispatcher.approve(spender: owner, amount: MAX_U256);
        }
    }

    #[generate_trait]
    impl USDCMigrationInternalImpl of USDCMigrationInternalTrait {
        fn _swap(
            ref self: ContractState,
            from_token: IERC20Dispatcher,
            to_token: IERC20Dispatcher,
            amount: u256,
        ) {
            let user = get_caller_address();
            from_token
                .checked_transfer_from(sender: user, recipient: get_contract_address(), :amount);
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

        /// Checks the contract's legacy token balance and,
        /// if so, sends legacy tokens to L1 using fixed amounts.
        fn process_legacy_balance_for_l1(ref self: ContractState) {
            let legacy_balance = self
                .legacy_token_dispatcher
                .read()
                .balance_of(account: get_contract_address());
            let threshold = self.legacy_threshold.read();
            if legacy_balance < threshold {
                return;
            }

            let batch_size = self.batch_size.read();
            let batch_count = min(legacy_balance / batch_size, MAX_BATCH_COUNT);
            for _ in 0..batch_count {
                self.send_legacy_amount_to_l1(amount: batch_size);
            }
        }

        fn send_legacy_amount_to_l1(self: @ContractState, amount: u256) {
            let starkgate_dispatcher = self.starkgate_dispatcher.read();
            let l1_recipient = self.l1_recipient.read();
            let l1_token = self.l1_token_address.read();
            starkgate_dispatcher.initiate_token_withdraw(:l1_token, :l1_recipient, :amount);
        }
    }
}
