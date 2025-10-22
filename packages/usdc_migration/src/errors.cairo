use starkware_utils::errors::{Describable, ErrorDisplay};
#[derive(Drop)]
pub(crate) enum Error {
    VERIFY_L1_FAILED,
    L1_RECIPIENT_NOT_VERIFIED,
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            Error::VERIFY_L1_FAILED => "Verify failed. The caller is not the L1 recipient.",
            Error::L1_RECIPIENT_NOT_VERIFIED => "L1 recipient not verified.",
        }
    }
}

