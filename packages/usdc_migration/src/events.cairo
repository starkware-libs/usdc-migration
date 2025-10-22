pub mod USDCMigrationEvents {
    use starknet::ContractAddress;

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct USDCMigratedEvent {
        pub amount: u256,
        pub user: ContractAddress,
    }
}
