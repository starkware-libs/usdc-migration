use starknet::ContractAddress;

#[starknet::interface]
pub trait ITokenMigration<T> {
    /// Exchanges (1:1) `amount` of legacy token for new token.
    /// Precondition: Sufficient allowance of legacy token.
    fn swap_to_new(ref self: T, amount: u256);
    /// Exchanges (1:1) `amount` of new token for legacy token (reverse swap).
    /// Precondition: Sufficient allowance of new token.
    fn swap_to_legacy(ref self: T, amount: u256);
    /// Returns if reverse swap (new -> legacy) is allowed.
    fn can_swap_to_legacy(self: @T) -> bool;
    /// Returns the legacy token address.
    fn get_legacy_token(self: @T) -> ContractAddress;
    /// Returns the new token address.
    fn get_new_token(self: @T) -> ContractAddress;
}

#[starknet::interface]
pub trait ITokenMigrationAdmin<T> {
    /// Sets the minimum balance of legacy token balance to keep in the supplier.
    /// Caller must be the owner.
    fn set_legacy_buffer(ref self: T, buffer: u256);
    /// Sets the exact amount of legacy token sent to L1 in a single withdraw action.
    /// Caller must be the owner.
    fn set_batch_size(ref self: T, batch_size: u256);
    /// Sends the entire legacy token balance to the L1 recipient.
    /// Caller must be the owner.
    fn send_legacy_balance_to_l1(ref self: T);
    /// Verifies the owner L2 address provided in the constructor is a controlled address.
    /// Caller must be the owner.
    fn verify_owner(ref self: T);
    /// Enable / disable reverse swap (new tokens for legacy tokens).
    /// Caller must be the owner.
    fn allow_swap_to_legacy(ref self: T, allow_swap: bool);
}
