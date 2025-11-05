pub mod TokenMigrationEvents {
    use starknet::{ContractAddress, EthAddress};

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

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct L1RecipientVerified {
        pub l1_recipient: EthAddress,
    }

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct LegacyBufferSet {
        pub old_buffer: u256,
        pub new_buffer: u256,
    }

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct BatchSizeSet {
        pub old_batch_size: u256,
        pub new_batch_size: u256,
    }
}
