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
    list: utils.FrameCyclicBuffer(PlayerList, .empty(), true),

    pub fn onInputReceived(self: *@This(), message: game_net.InputMessage) !void {
        // std.debug.print("Received player {} frame {}\n", .{ message.client_id.value, message.frame_number });
        std.debug.print("F{d} P{d} Input received \n", .{ message.frame_number, message.client_id.value });
        var entry = self.list.at(message.frame_number) catch {
            // std.debug.print("Failure at `at` - {}\n", .{err});
            return;
        };
        entry.list[message.client_id.value] = message.input;
    }

    pub fn isFrameReady(self: *@This(), frame_number: i64) !bool {
        // TODO: frame_number is always first_frame
        // TODO: Create const `at` for when I don't want to modify
        return (try self.list.at(frame_number)).isFull();
    }

    pub fn consumeFrame(self: *@This(), frame_number: i64) !PlayerList {
        if (self.list.first_frame != frame_number) {
            unreachable; // TODO should this even be a parameter?
        }
        const result = (try self.list.at(frame_number)).*;
        const block = self.list.dropFrame(frame_number);
        self.list.freeBlock(block);
        return result;
    }

    pub fn numReadyFrames(self: *@This()) !i64 {
        var result: i64 = 0;
        for (@intCast(self.list.first_frame)..@intCast(self.list.first_frame + self.list.len)) |frame| {
            if (!try self.isFrameReady(@intCast(frame))) {
                break;
            }
            result += 1;
        }
        return result;
    }

    pub fn init(gpa: std.mem.Allocator) InputBuffer {
        return InputBuffer{
            .list = .init(gpa),
        };
    }

    pub fn deinit(self: *@This()) void {
        while (self.list.len > 0) {
            self.list.freeBlock(self.list.dropFrame(self.list.first_frame));
        }
    }
};
