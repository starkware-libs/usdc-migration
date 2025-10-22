#[starknet::interface]
pub trait IUSDCMigration<T> {
    /// Swaps `amount` of legacy token for new token.
    /// Precondition: Caller has approved the contract to spend `amount` of legacy token.
    fn swap_to_new(ref self: T, amount: u256);
    /// Sends legacy tokens to L1 in batches of `l1_transfer_unit`.
    fn send_to_l1(ref self: T);
}

#[starknet::interface]
pub trait IUSDCMigrationConfig<T> {
    /// Sets the legacy token threshold amount that triggers transferring the legacy token to the L1
    /// recipient.
    /// Caller must be the owner.
    fn set_legacy_threshold(ref self: T, threshold: u256);
}
