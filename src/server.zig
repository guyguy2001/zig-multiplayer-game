const engine = @import("engine.zig");
const std = @import("std");
const utils = @import("utils.zig");
const game_net = @import("game_net.zig");
const posix = std.posix;

/// Holds the inputs of the players from every as-of-yet unstimulated frame.
const InputBuffer = struct {
    // TODO: Maybe do `PlayerList(engine.Input)` instead of [3]engine.Input?
    list: utils.Queue([3]?engine.Input),

    pub fn onInputReceived(self: *@This(), message: game_net.InputMessage) !void {
        self.list.enqueue(message.input);
    }
};
