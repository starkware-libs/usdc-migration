pub mod TokenMigrationEvents {
    use starknet::{ContractAddress, EthAddress};

    /// Emitted when a swap succeeds using `swap_to_legacy` or `swap_to_new`.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct TokenMigrated {
        #[key]
        pub user: ContractAddress,
        #[key]
        pub from_token: ContractAddress,
        #[key]
        pub to_token: ContractAddress,
        pub amount: u256,
    }

    /// Emitted when the L1 recipient is successfully verified using `verify_l1_recipient`.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct L1RecipientVerified {
        pub l1_recipient: EthAddress,
    }

    /// Emitted when the token supplier is updated using `set_token_supplier`.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct TokenSupplierSet {
        pub token_supplier: ContractAddress,
    }

    /// Emitted when the legacy buffer is updated using `set_legacy_buffer`.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct LegacyBufferSet {
        pub old_buffer: u256,
        pub new_buffer: u256,
    }

    /// Emitted when the batch size is updated using `set_batch_size`.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct BatchSizeSet {
        pub old_batch_size: u256,
        pub new_batch_size: u256,
    }

    /// Emitted when sending the legacy to L1 fails. This may happen after a successful swap to the
    /// new token, or after updating the legacy buffer or batch size.
    /// Note: The overall operation does not revert.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct SendToL1Failed {
        pub error: felt252,
    }
}
