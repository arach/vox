import Testing

/// Suites that mutate the process-wide `VOX_HOME` nest here so they run
/// serially with each other, not just within themselves.
@Suite(.serialized)
enum VoxHomeEnvironment {}
