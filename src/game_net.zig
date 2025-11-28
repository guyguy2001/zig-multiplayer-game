const std = @import("std");
const client_struct = @import("client.zig");
const engine = @import("engine.zig");
const server_structs = @import("server.zig");
const utils = @import("utils.zig");
const posix = std.posix;

const port = 12348;
const server_address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);

pub const ClientId = packed struct {
    value: u8,

    pub fn client_id(value: u8) ClientId {
        return ClientId{ .value = value };
    }
};

pub const ConnectionMessage = packed struct {
    client_id: ClientId,
};

/// A message sent from the client to the server, with the current input state
pub const InputMessage = packed struct {
    frame_number: i64,
    client_id: ClientId,
    input: engine.Input,
};

pub const SnapshotPartMessage = packed struct {
    frame_number: i64,
    entity_diff: engine.EntityDiff,
};

pub const FinishedSendingSnapshotsMessage = packed struct {
    frame_number: i64,
};

pub const ClientToServerMessageType = enum(u8) {
    connection = 5,
    input = 6,
};

pub const ClientToServerMessage = packed struct {
    type: ClientToServerMessageType,
    message: packed union {
        connection: ConnectionMessage,
        input: InputMessage,
    },

    pub fn sizeOf(self: *const @This()) usize {
        const prefix_size = @bitSizeOf(@TypeOf(self.type));
        const payload_size: usize = switch (self.type) {
            .connection => @bitSizeOf(ConnectionMessage),
            .input => @bitSizeOf(InputMessage),
        };
        return (prefix_size + payload_size + 7) / 8;
    }
};

pub const ServerToClientMessageType = enum(u8) {
    snapshot_part = 17,
    finished_sending_snapshots = 18,
};

pub const ServerToClientMessage = packed struct {
    type: ServerToClientMessageType,
    message: packed union {
        snapshot_part: SnapshotPartMessage,
        finished_sending_snapshots: FinishedSendingSnapshotsMessage,
    },

    pub fn sizeOf(self: *const @This()) usize {
        const prefix_size = @bitSizeOf(@TypeOf(self.type));
        const payload_size: usize = switch (self.type) {
            .snapshot_part => @bitSizeOf(SnapshotPartMessage),
            .finished_sending_snapshots => @bitSizeOf(FinishedSendingSnapshotsMessage),
        };
        return (prefix_size + payload_size + 7) / 8;
    }
};

pub fn _hasMessageWaiting(socket: posix.socket_t) !bool {
    var fds = [_]posix.pollfd{.{
        .fd = socket,
        .events = posix.POLL.IN,
        .revents = 0,
    }};
    return try posix.poll(&fds, 0) > 0;
}

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
        return _hasMessageWaiting(self.socket);
    }

    pub fn onClientConnected(
        self: *@This(),
        client_address: posix.sockaddr,
        client_id: ClientId,
    ) !void {
        if (client_id.value >= self.client_addresses.len) {
            std.debug.print("Client connected with id {d}, which is out of range!", .{client_id.value});
            return error.ConnectionMessageClientIdOutOfRange;
        }
        std.debug.print("Client {d} connected!\n", .{client_id.value});
        self.client_addresses[client_id.value] = client_address;
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
    server_snapshots: client_struct.SnapshotsBuffer,

    pub fn hasMessageWaiting(self: *const @This()) !bool {
        return _hasMessageWaiting(self.socket);
    }

    pub fn deinit(self: *@This()) void {
        posix.close(self.socket);
        self.server_snapshots.deinit();
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

pub fn sendMessageToServer(sock: posix.socket_t, address: posix.sockaddr, message: *const ClientToServerMessage) !void {
    const ptr = @as([]const u8, @ptrCast(message))[0..message.sizeOf()];

    _ = try posix.sendto(
        sock,
        ptr,
        0,
        &address,
        @sizeOf(@TypeOf(address)),
    );
}

pub fn sendMessageToClient(sock: posix.socket_t, address: posix.sockaddr, message: *const ServerToClientMessage) !void {
    const ptr = @as([]const u8, @ptrCast(message))[0..message.sizeOf()];

    _ = try posix.sendto(
        sock,
        ptr,
        0,
        &address,
        @sizeOf(@TypeOf(address)),
    );
}

fn serverReceiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, ClientToServerMessage } {
    var message: ClientToServerMessage = undefined;
    var address: posix.sockaddr = undefined;
    var addrlen: posix.socklen_t = @sizeOf(@TypeOf(address));

    const len = try posix.recvfrom(sock, @ptrCast(&message), 0, &address, &addrlen);
    if (len < 2) {
        @panic("AAHHHHHHHHHHH");
    }
    // TODO: assert received type makes sense and whatnot
    if (len != message.sizeOf()) {
        @panic("AHH2");
    }
    // TODO: assert received len == sizeof
    return .{ address, message };
}

fn clientReceiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, ServerToClientMessage } {
    var message: ServerToClientMessage = undefined;
    var address: posix.sockaddr = undefined;
    var addrlen: posix.socklen_t = @sizeOf(@TypeOf(address));

    const len = try posix.recvfrom(sock, @ptrCast(&message), 0, &address, &addrlen);
    if (len < 2) {
        @panic("AAHHHHHHHHHHH");
    }
    if (len != message.sizeOf()) {
        @panic("AHH2");
    }
    // TODO: assert received len == sizeof
    return .{ address, message };
}

