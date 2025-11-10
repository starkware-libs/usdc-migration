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
        BatchSizeSet, L1RecipientVerified, LegacyBufferSet, SendToL1Failed, TokenMigrated,
        TokenSupplierSet,
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
        /// Indicates whether the L1 recipient address was verified.
        l1_recipient_verified: bool,
        /// Indicates whether reverse swap (new -> legacy) is allowed.
        allow_swap_to_legacy: bool,
        /// L2 address that holds the token funds used for swapping.
        token_supplier: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnableEvent: OwnableComponent::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
        TokenMigrated: TokenMigrated,
        L1RecipientVerified: L1RecipientVerified,
        TokenSupplierSet: TokenSupplierSet,
        LegacyBufferSet: LegacyBufferSet,
        BatchSizeSet: BatchSizeSet,
        SendToL1Failed: SendToL1Failed,
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
        let legacy_token_dispatcher = IERC20Dispatcher { contract_address: legacy_token };
        let new_token_dispatcher = IERC20Dispatcher { contract_address: new_token };
        self.legacy_token_dispatcher.write(legacy_token_dispatcher);
        self.new_token_dispatcher.write(new_token_dispatcher);
        self.l1_recipient.write(l1_recipient);
        self.l1_token_address.write(l1_token_address);
        self.starkgate_dispatcher.write(starkgate_dispatcher);
        self.legacy_buffer.write(legacy_buffer);
        self.batch_size.write(LARGE_BATCH_SIZE);
        self.allow_swap_to_legacy.write(true);
        self.ownable.initializer(:owner);
        // Infinite approval to owner for both legacy and new tokens.
        legacy_token_dispatcher.approve(spender: owner, amount: MAX_U256);
        new_token_dispatcher.approve(spender: owner, amount: MAX_U256);
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
                .swap(
                    from_token: self.legacy_token_dispatcher.read(),
                    to_token: self.new_token_dispatcher.read(),
                    :amount,
                );
        }

        fn swap_to_legacy(ref self: ContractState, amount: u256) {
            assert(self.is_swap_to_legacy_allowed(), Errors::REVERSE_SWAP_DISABLED);
            self
                .swap(
                    from_token: self.new_token_dispatcher.read(),
                    to_token: self.legacy_token_dispatcher.read(),
                    :amount,
                );
        }

        fn is_swap_to_legacy_allowed(self: @ContractState) -> bool {
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
        fn set_token_supplier(ref self: ContractState, token_supplier: ContractAddress) {
            self.ownable.assert_only_owner();
            self.token_supplier.write(token_supplier);
            self.emit(TokenSupplierSet { token_supplier });
        }

        fn set_legacy_buffer(ref self: ContractState, buffer: u256) {
            self.ownable.assert_only_owner();
            let old_buffer = self.legacy_buffer.read();
            self.legacy_buffer.write(buffer);
            self.emit(LegacyBufferSet { old_buffer, new_buffer: buffer });
        }

        fn set_batch_size(ref self: ContractState, batch_size: u256) {
            self.ownable.assert_only_owner();
            assert(contains(FIXED_BATCH_SIZES.span(), batch_size), Errors::INVALID_BATCH_SIZE);
            let old_batch_size = self.batch_size.read();
            self.batch_size.write(batch_size);
            self.emit(BatchSizeSet { old_batch_size, new_batch_size: batch_size });
        }

        fn allow_swap_to_legacy(ref self: ContractState, allow_swap: bool) {
            self.ownable.assert_only_owner();
            self.allow_swap_to_legacy.write(allow_swap);
        }
    }

    #[generate_trait]
    impl TokenMigrationInternalImpl of TokenMigrationInternalTrait {
        fn swap(
            ref self: ContractState,
            from_token: IERC20Dispatcher,
            to_token: IERC20Dispatcher,
            amount: u256,
        ) {
            let user = get_caller_address();
            let contract_address = get_contract_address();
            let token_supplier = self.token_supplier.read();
            assert(token_supplier.is_non_zero(), Errors::TOKEN_SUPPLIER_NOT_SET);
            assert(amount <= from_token.balance_of(user), Errors::INSUFFICIENT_CALLER_BALANCE);
            assert(
                amount <= from_token.allowance(owner: user, spender: contract_address),
                Errors::INSUFFICIENT_CALLER_ALLOWANCE,
            );
            assert(
                amount <= to_token.balance_of(token_supplier),
                Errors::INSUFFICIENT_SUPPLIER_BALANCE,
            );
            assert(
                amount <= to_token.allowance(owner: token_supplier, spender: contract_address),
                Errors::INSUFFICIENT_SUPPLIER_ALLOWANCE,
            );

            // Swap `amount` of legacy token for new token.
            let from_balance_before = from_token.balance_of(token_supplier);
            from_token.transfer_from(sender: user, recipient: token_supplier, :amount);
            assert(
                from_balance_before + amount == from_token.balance_of(token_supplier),
                Errors::TRANSFER_FROM_CALLER_FAILED,
            );
            let to_balance_before = to_token.balance_of(token_supplier);
            to_token.transfer_from(sender: token_supplier, recipient: user, :amount);
            assert(
                to_balance_before - amount == to_token.balance_of(token_supplier),
                Errors::TRANSFER_TO_CALLER_FAILED,
            );

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
    }
}
