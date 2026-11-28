/// App-wide limits. The create_post SQL function checks the same numbers,
/// so change them in both places.
const int kMaxPhotosPerItem = 5;
const int kMaxItemsPerPost = 5;

/// Wanted entries per post. Each entry is a single item or a bundle.
const int kMaxWantsPerPost = 5;

/// Items inside one wanted bundle.
const int kMaxItemsPerWantBundle = 5;

const int kMaxWantLength = 60;