pub mod USDCMigrationEvents {
    use starknet::ContractAddress;

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct USDCMigrated {
        #[key]
        pub user: ContractAddress,
        #[key]
        pub to_token: ContractAddress,
        pub amount: u256,
    }
}
