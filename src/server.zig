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
                std.debug.print("null in entry {d}\n", .{i});
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
    list: utils.FrameCyclicBuffer(PlayerList, PlayerList.empty()),

    pub fn onInputReceived(self: *@This(), message: game_net.InputMessage) !void {
        // std.debug.print("Received player {} frame {}\n", .{ message.client_id.value, message.frame_number });
        std.debug.print("F{d} P{d}", .{ message.frame_number, message.client_id.value });
        var entry = self.list.at(message.frame_number) catch {
            // std.debug.print("Failure at `at` - {}\n", .{err});
            return;
        };
        entry.list[message.client_id.value] = message.input;
    }

    pub fn isFrameReady(self: *@This(), frame_number: i64) !bool {
        // TODO: frame_number is always first_frame
        return (try self.list.at(frame_number)).isFull();
    }

    pub fn consumeFrame(self: *@This(), frame_number: i64) !PlayerList {
        if (self.list.first_frame != frame_number) {
            unreachable; // TODO should this even be a parameter?
        }
        const result = (try self.list.at(frame_number)).*;
        try self.list.dropFrame(frame_number);
        return result;
    }

    pub fn init(gpa: std.mem.Allocator) InputBuffer {
        return InputBuffer{
            .list = .init(gpa),
        };
    }
};
