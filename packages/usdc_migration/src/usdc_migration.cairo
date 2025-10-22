#[starknet::contract]
pub mod usdc_migration {
    //use statements
    use usdc_migration::interface::IUSDCMigration;

    #[storage]
    struct Storage { //storage variables
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event { //event variables
    }

    #[constructor]
    fn constructor(ref self: ContractState) { //constructor logic
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationImpl of IUSDCMigration<ContractState> { //impl logic
    }
}
