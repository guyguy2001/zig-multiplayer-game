const std = @import("std");

const consts = @import("consts.zig");
const engine = @import("engine.zig");
const game_net = @import("game_net.zig");
const utils = @import("utils.zig");

pub const FrameSnapshots = struct {
    // Thoughts:
    // For the input, I'm going to give acks from the server to make sure all of the input data was eventually received.
    // Do I want to do the same for snapshot PLs?
    // I worry that if there's an important update for an entity that only updates once every 10 seconds, that update would drop, and the client wouldn't know anything happened.

    snapshots: std.ArrayList(engine.EntityDiff),
    is_done: bool, // Did we receive the FinishedSending packet

    pub fn init() FrameSnapshots {
        return FrameSnapshots{
            .snapshots = .empty,
            .is_done = false,
        };
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.snapshots.deinit(gpa);
    }
};

pub const SnapshotsBuffer = struct {
    list: utils.FrameCyclicBuffer(FrameSnapshots, .init(), true),
    gpa: std.mem.Allocator,

    pub fn firstFrame(self: *const @This()) utils.FrameNumber {
        return self.list.first_frame;
    }

    pub fn len(self: *const @This()) u64 {
        return self.list.len;
    }

    pub fn onSnapshotPartReceived(self: *@This(), part: game_net.SnapshotPartMessage) !void {
        std.debug.print("F{d} Sp{d} Snapshot part\n", .{ part.frame_number, part.entity_diff.id.index });
        var entry = self.list.at(part.frame_number) catch |err| {
            std.debug.print("client: Failure at `at` - {}\n", .{err});
            // TODO: Why do I even catch here?
            return;
        };
        try entry.snapshots.append(self.gpa, part.entity_diff);
    }

    pub fn onSnapshotDoneReceived(self: *@This(), message: game_net.FinishedSendingSnapshotsMessage) !void {
        var entry = self.list.at(message.frame_number) catch {
            std.debug.print(
                "W: Received too old of a frame ({d}, first is {d})",
                .{ message.frame_number, self.list.first_frame },
            );
            return;
        };
        entry.is_done = true;
    }

    pub fn isFrameReady(self: *@This(), frame_number: u64) !bool {
        // TODO: frame_number is always first_frame
        return (try self.list.at(frame_number)).is_done;
    }

    // This seems like it's shared between this and ther server's
    pub fn consumeFrame(self: *@This(), frame_number: u64) !FrameSnapshots {
        // std.debug.print("F{d} Consume\n", .{frame_number});
        if (self.list.first_frame != frame_number) {
            // TODO should this even be a parameter? evidently yes
            std.debug.print("ERROR: Tried consuming frame {d} while we're still on frame {d}\n", .{ frame_number, self.list.first_frame });
            return error.WrongFrameNumber;
        }
        const block = self.list.dropFrame(frame_number);
        const result = block.data;
        self.list.freeBlock(block);
        return result;
    }

    pub fn init(gpa: std.mem.Allocator) SnapshotsBuffer {
        return SnapshotsBuffer{
            .list = .init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *@This()) void {
        while (self.list.len > 0) {
            const block = self.list.dropFrame(self.list.first_frame);
            block.data.deinit(self.gpa);
            self.list.freeBlock(block);
        }
    }
};

pub const HandleIncomingMessagesResult = enum {
    ok,
    quit,
};

pub fn handleIncomingMessages(c: *game_net.Client, frame_number: utils.FrameNumber, time_per_frame: u64) !HandleIncomingMessagesResult {
    while (try c.hasMessageWaiting()) {
        _, const message = game_net.clientReceiveMessage(c.socket) catch |err| {
            if (err == error.ConnectionResetByPeer or err == error.Timeout) {
                std.debug.print("Disconnected by peer!\n", .{});
                return .quit;
            } else {
                return err;
            }
        };
        switch (message.type) {
            .snapshot_part => {
                try c.server_snapshots.onSnapshotPartReceived(message.message.snapshot_part);
            },
            .finished_sending_snapshots => {
                try c.server_snapshots.onSnapshotDoneReceived(message.message.finished_sending_snapshots);
                c.snapshot_done_server_frame = message.message.finished_sending_snapshots.frame_number;
            },
            .input_ack => {
                const ack = message.message.input_ack;
                const rtt = frame_number - ack.ack_frame_number;

                const actual_server_buffer: i64 = @bitCast(ack.ack_frame_number -% ack.received_during_frame);

                // if (frame_number - @divFloor(rtt, 2) > ack.received_during_frame + 10) {
                if (actual_server_buffer > consts.desired_server_buffer + 1) {
                    // Sleep half a frame each time we notice we're ahead of the server
                    std.Thread.sleep(utils.millisToNanos(time_per_frame / 2));
                }
                if (actual_server_buffer > consts.desired_server_buffer * 2 + 1) {
                    // Starting to get bad
                    std.Thread.sleep(utils.millisToNanos(time_per_frame * 2));
                }

                std.debug.print("rtt is {d}\n", .{rtt});
                std.debug.print("ACK For F{d}, Server frame {d}\n", .{ ack.ack_frame_number, ack.received_during_frame });
                c.ack_server_frame = ack.received_during_frame;
            },
        }
    }
    return .ok;
}
