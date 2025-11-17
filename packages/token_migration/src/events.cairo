pub mod TokenMigrationEvents {
    use starknet::{ContractAddress, EthAddress};

    /// Emitted when a token swap sucessfully executed.
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

    /// Emitted upon handling l1-l2 msg verifying L1 recipient address.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct L1RecipientVerified {
        pub l1_recipient: EthAddress,
    }

    /// Emitted on a change in the token supplier address.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct TokenSupplierSet {
        pub token_supplier: ContractAddress,
    }

    /// Emitted on a change in the legacy token buffer level.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct LegacyBufferSet {
        pub old_buffer: u256,
        pub new_buffer: u256,
    }

    /// Emitted on a change in the fixed-size used for legacy token withdrawals to L1.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct BatchSizeSet {
        pub old_batch_size: u256,
        pub new_batch_size: u256,
    }

    /// Emitted when failed to send legacy tokens to L1.
    /// The failure is handled caught without failing the user action.
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct SendToL1Failed {
        pub error: felt252,
    }
}
