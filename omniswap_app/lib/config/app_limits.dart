/// App-wide limits. The create_post SQL function checks the same numbers,
/// so change them in both places.
const int kMaxPhotosPerItem = 5;
const int kMaxItemsPerPost = 5;
const int kMaxWantsPerPost = 5;
const int kMaxWantLength = 60;