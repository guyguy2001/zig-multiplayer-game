const std = @import("std");
const posix = std.posix;

const client_struct = @import("client.zig");
const debug = @import("debug.zig");
const engine = @import("engine.zig");
const server_structs = @import("server.zig");
const net = @import("net");
const simulation = @import("simulation/root.zig");
const utils = @import("utils.zig");

pub const ClientId = net.protocol.ClientId;

const port = 12348;
const server_address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);
// We use ms because this is how it's defined in winsock - https://learn.microsoft.com/en-us/windows/win32/api/winsock/nf-winsock-setsockopt
const default_socket_timeout_ms: std.os.windows.DWORD = 2000;
const max_connection_attempts = 3;

pub const NetworkRole = enum {
    client,
    server,
};

pub const Server = struct {
    socket: posix.socket_t,
    client_addresses: [3]?posix.sockaddr,
    // TODO: Is it a good idea for this to also contain gameplay-logic-structs such as these?
    input: server_structs.InputBuffer,

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
                try sendMessageToClient(self.socket, client_address, &net.protocol.ServerToClientMessage{
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
        client_id: ClientId,
        frame_number: utils.FrameNumber,
    ) !void {
        if (client_id.value >= self.client_addresses.len) {
            std.debug.print("Client connected with id {d}, which is out of range!", .{client_id.value});
            return error.ConnectionMessageClientIdOutOfRange;
        }
        std.debug.print("Client {d} connected!\n", .{client_id.value});
        self.client_addresses[client_id.value] = client_address;
        try sendMessageToClient(self.socket, client_address, &net.protocol.ServerToClientMessage{
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

pub const Client = struct {
    id: ClientId,
    socket: posix.socket_t,
    server_address: posix.sockaddr,
    ack_server_frame: utils.FrameNumber = 0,
    snapshot_done_server_frame: utils.FrameNumber = 0,
    simulation_speed_multiplier: f32 = 1,
    server_snapshots: client_struct.SnapshotsBuffer,
    timeline: simulation.ClientTimeline,
    last_frame_nanos: ?i128 = null,
    debug_flags: *debug.DebugFlags,

    pub fn hasMessageWaiting(self: *const @This()) !bool {
        return net.utils.hasMessageWaiting(self.socket);
    }

    pub fn deinit(self: *@This()) void {
        posix.close(self.socket);
        self.server_snapshots.deinit();
        while (self.timeline.len > 0) {
            self.timeline.freeBlock(self.timeline.dropFrame(self.timeline.first_frame));
        }
    }
};

pub const NetworkState = union(NetworkRole) {
    client: Client,
    server: Server,

    pub fn cleanup(self: *@This()) void {
        switch (self.*) {
            .client => |*c| {
                c.deinit();
            },
            .server => |*s| {
                s.deinit();
            },
        }
    }
};

pub fn sendMessageToServer(sock: posix.socket_t, address: posix.sockaddr, message: *const net.protocol.ClientToServerMessage) !void {
    const ptr = @as([]const u8, @ptrCast(message))[0..message.sizeOf()];

    _ = try posix.sendto(
        sock,
        ptr,
        0,
        &address,
        @sizeOf(@TypeOf(address)),
    );
}

pub fn sendMessageToClient(
    sock: posix.socket_t,
    address: posix.sockaddr,
    message: *const net.protocol.ServerToClientMessage,
) !void {
    const ptr = @as([]const u8, @ptrCast(message))[0..message.sizeOf()];

    _ = try posix.sendto(
        sock,
        ptr,
        0,
        &address,
        @sizeOf(@TypeOf(address)),
    );
}

pub fn serverReceiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, net.protocol.ClientToServerMessage } {
    var message: net.protocol.ClientToServerMessage = undefined;
    var address: posix.sockaddr = undefined;
    var addrlen: posix.socklen_t = @sizeOf(@TypeOf(address));

    const len = try posix.recvfrom(sock, @ptrCast(&message), 0, &address, &addrlen);
    if (len < 2) {
        @panic("Received too small of a message");
    }
    if (len != message.sizeOf()) {
        @panic("Message has incorrect size");
    }
    return .{ address, message };
}

pub fn clientReceiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, net.protocol.ServerToClientMessage } {
    var message: net.protocol.ServerToClientMessage = undefined;
    var address: posix.sockaddr = undefined;
    var addrlen: posix.socklen_t = @sizeOf(@TypeOf(address));

    const len = try posix.recvfrom(sock, @ptrCast(&message), 0, &address, &addrlen);
    if (len < 2) {
        @panic("Received too small of a message");
    }
    if (len != message.sizeOf()) {
        @panic("Message has incorrect size");
    }
    return .{ address, message };
}

fn tryConnectInLoop(socket: posix.socket_t, target_address: std.net.Address, client_id: ClientId) !?net.protocol.ConnectionAckMessage {
    for (0..max_connection_attempts) |_| {
        try sendMessageToServer(
            socket,
            target_address.any,
            &net.protocol.ClientToServerMessage{
                .type = .connection,
                .message = .{ .connection = net.protocol.ConnectionMessage{
                    .client_id = client_id,
                } },
            },
        );

        _, const message = clientReceiveMessage(socket) catch |e| {
            if (e == error.Timeout or e == error.ConnectionResetByPeer) {
                std.Thread.sleep(utils.millisToNanos(250));
                continue;
            }
            return e;
        };

        if (message.type != .connection_ack) {
            std.debug.print("W: Got wrong message! {d}\n", .{message.type});
            return null;
        }
        return message.message.connection_ack;
    }
    return error.ConnectionFailedAfterManyAttempts;
}

pub fn connectToServer(id: ClientId, gpa: std.mem.Allocator, debug_flags: *debug.DebugFlags) !struct { NetworkState, utils.FrameNumber } {
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(socket);
    try posix.setsockopt(
        socket,
        posix.SOL.SOCKET,
        posix.SO.RCVTIMEO,
        std.mem.asBytes(&default_socket_timeout_ms),
    );

    try posix.connect(socket, &server_address.any, server_address.getOsSockLen());
    const message = try tryConnectInLoop(socket, server_address, id);

    const frame_number = if (message) |msg| msg.frame_number else 0;
    var timeline: simulation.ClientTimeline = .init(gpa);
    std.debug.print("First frame {d}\n", .{frame_number});
    timeline.first_frame = frame_number + 1;

    return .{
        NetworkState{ .client = Client{
            .socket = socket,
            .server_address = server_address.any,
            .id = id,
            .server_snapshots = .init(gpa),
            .timeline = timeline,
            .debug_flags = debug_flags,
        } },
        frame_number,
    };
}

pub fn setupServer(gpa: std.mem.Allocator) !NetworkState {
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(sock);
    try posix.setsockopt(
        sock,
        posix.SOL.SOCKET,
        posix.SO.RCVTIMEO,
        std.mem.asBytes(&default_socket_timeout_ms),
    );

    try posix.bind(sock, &server_address.any, server_address.getOsSockLen());

    std.debug.print("UDP Server listening on port {d}\n", .{port});

    const input = server_structs.InputBuffer.init(gpa);
    errdefer input.deinit();
    return NetworkState{ .server = Server{
        .socket = sock,
        .client_addresses = .{null} ** 3,
        .input = input,
    } };
}

pub fn sendInput(client: *const Client, input: engine.Input, frame_number: u64) !void {
    // std.debug.print("F{d} sending input\n", .{frame_number});
    if (client.debug_flags.outgoing_pl_percent > 0 and utils.randInt(100) < client.debug_flags.outgoing_pl_percent) {
        std.debug.print("Simulated PL on input :(", .{});
        return;
    }

    try sendMessageToServer(
        client.socket,
        client.server_address,
        &net.protocol.ClientToServerMessage{
            .type = .input,
            .message = .{ .input = net.protocol.InputMessage{
                .client_id = client.id,
                .input = input,
                .frame_number = frame_number,
            } },
        },
    );
}

fn sendToAllClients(server: *const Server, message: *const net.protocol.ServerToClientMessage) !void {
    for (server.client_addresses) |c| {
        if (c) |address| {
            // std.debug.print("P{any} ", .{address});
            try sendMessageToClient(server.socket, address, message);
        }
    }
    // std.debug.print("\n", .{});
}

pub fn sendSnapshots(server: *const Server, world: *engine.World) !void {
    var iter = world.entities.iter();
    // std.debug.print("Sending frame {}\n", .{world.time.frame_number});
    while (iter.next()) |entity| {
        if (entity.network != null and
            (@mod(world.time.frame_number, 20) == 0 or // Periodically send positions in case of PL
                // Otherwise, only change modified entities
                world.entities.modified_this_frame[entity.id.index]))
        {
            try sendToAllClients(server, &net.protocol.ServerToClientMessage{
                .type = .snapshot_part,
                .message = .{ .snapshot_part = net.protocol.SnapshotPartMessage{
                    .entity_diff = entity.make_diff(),
                    .frame_number = world.time.frame_number,
                } },
            });
        }
    }
    try sendToAllClients(server, &net.protocol.ServerToClientMessage{
        .type = .finished_sending_snapshots,
        .message = .{ .finished_sending_snapshots = net.protocol.FinishedSendingSnapshotsMessage{
            .frame_number = world.time.frame_number,
        } },
    });
    // std.debug.print("Sent snapshots for frame {}\n", .{world.time.frame_number});
}
