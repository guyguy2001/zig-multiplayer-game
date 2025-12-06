const std = @import("std");
const posix = std.posix;

const game = @import("game");
const lib = @import("lib");
const engine = game.engine;
const simulation = game.simulation;

const consts = @import("consts.zig");
const protocol = @import("protocol.zig");
const root = @import("root.zig");
const utils = @import("utils.zig");

pub const Client = struct {
    id: root.ClientId,
    socket: posix.socket_t,
    server_address: posix.sockaddr,
    ack_server_frame: lib.FrameNumber = 0,
    snapshot_done_server_frame: lib.FrameNumber = 0,
    simulation_speed_multiplier: f32 = 1,
    server_snapshots: SnapshotsBuffer,
    timeline: simulation.ClientTimeline,
    last_frame_nanos: ?i128 = null,

    pub fn hasMessageWaiting(self: *const @This()) !bool {
        return utils.hasMessageWaiting(self.socket);
    }

    pub fn deinit(self: *@This()) void {
        posix.close(self.socket);
        self.server_snapshots.deinit();
        while (self.timeline.len > 0) {
            self.timeline.freeBlock(self.timeline.dropFrame(self.timeline.first_frame));
        }
    }
};

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
    list: lib.FrameCyclicBuffer(FrameSnapshots, .init(), true),
    gpa: std.mem.Allocator,

    pub fn firstFrame(self: *const @This()) lib.FrameNumber {
        return self.list.first_frame;
    }

    pub fn len(self: *const @This()) u64 {
        return self.list.len;
    }

    pub fn onSnapshotPartReceived(self: *@This(), part: protocol.SnapshotPartMessage) !void {
        // Mark all previous frames as done, even if the "done" message hadn't arrived
        for (self.list.first_frame..part.frame_number) |frame| {
            (try self.list.at(frame)).is_done = true;
        }

        var entry = self.list.at(part.frame_number) catch |err| {
            std.debug.print("client: Failure at `at` - {}\n", .{err});
            // TODO: Why do I even catch here?
            return;
        };
        try entry.snapshots.append(self.gpa, part.entity_diff);
    }

    pub fn onSnapshotDoneReceived(self: *@This(), message: protocol.FinishedSendingSnapshotsMessage) !void {
        var entry = self.list.at(message.frame_number) catch {
            std.debug.print(
                "W: Received too old of a frame ({d}, first is {d})\n",
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

pub fn handleIncomingMessages(c: *Client) !root.HandleIncomingMessagesResult {
    while (try c.hasMessageWaiting()) {
        _, const message = utils.clientReceiveMessage(c.socket) catch |err| {
            switch (err) {
                error.ConnectionResetByPeer, error.ConnectionTimedOut => {
                    std.debug.print("Disconnected by peer!\n", .{});
                    return .quit;
                },
                error.InvalidMessage => continue,
                else => {
                    return err;
                },
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
                c.simulation_speed_multiplier = calculateNeededSimulationSpeed(ack);
                c.ack_server_frame = ack.received_during_frame;
                // std.debug.print("ACK For F{d}, Server frame {d}\n", .{ ack.ack_frame_number, ack.received_during_frame });
            },
            .connection_ack => {
                std.debug.print("W: Received connection ack late into the game", .{});
            },
        }
    }
    return .ok;
}

fn calculateNeededSimulationSpeed(ack: protocol.InputAckMessage) f32 {
    // How many frames the server has
    const actual_server_buffer: i64 = @bitCast(ack.ack_frame_number -% ack.received_during_frame);

    const buffer_error: f32 = @floatFromInt(actual_server_buffer - consts.desired_server_buffer);

    var calculated_multiplier: f32 = 1.0 - (buffer_error * consts.simulation_speed.speedup_intensity);

    // Clamp the result to safe bounds to prevent runaway speeds
    calculated_multiplier = @max(
        @min(calculated_multiplier, consts.simulation_speed.max_speedup),
        consts.simulation_speed.max_slowdown,
    );

    // If the state is relatively good, prefer running at the same speed as the server
    if (@abs(buffer_error) <= 1) {
        return 1.0;
    } else {
        return calculated_multiplier;
    }
}