pub fn connectToServer(id: ClientId, gpa: std.mem.Allocator) !NetworkState {
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, 0);
    errdefer posix.close(socket);

    try posix.connect(socket, &server_address.any, server_address.getOsSockLen());
    try sendMessageToServer(
        socket,
        server_address.any,
        &ClientToServerMessage{
            .type = .connection,
            .message = .{ .connection = ConnectionMessage{
                .client_id = id,
            } },
        },
    );

    return NetworkState{ .client = Client{
        .socket = socket,
        .server_address = server_address.any,
        .id = id,
        .server_snapshots = .init(gpa),
    } };
}

pub fn setupServer(gpa: std.mem.Allocator) !NetworkState {
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(sock);

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

pub fn sendInput(client: *const Client, input: engine.Input, frame_number: i64) !void {
    std.debug.print("F{d} sending input\n", .{frame_number});
    try sendMessageToServer(
        client.socket,
        client.server_address,
        &ClientToServerMessage{
            .type = .input,
            .message = .{ .input = InputMessage{
                .client_id = client.id,
                .input = input,
                .frame_number = frame_number,
            } },
        },
    );
}

pub fn receiveInput(server: *Server) !InputMessage {
    while (true) {
        const address, const message = try serverReceiveMessage(server.socket);

        switch (message.type) {
            .input => {
                return message.message.input;
            },
            .connection => {
                try server.onClientConnected(address, message.message.connection.client_id);
                continue;
            },
        }
    }
}

pub fn receiveSnapshotPart(client: *const Client) !ServerToClientMessage {
    while (true) {
        // problem is probably that it notices the server sent an ICMP packet of "not yet"
        _, const message = try clientReceiveMessage(client.socket);

        switch (message.type) {
            .snapshot_part => {
                return message;
            },
            .finished_sending_snapshots => {
                return message; // TODO: Maybe return just the frame number?
            },
        }
    }
}

fn sendToAllClients(server: *const Server, message: *const ServerToClientMessage) !void {
    for (server.client_addresses) |c| {
        if (c) |address| {
            std.debug.print("P{any} ", .{address});
            try sendMessageToClient(server.socket, address, message);
        }
    }
    std.debug.print("\n", .{});
}

pub fn sendSnapshots(server: *const Server, world: *engine.World) !void {
    var iter = world.entities.iter();
    std.debug.print("Sending frame {}\n", .{world.time.frame_number});
    while (iter.next()) |entity| {
        if (world.entities.modified_this_frame[entity.id.index]) {
            try sendToAllClients(server, &ServerToClientMessage{
                .type = .snapshot_part,
                .message = .{ .snapshot_part = SnapshotPartMessage{
                    .entity_diff = entity.make_diff(),
                    .frame_number = world.time.frame_number,
                } },
            });
        }
    }
    try sendToAllClients(server, &ServerToClientMessage{
        .type = .finished_sending_snapshots,
        .message = .{ .finished_sending_snapshots = FinishedSendingSnapshotsMessage{
            .frame_number = world.time.frame_number,
        } },
    });
    std.debug.print("Sent snapshots for frame {}\n", .{world.time.frame_number});
}
