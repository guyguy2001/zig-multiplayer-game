const engine = @import("engine.zig");
const main_file = @import("main.zig");
const simulation = @import("simulation/root.zig");
const utils = @import("utils.zig");

// This is the main file of the game as a "library" - i.e. when imported as "game",
// currently only in src/net/protocol.zig and in src/main.zig.
// The only types exported here are those shared with the network library.
pub const Input = engine.Input;
pub const EntityDiff = engine.EntityDiff;

pub const main = main_file.main;
