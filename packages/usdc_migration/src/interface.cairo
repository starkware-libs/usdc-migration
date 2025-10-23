#[starknet::interface]
pub trait IUSDCMigration<T> {
    /// Exchange `amount` of legacy token for new token.
    /// Precondition: Caller has approved the contract to spend `amount` of legacy token.
    fn exchange_legacy_for_new(ref self: T, amount: u256);
}

#[starknet::interface]
pub trait IUSDCMigrationConfig<T> {
    /// Sets the legacy token threshold amount that triggers transferring the legacy token to the L1
    /// recipient.
    /// Caller must be the owner.
    fn set_legacy_threshold(ref self: T, threshold: u256);
}
