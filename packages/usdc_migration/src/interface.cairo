#[starknet::interface]
pub trait IUSDCMigration<T> { //interface
}

#[starknet::interface]
pub trait IUSDCMigrationConfig<T> {
    /// Sets the legacy token threshold amount that triggers transferring the legacy token to the L1
    /// recipient.
    /// Caller must be the owner.
    fn set_legacy_threshold(ref self: T, threshold: u256);
}
