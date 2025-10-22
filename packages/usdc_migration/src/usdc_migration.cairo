#[starknet::contract]
pub mod USDCMigration {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::storage::StoragePointerWriteAccess;
    use starknet::{ClassHash, ContractAddress, EthAddress};
    use starkware_utils::constants::MAX_U256;
    use usdc_migration::interface::IUSDCMigration;

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
        // TODO: Consider change to dispatcher.
        legacy_token: ContractAddress,
        /// The new token swapping the legacy one.
        // TODO: Consider change to dispatcher.
        native_token: ContractAddress,
        /// Ethereum address to which the legacy token is bridged.
        l1_recipient: EthAddress,
        /// The owner of the contract. This L2 address gets the remaining USDC.
        // TODO: Remove? This address is defined as the owner of the contract in the Ownable
        // component.
        owner_l2_address: ContractAddress,
        /// Token bridge address.
        starkgate_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnableEvent: OwnableComponent::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
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
        self.ownable.initializer(owner: owner_l2_address);
        // Infinite approval to l2 address for both legacy and native tokens.
        let legacy_dispacther = IERC20Dispatcher { contract_address: legacy_token };
        let native_dispacther = IERC20Dispatcher { contract_address: native_token };
        legacy_dispacther.approve(spender: owner_l2_address, amount: MAX_U256);
        native_dispacther.approve(spender: owner_l2_address, amount: MAX_U256);
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
}
