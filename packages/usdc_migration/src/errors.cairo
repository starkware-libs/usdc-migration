use starkware_utils::errors::{Describable, ErrorDisplay};
#[derive(Drop)]
pub(crate) enum Error {
    VERIFY_FAILED,
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            Error::VERIFY_FAILED => "Verify failed. The caller is not the owner.",
        }
    }
}

