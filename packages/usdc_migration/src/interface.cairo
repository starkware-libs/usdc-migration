#[starknet::interface]
pub trait IUSDCMigration<T> { //interface
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
    fn send_legacy_to_l1(self: @T) -> u256;
    /// Verify the owner L2 address given in the constructor is a reachable address.
    /// Caller must be the owner.
    fn verify_owner(self: @T);
}
