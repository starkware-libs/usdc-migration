use starknet::{ContractAddress, EthAddress};

#[starknet::interface]
pub(crate) trait ITokenBridge<TContractState> {
    fn get_l1_token(self: @TContractState, l2_token: ContractAddress) -> EthAddress;
    fn initiate_token_withdraw(
        ref self: TContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256,
    );
}
