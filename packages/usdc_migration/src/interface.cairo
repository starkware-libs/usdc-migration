#[starknet::interface]
pub trait IUSDCMigration<T> {
    /// Migrate `amount` of USDC.e to USDC.
    /// Caller is expected to have approved the contract to spend `amount` of USDC.e.
    fn migrate(ref self: T, amount: u256);
    fn recycle(ref self: T);
}
