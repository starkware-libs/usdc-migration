use starknet::EthAddress;

#[starknet::interface]
pub(crate) trait ITokenBridge<TContractState> {
    fn initiate_token_withdraw(
        ref self: TContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256,
    );
}
