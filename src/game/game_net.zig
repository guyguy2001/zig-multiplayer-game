const std = @import("std");
const posix = std.posix;

const lib = @import("lib");
const net = @import("net");

const client = @import("client.zig");
const engine = @import("engine.zig");
const server = @import("server.zig");
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

pub const NetworkState = union(NetworkRole) {
    client: client.Client,
    server: server.Server,

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

pub fn sendMessageToServer(
    sock: posix.socket_t,
    address: posix.sockaddr,
    message: *const net.protocol.ClientToServerMessage,
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

fn receiveMessage(T: type, sock: posix.socket_t) !struct { posix.sockaddr, T } {
    var message: T = undefined;
    var address: posix.sockaddr = undefined;
    var addrlen: posix.socklen_t = @sizeOf(@TypeOf(address));

    const len = try posix.recvfrom(sock, @ptrCast(&message), 0, &address, &addrlen);
    if (len < 2) {
        @panic("Received too small of a message");
    }
    // TODO: add validation that the id is of the enum. Maybe further validations for the payload
    if (len != message.sizeOf()) {
        @panic("Message has incorrect size");
    }
    return .{ address, message };
}

pub fn clientReceiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, net.protocol.ServerToClientMessage } {
    return receiveMessage(net.protocol.ServerToClientMessage, sock);
}

pub fn serverReceiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, net.protocol.ClientToServerMessage } {
    return receiveMessage(net.protocol.ClientToServerMessage, sock);
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

/// Connect to the server, and initialize the Client struct.
pub fn connectToServer(id: ClientId, gpa: std.mem.Allocator) !struct { NetworkState, lib.FrameNumber } {
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
        NetworkState{ .client = client.Client{
            .socket = socket,
            .server_address = server_address.any,
            .id = id,
            .server_snapshots = .init(gpa),
            .timeline = timeline,
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

    const input = server.InputBuffer.init(gpa);
    errdefer input.deinit();
    return NetworkState{ .server = server.Server{
        .socket = sock,
        .client_addresses = .{null} ** 3,
        .input = input,
    } };
}

pub fn sendInput(c: *const client.Client, input: engine.Input, frame_number: u64) !void {
    // std.debug.print("F{d} sending input\n", .{frame_number});
    try sendMessageToServer(
        c.socket,
        c.server_address,
        &net.protocol.ClientToServerMessage{
            .type = .input,
            .message = .{ .input = net.protocol.InputMessage{
                .client_id = c.id,
                .input = input,
                .frame_number = frame_number,
            } },
        },
    );
}

fn sendToAllClients(s: *const server.Server, message: *const net.protocol.ServerToClientMessage) !void {
    for (s.client_addresses) |c| {
        if (c) |address| {
            try sendMessageToClient(s.socket, address, message);
        }
    }
}

pub fn sendSnapshots(s: *const server.Server, world: *engine.World) !void {
    var iter = world.entities.iter();
    // std.debug.print("Sending frame {}\n", .{world.time.frame_number});
    while (iter.next()) |entity| {
        if (entity.network != null and
            (@mod(world.time.frame_number, 20) == 0 or // Periodically send positions in case of PL
                // Otherwise, only change modified entities
                world.entities.modified_this_frame[entity.id.index]))
        {
            try sendToAllClients(s, &net.protocol.ServerToClientMessage{
                .type = .snapshot_part,
                .message = .{ .snapshot_part = net.protocol.SnapshotPartMessage{
                    .entity_diff = entity.make_diff(),
                    .frame_number = world.time.frame_number,
                } },
            });
        }
    }
    try sendToAllClients(s, &net.protocol.ServerToClientMessage{
        .type = .finished_sending_snapshots,
        .message = .{ .finished_sending_snapshots = net.protocol.FinishedSendingSnapshotsMessage{
            .frame_number = world.time.frame_number,
        } },
    });
    // std.debug.print("Sent snapshots for frame {}\n", .{world.time.frame_number});
}
