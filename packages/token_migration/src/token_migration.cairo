#[starknet::contract]
pub mod TokenMigration {
    use core::cmp::min;
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{
        ClassHash, ContractAddress, EthAddress, get_caller_address, get_contract_address,
    };
    use starkware_utils::constants::MAX_U256;
    use starkware_utils::span::contains;
    use token_migration::errors::Errors;
    use token_migration::events::TokenMigrationEvents::{
        BatchSizeSet, L1RecipientVerified, LegacyBufferSet, TokenMigrated,
    };
    use token_migration::interface::{ITokenMigration, ITokenMigrationAdmin};
    use token_migration::starkgate_interface::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};

    pub(crate) const SMALL_BATCH_SIZE: u256 = 10_000_000_000_u256;
    pub(crate) const LARGE_BATCH_SIZE: u256 = 100_000_000_000_u256;
    pub(crate) const XL_BATCH_SIZE: u256 = 1_000_000_000_000_u256;
    /// Fixed set of batch sizes used when bridging the legacy token to L1.
    pub(crate) const FIXED_BATCH_SIZES: [u256; 3] = [
        SMALL_BATCH_SIZE, LARGE_BATCH_SIZE, XL_BATCH_SIZE,
    ];
    /// Maximum number of batches that can be sent to L1 in a single transaction.
    pub(crate) const MAX_BATCH_COUNT: u8 = 100;

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
        /// Bridged token address on L1.
        l1_token_address: EthAddress,
        /// StarkGate L2 bridge, used to bridge the legacy token to L1.
        starkgate_dispatcher: ITokenBridgeDispatcher,
        /// Minimum balance of legacy token balance to keep in the supplier.
        legacy_buffer: u256,
        /// The exact amount of legacy token sent to L1 in a single withdraw action.
        /// Must be a value from FIXED_BATCH_SIZES.
        batch_size: u256,
        /// Indicates if L1 recipient address was verified.
        l1_recipient_verified: bool,
        /// Indicates if reverse swap (new -> legacy) is allowed.
        allow_swap_to_legacy: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnableEvent: OwnableComponent::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
        TokenMigrated: TokenMigrated,
        L1RecipientVerified: L1RecipientVerified,
        LegacyBufferSet: LegacyBufferSet,
        BatchSizeSet: BatchSizeSet,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        legacy_token: ContractAddress,
        new_token: ContractAddress,
        l1_recipient: EthAddress,
        owner: ContractAddress,
        starkgate_address: ContractAddress,
        legacy_buffer: u256,
    ) {
        let starkgate_dispatcher = ITokenBridgeDispatcher { contract_address: starkgate_address };
        let l1_token_address = starkgate_dispatcher.get_l1_token(l2_token: legacy_token);
        assert(l1_token_address.is_non_zero(), Errors::LEGACY_TOKEN_BRIDGE_MISMATCH);

        self.legacy_token_dispatcher.write(IERC20Dispatcher { contract_address: legacy_token });
        self.new_token_dispatcher.write(IERC20Dispatcher { contract_address: new_token });
        self.l1_recipient.write(l1_recipient);
        self.l1_token_address.write(l1_token_address);
        self.starkgate_dispatcher.write(starkgate_dispatcher);
        self.legacy_buffer.write(legacy_buffer);
        self.batch_size.write(LARGE_BATCH_SIZE);
        self.allow_swap_to_legacy.write(true);
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
            self.upgradeable.upgrade(:new_class_hash);
        }
    }

    #[abi(embed_v0)]
    pub impl TokenMigrationImpl of ITokenMigration<ContractState> {
        fn swap_to_new(ref self: ContractState, amount: u256) {
            self
                ._swap(
                    from_token: self.legacy_token_dispatcher.read(),
                    to_token: self.new_token_dispatcher.read(),
                    :amount,
                );
            self.process_legacy_balance();
        }

        fn swap_to_legacy(ref self: ContractState, amount: u256) {
            assert(self.can_swap_to_legacy(), Errors::REVERSE_SWAP_DISABLED);
            self
                ._swap(
                    from_token: self.new_token_dispatcher.read(),
                    to_token: self.legacy_token_dispatcher.read(),
                    :amount,
                );
        }

        fn can_swap_to_legacy(self: @ContractState) -> bool {
            self.allow_swap_to_legacy.read()
        }

        fn get_legacy_token(self: @ContractState) -> ContractAddress {
            self.legacy_token_dispatcher.contract_address.read()
        }

        fn get_new_token(self: @ContractState) -> ContractAddress {
            self.new_token_dispatcher.contract_address.read()
        }
    }

    #[abi(embed_v0)]
    pub impl AdminFunctions of ITokenMigrationAdmin<ContractState> {
        fn set_legacy_buffer(ref self: ContractState, buffer: u256) {
            self.ownable.assert_only_owner();
            let old_buffer = self.legacy_buffer.read();
            self.legacy_buffer.write(buffer);
            self.emit(LegacyBufferSet { old_buffer, new_buffer: buffer });
            // Send the legacy balance to L1 according to the new legacy buffer.
            self.process_legacy_balance();
        }

        fn set_batch_size(ref self: ContractState, batch_size: u256) {
            self.ownable.assert_only_owner();
            assert(contains(FIXED_BATCH_SIZES.span(), batch_size), Errors::INVALID_BATCH_SIZE);
            let old_batch_size = self.batch_size.read();
            self.batch_size.write(batch_size);
            self.emit(BatchSizeSet { old_batch_size, new_batch_size: batch_size });
            // Send the legacy balance to L1 according to the new batch size.
            self.process_legacy_balance();
        }

        fn send_legacy_balance_to_l1(ref self: ContractState) {
            self.ownable.assert_only_owner();
            assert(self.l1_recipient_verified.read(), Errors::L1_RECIPIENT_NOT_VERIFIED);
            let legacy_token = self.legacy_token_dispatcher.read();
            let legacy_balance = legacy_token.balance_of(get_contract_address());
            if legacy_balance > 0 {
                self
                    .send_legacy_amount_to_l1(
                        starkgate_dispatcher: self.starkgate_dispatcher.read(),
                        l1_token: self.l1_token_address.read(),
                        l1_recipient: self.l1_recipient.read(),
                        amount: legacy_balance,
                    );
            }
        }

        fn verify_owner(ref self: ContractState) {
            self.ownable.assert_only_owner();
            // Infinite approval to l2 address for both legacy and new tokens.
            let owner = get_caller_address();
            self.legacy_token_dispatcher.read().approve(spender: owner, amount: MAX_U256);
            self.new_token_dispatcher.read().approve(spender: owner, amount: MAX_U256);
        }

        fn allow_swap_to_legacy(ref self: ContractState, allow_swap: bool) {
            self.ownable.assert_only_owner();
            self.allow_swap_to_legacy.write(allow_swap);
        }
    }

    /// Verify the L1 recipient address provided in the constructor is a controlled address.
    #[l1_handler]
    fn verify_l1_recipient(ref self: ContractState, from_address: felt252) {
        let l1_recipient = self.l1_recipient.read();
        if from_address == l1_recipient.into() {
            self.l1_recipient_verified.write(true);
            self.emit(L1RecipientVerified { l1_recipient });
        }
    }

    #[generate_trait]
    impl TokenMigrationInternalImpl of TokenMigrationInternalTrait {
        fn _swap(
            ref self: ContractState,
            from_token: IERC20Dispatcher,
            to_token: IERC20Dispatcher,
            amount: u256,
        ) {
            let user = get_caller_address();
            let contract_address = get_contract_address();
            assert(amount <= from_token.balance_of(user), Errors::INSUFFICIENT_CALLER_BALANCE);
            assert(
                amount <= from_token.allowance(owner: user, spender: contract_address),
                Errors::INSUFFICIENT_ALLOWANCE,
            );
            assert(
                amount <= to_token.balance_of(contract_address),
                Errors::INSUFFICIENT_CONTRACT_BALANCE,
            );

            let success = from_token
                .transfer_from(sender: user, recipient: contract_address, :amount);
            assert(success, Errors::TRANSFER_FROM_CALLER_FAILED);
            let success = to_token.transfer(recipient: user, :amount);
            assert(success, Errors::TRANSFER_TO_CALLER_FAILED);
            // TODO: Add balance checks here for both tokens to be sure the transfer was successful?

            self
                .emit(
                    TokenMigrated {
                        user,
                        from_token: from_token.contract_address,
                        to_token: to_token.contract_address,
                        amount,
                    },
                );
        }

        /// If there is available legacy token balance in the supplier, send it to L1 using
        /// StarkGate bridge using fixed `batch_size`.
        fn process_legacy_balance(ref self: ContractState) {
            assert(self.l1_recipient_verified.read(), Errors::L1_RECIPIENT_NOT_VERIFIED);
            let legacy_token = self.legacy_token_dispatcher.read();
            let legacy_balance = legacy_token.balance_of(get_contract_address());
            let legacy_buffer = self.legacy_buffer.read();
            let batch_size = self.batch_size.read();
            if legacy_balance < (legacy_buffer + batch_size) {
                return;
            }
            let available_balance = legacy_balance - legacy_buffer;
            let batch_count = min(available_balance / batch_size, MAX_BATCH_COUNT.into());
            let starkgate_dispatcher = self.starkgate_dispatcher.read();
            let l1_token = self.l1_token_address.read();
            let l1_recipient = self.l1_recipient.read();
            for _ in 0..batch_count {
                self
                    .send_legacy_amount_to_l1(
                        :starkgate_dispatcher, :l1_token, :l1_recipient, amount: batch_size,
                    );
            }
        }

        /// Sends `amount` of legacy token to L1 using StarkGate bridge.
        #[inline(always)]
        fn send_legacy_amount_to_l1(
            self: @ContractState,
            starkgate_dispatcher: ITokenBridgeDispatcher,
            l1_token: EthAddress,
            l1_recipient: EthAddress,
            amount: u256,
        ) {
            starkgate_dispatcher.initiate_token_withdraw(:l1_token, :l1_recipient, :amount);
        }
    }
}
