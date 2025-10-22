#[starknet::interface]
pub trait IUSDCMigration<T> {
    /// Exchanges (1:1) `amount` of legacy token for new token.
    /// Precondition: Sufficient allowance of legacy token.
    fn swap_to_new(ref self: T, amount: u256);
}

#[starknet::interface]
pub trait IUSDCMigrationAdmin<T> {
    /// Sets the legacy token threshold amount that triggers transferring the legacy token to the L1
    /// recipient.
    /// Caller must be the owner.
    fn set_legacy_threshold(ref self: T, threshold: u256);
    /// Sends the entire legacy token balance to the L1 recipient.
    /// Returns the amount of legacy tokens sent.
    /// Caller must be the owner.
    fn send_legacy_balance_to_l1(self: @T);
    /// Verifies the owner L2 address provided in the constructor is a controlled address.
    /// Caller must be the owner.
    fn verify_owner(self: @T);
}
