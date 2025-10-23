pub mod USDCMigrationEvents {
    use starknet::ContractAddress;

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct USDCMigratedEvent {
        #[key]
        pub user: ContractAddress,
        pub amount: u256,
    }
}
