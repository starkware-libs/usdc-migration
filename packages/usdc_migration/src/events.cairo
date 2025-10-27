pub mod USDCMigrationEvents {
    use starknet::ContractAddress;

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
}
