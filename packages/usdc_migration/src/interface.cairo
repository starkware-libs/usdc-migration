#[starknet::interface]
pub trait IUSDCMigration<T> {
    /// Exchanges (1:1) `amount` of legacy token for new token.
    /// Precondition: Sufficient allowance of legacy token.
    fn swap_to_new(ref self: T, amount: u256);
}

#[starknet::interface]
pub trait IUSDCMigrationConfig<T> {
    /// Sets the legacy token threshold amount that triggers transferring the legacy token to the L1
    /// recipient.
    /// Caller must be the owner.
    fn set_legacy_threshold(ref self: T, threshold: u256);
}
