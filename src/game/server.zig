const std = @import("std");
const posix = std.posix;

const lib = @import("lib");
const net = @import("net");

const consts = @import("consts.zig");
const engine = @import("engine.zig");
const game_net = @import("game_net.zig");

pub const Server = struct {
    socket: posix.socket_t,
    client_addresses: [3]?posix.sockaddr,
    // TODO: Is it a good idea for this to also contain gameplay-logic-structs such as these?
    // i.e. should I split it to ServerNetwork and ServerState?
    input: InputBuffer,

    pub fn hasMessageWaiting(self: *const @This()) !bool {
        return net.utils.hasMessageWaiting(self.socket);
    }

    pub fn handleMessage(
        self: *@This(),
        frame_number: u64,
        client_address: posix.sockaddr,
        message: net.protocol.ClientToServerMessage,
    ) !void {
        switch (message.type) {
            .input => {
                const input_message = message.message.input;
                try game_net.sendMessageToClient(self.socket, client_address, &net.protocol.ServerToClientMessage{
                    .type = .input_ack,
                    .message = .{ .input_ack = net.protocol.InputAckMessage{
                        .ack_frame_number = input_message.frame_number,
                        .received_during_frame = frame_number,
                    } },
                });
                try self.input.onInputReceived(input_message);
            },
            .connection => {
                try self.onClientConnected(
                    client_address,
                    message.message.connection.client_id,
                    frame_number,
                );
            },
        }
    }

    pub fn onClientConnected(
        self: *@This(),
        client_address: posix.sockaddr,
        client_id: game_net.ClientId,
        frame_number: lib.FrameNumber,
    ) !void {
        if (client_id.value >= self.client_addresses.len) {
            std.debug.print("Client connected with id {d}, which is out of range!", .{client_id.value});
            return error.ConnectionMessageClientIdOutOfRange;
        }
        std.debug.print("Client {d} connected!\n", .{client_id.value});
        self.client_addresses[client_id.value] = client_address;
        try game_net.sendMessageToClient(self.socket, client_address, &net.protocol.ServerToClientMessage{
            .type = .connection_ack,
            .message = .{ .connection_ack = net.protocol.ConnectionAckMessage{
                .frame_number = frame_number,
            } },
        });
    }

    pub fn deinit(self: *@This()) void {
        posix.close(self.socket);
        self.input.deinit();
    }
};
const PlayersInput = struct {
    list: [3]?engine.Input,

    pub fn isFull(self: *@This()) bool {
        var i: usize = 1;
        while (i < 3) : (i += 1) {
            if (self.list[i] == null) {
                // std.debug.print("null in entry {d}\n", .{i});
                return false;
            }
        }
        return true;
    }

    pub fn empty() PlayersInput {
        return PlayersInput{
            .list = [_]?engine.Input{null} ** 3,
        };
    }
};

/// Holds the inputs of the players from every as-of-yet unstimulated frame.
pub const InputBuffer = struct {
    list: lib.FrameCyclicBuffer(PlayersInput, .empty(), true),
    current_state: [3]engine.Input,
    last_seen: [3]lib.FrameNumber,

    pub fn onInputReceived(self: *@This(), message: net.protocol.InputMessage) !void {
        // std.debug.print("Received player {} frame {}\n", .{ message.client_id.value, message.frame_number });
        std.debug.print("F{d} P{d} Input received \n", .{ message.frame_number, message.client_id.value });
        var entry = self.list.at(message.frame_number) catch {
            // std.debug.print("Failure at `at` - {}\n", .{err});
            return;
        };
        entry.list[message.client_id.value] = message.input;
    }

    pub fn isFrameReady(self: *@This(), frame_number: u64) !bool {
        // TODO: frame_number is always first_frame
        // TODO: Create const `at` for when I don't want to modify
        return (try self.list.at(frame_number)).isFull();
    }

    pub fn consumeFrame(self: *@This(), frame_number: u64) ![3]engine.Input {
        if (self.list.first_frame != frame_number) {
            unreachable; // TODO should this even be a parameter?
        }
        const inputs = (try self.list.at(frame_number)).*;
        const block = self.list.dropFrame(frame_number);
        self.list.freeBlock(block);

        for (1..inputs.list.len) |i| {
            if (inputs.list[i]) |input| {
                self.current_state[i] = input;
                self.last_seen[i] = frame_number;
            } else {
                std.debug.print("E: Client {d} has no input for frame {d}!\n", .{ i, frame_number });
                if (frame_number - self.last_seen[i] > consts.stop_holding_input_threshold) {
                    self.current_state[i] = engine.Input.empty();
                }
            }
        }
        return self.current_state;
    }

    pub fn numReadyFrames(self: *@This()) !u64 {
        var result: u64 = 0;
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
            .current_state = [_]engine.Input{.empty()} ** 3,
            .last_seen = [_]lib.FrameNumber{0} ** 3,
        };
    }

    pub fn deinit(self: *@This()) void {
        while (self.list.len > 0) {
            self.list.freeBlock(self.list.dropFrame(self.list.first_frame));
        }
    }
};
