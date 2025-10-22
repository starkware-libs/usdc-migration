#[starknet::contract]
pub mod USDCMigration {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::StoragePointerWriteAccess;
    use starkware_utils::constants::MAX_U256;
    use usdc_migration::interface::IUSDCMigration;

    #[storage]
    struct Storage {
        /// Deprecated USDC.e token address.
        usdc_e_token: ContractAddress,
        /// New USDC token address.
        usdc_token: ContractAddress,
        /// Address in L1 that gets the USDC.e.
        owner_l1_address: ContractAddress,
        /// Address in L2 that gets the remaining USDC.
        owner_l2_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event { //event variables
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        usdc_e_token: ContractAddress,
        usdc_token: ContractAddress,
        owner_l1_address: ContractAddress,
        owner_l2_address: ContractAddress,
    ) {
        self.usdc_e_token.write(usdc_e_token);
        self.usdc_token.write(usdc_token);
        self.owner_l1_address.write(owner_l1_address);
        self.owner_l2_address.write(owner_l2_address);
        // Infinite approval to l2 address for both USDC.e and USDC.
        let usdc_e_dispacther = IERC20Dispatcher { contract_address: usdc_e_token };
        let usdc_dispacther = IERC20Dispatcher { contract_address: usdc_token };
        usdc_e_dispacther.approve(spender: owner_l2_address, amount: MAX_U256);
        usdc_dispacther.approve(spender: owner_l2_address, amount: MAX_U256);
    }

    #[abi(embed_v0)]
    pub impl USDCMigrationImpl of IUSDCMigration<ContractState> { //impl logic
    }
}
