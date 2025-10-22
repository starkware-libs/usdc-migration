pub mod USDCMigrationEvents {
    use starknet::{ContractAddress, EthAddress};

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

    // TODO: Module for admin events?
    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct L1RecipientVerified {
        #[key]
        pub l1_recipient: EthAddress,
    }
}
