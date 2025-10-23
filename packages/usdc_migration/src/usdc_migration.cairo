#[starknet::contract]
pub mod USDCMigration {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::storage::StoragePointerWriteAccess;
    use starknet::{ClassHash, ContractAddress, EthAddress};
    use starkware_utils::constants::MAX_U256;
    use usdc_migration::errors::Errors;
    use usdc_migration::interface::{IUSDCMigration, IUSDCMigrationConfig};

    /// Fixed set of transfer units used when bridging the legacy token to L1.
    pub(crate) const FIXED_TRANSFER_UNITS: [u256; 2] = [10_000_000_000_u256, 100_000_000_000_u256];

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
        /// Token bridge address.
        starkgate_address: ContractAddress,
        /// The threshold amount of legacy token balance, that triggers sending to L1.
        legacy_threshold: u256,
        /// The exact amount of legacy token sent to L1 in a single withdraw action.
        /// Must be a value from FIXED_TRANSFER_UNITS.
        transfer_unit: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnableEvent: OwnableComponent::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[constructor]
    pub(crate) fn constructor(
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
        self.legacy_token_dispatcher.write(legacy_dispatcher);
        self.new_token_dispatcher.write(new_dispatcher);
        self.l1_recipient.write(l1_recipient);
        self.starkgate_address.write(starkgate_address);
        let mut transfer_units = FIXED_TRANSFER_UNITS.span();
        let last_transfer_unit = *transfer_units.pop_back().unwrap();
        assert(last_transfer_unit <= legacy_threshold, Errors::THRESHOLD_TOO_SMALL);
        self.legacy_threshold.write(legacy_threshold);
        self.transfer_unit.write(last_transfer_unit);
        self.ownable.initializer(:owner);
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
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationConfigImpl of IUSDCMigrationConfig<ContractState> { //impl logic
        fn set_legacy_threshold(ref self: ContractState, threshold: u256) {
            self.ownable.assert_only_owner();
            let transfer_units = FIXED_TRANSFER_UNITS.span();
            assert(threshold >= *transfer_units[0], Errors::THRESHOLD_TOO_SMALL);
            self.legacy_threshold.write(threshold);
            // Infer the transfer unit from the threshold.
            let mut i = transfer_units.len() - 1;
            while i >= 0 {
                let transfer_unit = *transfer_units[i];
                if transfer_unit <= threshold {
                    self.transfer_unit.write(transfer_unit);
                    break;
                }
                i -= 1;
            }
            // TODO: Emit event?
        // TODO: Send to L1 here according the new threshold?
        }
    }
}
