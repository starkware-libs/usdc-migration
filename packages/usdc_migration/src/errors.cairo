use starkware_utils::errors::{Describable, ErrorDisplay};
#[derive(Drop)]
pub(crate) enum Error {
    VERIFY_L2_FAILED,
    VERIFY_L1_FAILED,
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            Error::VERIFY_L2_FAILED => "Verify failed. The caller is not the owner.",
            Error::VERIFY_L1_FAILED => "Verify failed. The caller is not the L1 recipient.",
        }
    }
}

