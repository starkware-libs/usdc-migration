use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub enum Error {
    INVALID_LEGACY_THRESHOLD,
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            Error::INVALID_LEGACY_THRESHOLD => "Invalid legacy threshold",
        }
    }
}
