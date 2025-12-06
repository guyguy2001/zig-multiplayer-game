const std = @import("std");
const posix = std.posix;

const game = @import("game");
const lib = @import("lib");
const engine = game.engine;
const simulation = game.simulation;

const client = @import("client.zig");
const consts = @import("consts.zig");
const protocol = @import("protocol.zig");
const server = @import("server.zig");
const root = @import("root.zig");

pub fn hasMessageWaiting(socket: posix.socket_t) !bool {
    var fds = [_]posix.pollfd{.{
        .fd = socket,
        .events = posix.POLL.IN,
        .revents = 0,
    }};
    return try posix.poll(&fds, 0) > 0;
}

pub fn sendMessageToServer(
    sock: posix.socket_t,
    address: posix.sockaddr,
    message: *const protocol.ClientToServerMessage,
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
    message: *const protocol.ServerToClientMessage,
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
        std.log.err("Received too small of a message\n", .{});
        return error.InvalidMessage;
    }
    // Roundabout way of making sure the `type` enum value is valid.
    _ = std.enums.fromInt(@TypeOf(message.type), @intFromEnum(message.type)) orelse {
        std.log.err("Received invalid message type: {}\n", .{message.type});
        return error.InvalidMessage;
    };
    if (len != message.sizeOf()) {
        std.log.err("Message has incorrect size - expected {}, found {} (for message type {})\n", .{
            message.sizeOf(),
            len,
            message.type,
        });
        return error.InvalidMessage;
    }
    return .{ address, message };
}

pub fn clientReceiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, protocol.ServerToClientMessage } {
    return receiveMessage(protocol.ServerToClientMessage, sock);
}

pub fn serverReceiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, protocol.ClientToServerMessage } {
    return receiveMessage(protocol.ClientToServerMessage, sock);
}

fn tryConnectInLoop(socket: posix.socket_t, target_address: std.net.Address, client_id: root.ClientId) !?protocol.ConnectionAckMessage {
    for (0..consts.max_connection_attempts) |_| {
        try sendMessageToServer(
            socket,
            target_address.any,
            &protocol.ClientToServerMessage{
                .type = .connection,
                .message = .{ .connection = protocol.ConnectionMessage{
                    .client_id = client_id,
                } },
            },
        );

        _, const message = clientReceiveMessage(socket) catch |e| {
            if (e == error.TimeoutConnectionTimedOut or e == error.ConnectionResetByPeer) {
                std.Thread.sleep(lib.utils.millisToNanos(250));
                continue;
            }
            return e;
        };

        if (message.type != .connection_ack) {
            std.log.warn("Got wrong message! {d}\n", .{message.type});
            return null;
        }
        return message.message.connection_ack;
    }
    return error.ConnectionFailedAfterManyAttempts;
}

/// Connect to the server, and initialize the Client struct.
/// Returns a tuple of:
///     The `Server` struct, wrapped in the `NetworkState` union.
///     The current frame on the server.
pub fn connectToServer(id: root.ClientId, gpa: std.mem.Allocator) !struct {
    root.NetworkState,
    lib.FrameNumber,
} {
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(socket);
    try posix.setsockopt(
        socket,
        posix.SOL.SOCKET,
        posix.SO.RCVTIMEO,
        std.mem.asBytes(&consts.default_socket_timeout_ms),
    );

    try posix.connect(socket, &consts.server_address.any, consts.server_address.getOsSockLen());
    const message = try tryConnectInLoop(socket, consts.server_address, id);

    const frame_number = if (message) |msg| msg.frame_number else 0;
    var timeline: simulation.ClientTimeline = .init(gpa);
    std.log.info("First frame {d}\n", .{frame_number});
    timeline.first_frame = frame_number + 1;

    return .{
        root.NetworkState{ .client = client.Client{
            .socket = socket,
            .server_address = consts.server_address.any,
            .id = id,
            .server_snapshots = .init(gpa),
            .timeline = timeline,
        } },
        frame_number,
    };
}

/// Start listening for client connections, and initialize the server struct.
pub fn setupServer(gpa: std.mem.Allocator) !root.NetworkState {
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(sock);
    try posix.setsockopt(
        sock,
        posix.SOL.SOCKET,
        posix.SO.RCVTIMEO,
        std.mem.asBytes(&consts.default_socket_timeout_ms),
    );

    try posix.bind(sock, &consts.server_bind_address.any, consts.server_bind_address.getOsSockLen());

    std.log.info("UDP Server listening on port {d}\n", .{consts.port});

    const input = server.InputBuffer.init(gpa);
    errdefer input.deinit();
    return root.NetworkState{ .server = server.Server{
        .socket = sock,
        .client_addresses = .{null} ** 3,
        .input = input,
    } };
}

pub fn sendInput(c: *const client.Client, input: engine.Input, frame_number: u64) !void {
    // std.log.debug("F{d} sending input\n", .{frame_number});
    try sendMessageToServer(
        c.socket,
        c.server_address,
        &protocol.ClientToServerMessage{
            .type = .input,
            .message = .{ .input = protocol.InputMessage{
                .client_id = c.id,
                .input = input,
                .frame_number = frame_number,
            } },
        },
    );
}

fn sendToAllClients(s: *const server.Server, message: *const protocol.ServerToClientMessage) !void {
    for (s.client_addresses) |c| {
        if (c) |address| {
            try sendMessageToClient(s.socket, address, message);
        }
    }
}

pub fn sendSnapshots(s: *const server.Server, world: *engine.World) !void {
    var iter = world.entities.iter();
    // std.log.debug("Sending frame {}\n", .{world.time.frame_number});
    while (iter.next()) |entity| {
        if (entity.network != null and
            (@mod(world.time.frame_number, 20) == 0 or // Periodically send positions in case of PL
                // Otherwise, only change modified entities
                world.entities.modified_this_frame[entity.id.index]))
        {
            try sendToAllClients(s, &protocol.ServerToClientMessage{
                .type = .snapshot_part,
                .message = .{ .snapshot_part = protocol.SnapshotPartMessage{
                    .entity_diff = entity.make_diff(),
                    .frame_number = world.time.frame_number,
                } },
            });
        }
    }
    try sendToAllClients(s, &protocol.ServerToClientMessage{
        .type = .finished_sending_snapshots,
        .message = .{ .finished_sending_snapshots = protocol.FinishedSendingSnapshotsMessage{
            .frame_number = world.time.frame_number,
        } },
    });
    // std.log.debug("Sent snapshots for frame {}\n", .{world.time.frame_number});
}
