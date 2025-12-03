const engine = @import("engine.zig");
pub const main_file = @import("main.zig");
const utils = @import("utils.zig");

// This is the main file of the game as a "library" - i.e. when imported as "zig_multiplayer_game",
// currently only in src/net/protocol.zig.
// The only types exported here are those shared with the network library.
pub const Input = engine.Input;
pub const EntityDiff = engine.EntityDiff;
pub const FrameNumber = utils.FrameNumber;

pub const main = main_file.main;
