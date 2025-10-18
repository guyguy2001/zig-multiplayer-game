const engine = @import("engine.zig");
const std = @import("std");
const utils = @import("utils.zig");
const game_net = @import("game_net.zig");
const posix = std.posix;

const PlayerList = struct {
    list: [3]?engine.Input,

    pub fn isFull(self: *@This()) bool {
        var i: usize = 1;
        while (i < 3) : (i += 1) {
            if (self.list[i] == null) {
                std.debug.print("{} is false\n", .{i});
                return false;
            }
        }
        return true;
    }

    pub fn empty() PlayerList {
        return PlayerList{
            .list = [_]?engine.Input{null} ** 3,
        };
    }
};

/// Holds the inputs of the players from every as-of-yet unstimulated frame.
pub const InputBuffer = struct {
    list: utils.MockCyclicBuffer(PlayerList, PlayerList.empty()),

    pub fn onInputReceived(self: *@This(), message: game_net.InputMessage) !void {
        std.debug.print("Received player {} frame {}\n", .{ message.client_id.value, message.frame_number });
        var list = self.list.at(message.frame_number) catch |err| {
            std.debug.print("Failure at `at` - {}\n", .{err});
            return;
        };
        list.list[message.client_id.value] = message.input;
        var frame_number: i64 = self.list.first_frame;
        if (frame_number == message.frame_number) {
            while (frame_number < self.list.first_frame + self.list.len) : (frame_number += 1) {
                std.debug.print("Checking framer {d}: \n", .{frame_number});
                if (self.list.at(frame_number)) |entry| {
                    if (entry.isFull()) {
                        try self.list.dropFrame(frame_number);
                        std.debug.print("Dropping frame {d}\n", .{frame_number});
                        // TODO: simulate the frame, send message to all clients with result.
                    } else {
                        break;
                    }
                } else |_| unreachable;
            }
        }
    }

    pub fn init(gpa: std.mem.Allocator) InputBuffer {
        return InputBuffer{
            .list = .init(gpa),
        };
    }
};
