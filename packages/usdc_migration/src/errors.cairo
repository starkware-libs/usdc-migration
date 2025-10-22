use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub enum USDCMigrationError {
    INSUFFICIENT_USDC_BALANCE,
}

impl DescribableUSDCMigrationError of Describable<USDCMigrationError> {
    fn describe(self: @USDCMigrationError) -> ByteArray {
        match self {
            USDCMigrationError::INSUFFICIENT_USDC_BALANCE => "Insufficient USDC balance",
        }
    }
}
