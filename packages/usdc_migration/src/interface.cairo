#[starknet::interface]
pub trait IUSDCMigration<T> {
    /// Exchange `amount` of legacy token for new token.
    /// Precondition: Caller has approved the contract to spend `amount` of legacy token.
    fn exchange_legacy_for_new(ref self: T, amount: u256);
    fn recycle(ref self: T);
}
