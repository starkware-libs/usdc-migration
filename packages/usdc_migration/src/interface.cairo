#[starknet::interface]
pub trait IUSDCMigration<T> { //interface
}

#[starknet::interface]
pub trait IUSDCMigrationOwner<T> {
    /// Sets the legacy token threshold amount that triggers transferring the legacy token to the L1
    /// recipient.
    /// Caller must be the owner.
    fn set_legacy_threshold(ref self: T, legacy_threshold: u256);
    /// Sends the entire legacy token balance to the L1 recipient.
    /// Returns the amount of legacy tokens sent.
    /// Caller must be the owner.
    fn send_legacy_reminder_to_l1(self: @T) -> u256;
}
