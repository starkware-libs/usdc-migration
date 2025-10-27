pub mod USDCMigrationEvents {
    use starknet::ContractAddress;

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct USDCMigrated {
        #[key]
        pub user: ContractAddress,
        #[key]
        pub from_token: ContractAddress,
        #[key]
        pub to_token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct SentToL1 {
        // TODO: Add l1 recipient?
        pub amount: u256,
        pub batch_size: u256,
        pub batch_count: u256,
    }
}
