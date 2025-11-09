use starknet::ContractAddress;

#[starknet::interface]
pub trait ITokenMigration<T> {
    /// Exchanges (1:1) `amount` of legacy token for new token.
    /// Precondition: Sufficient allowance of legacy token.
    fn swap_to_new(ref self: T, amount: u256);
    /// Exchanges (1:1) `amount` of new token for legacy token (reverse swap).
    /// Precondition: Sufficient allowance of new token.
    fn swap_to_legacy(ref self: T, amount: u256);
    /// Indicates whether reverse swapping (new -> legacy) is allowed.
    fn is_swap_to_legacy_allowed(self: @T) -> bool;
    /// Returns the legacy token address.
    fn get_legacy_token(self: @T) -> ContractAddress;
    /// Returns the new token address.
    fn get_new_token(self: @T) -> ContractAddress;
}

#[starknet::interface]
pub trait ITokenMigrationAdmin<T> {
    /// Finalizes the contract initialization process. Swaps will fail before calling this function.
    /// This function may be called later to update the token supplier address.
    /// Precondition: L1 recipient is verified.
    /// Caller must be the owner.
    fn finalize_setup(ref self: T, token_supplier: ContractAddress);
    /// Sets the minimum balance of legacy token balance to keep in the supplier.
    /// Caller must be the owner.
    fn set_legacy_buffer(ref self: T, buffer: u256);
    /// Sets the exact amount of legacy token sent to L1 in a single withdraw action.
    /// Caller must be the owner.
    fn set_batch_size(ref self: T, batch_size: u256);
    /// Enables / disables reverse swap (new tokens for legacy tokens).
    /// Caller must be the owner.
    fn allow_swap_to_legacy(ref self: T, allow_swap: bool);
}
