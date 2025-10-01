const engine = @import("engine.zig");
const std = @import("std");
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

pub const MessageType = enum(u8) {
    connection = 5,
    input = 6,
    snapshot_part = 7,
};

pub const Message = packed struct {
    type: MessageType,
    message: packed union {
        connection: ConnectionMessage,
        input: InputMessage,
        snapshot_part: SnapshotPartMessage,
    },

    pub fn sizeOf(self: *const @This()) usize {
        const prefix_size = @bitSizeOf(@TypeOf(self.type));
        const payload_size: usize = switch (self.type) {
            .connection => @bitSizeOf(ConnectionMessage),
            .input => @bitSizeOf(InputMessage),
            .snapshot_part => @bitSizeOf(SnapshotPartMessage),
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
};

pub const Client = struct {
    id: ClientId,
    socket: posix.socket_t,
    server_address: posix.sockaddr,

    pub fn hasMessageWaiting(self: *const @This()) !bool {
        return _hasMessageWaiting(self.socket);
    }
};

pub const NetworkState = union(NetworkRole) {
    client: Client,
    server: Server,

    pub fn cleanup(self: *@This()) !void {
        switch (self.*) {
            .client => |c| {
                posix.close(c.socket);
            },
            .server => |s| {
                posix.close(s.socket);
            },
        }
    }
};

pub fn sendMessage(sock: posix.socket_t, address: posix.sockaddr, message: *const Message) !void {
    // std.debug.print("Sizeof Message: {}\n", .{@sizeOf(Message)});
    // std.debug.print("Sending {any}: \n", .{message.*});
    const ptr = @as([]const u8, @ptrCast(message))[0..message.sizeOf()];
    // std.debug.print("Sending (hex): ", .{});
    // for (ptr) |byte| {
    //     std.debug.print("{x:0>2} ", .{byte}); // Prints each byte in hex, padded with leading zero if necessary
    // }
    // std.debug.print("\n", .{});

    _ = try posix.sendto(
        sock,
        ptr,
        0,
        &address,
        @sizeOf(@TypeOf(address)),
    );
}

fn receiveMessage(sock: posix.socket_t) !struct { posix.sockaddr, Message } {
    var message: Message = undefined;
    var address: posix.sockaddr = undefined;
    var addrlen: posix.socklen_t = @sizeOf(@TypeOf(address));

    const len = try posix.recvfrom(sock, @ptrCast(&message), 0, &address, &addrlen);
    // message = Message{ .client_id = .client_id(4), .message = .{ .connection = .{} }, .type = .connection };
    // const len = 2;
    // std.debug.print("Received (hex): ", .{});
    // for (@as([]u8, @ptrCast(&message))[0..len]) |byte| {
    //     std.debug.print("{x:0>2} ", .{byte}); // Prints each byte in hex, padded with leading zero if necessary
    // }
    // std.debug.print("\n", .{});
    // std.debug.print("Got {d} bytes, out of {d}\n", .{ len, @sizeOf(Message) });
    if (len < 2) {
        @panic("AAHHHHHHHHHHH");
    }
    if (len != message.sizeOf()) {
        @panic("AHH2");
    }
    // TODO: assert received len == sizeof
    return .{ address, message };
}

pub fn connectToServer(id: ClientId) !NetworkState {
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, 0);
    errdefer posix.close(socket);

    try posix.connect(socket, &server_address.any, server_address.getOsSockLen());
    try sendMessage(
        socket,
        server_address.any,
        &Message{
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
    } };
}

pub fn setupServer() !NetworkState {
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(sock);

    try posix.bind(sock, &server_address.any, server_address.getOsSockLen());

    std.debug.print("UDP Server listening on port {d}\n", .{port});

    return NetworkState{ .server = Server{
        .socket = sock,
        .client_addresses = .{null} ** 3,
    } };
}

pub fn sendInput(client: *const Client, input: engine.Input, frame_number: i64) !void {
    try sendMessage(
        client.socket,
        client.server_address,
        &Message{
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
        const address, const message = try receiveMessage(server.socket);

        switch (message.type) {
            .input => {
                return message.message.input;
            },
            .connection => {
                try server.onClientConnected(address, message.message.connection.client_id);
                continue;
            },
            .snapshot_part => unreachable,
        }
    }
}

pub fn receiveSnapshotPart(client: *const Client) !SnapshotPartMessage {
    while (true) {
        // problem is probably that it notices the server sent an ICMP packet of "not yet"
        _, const message = try receiveMessage(client.socket);

        switch (message.type) {
            .input => unreachable,
            .connection => continue,
            .snapshot_part => return message.message.snapshot_part,
        }
    }
}

// pub fn receiveMessage3(sock: posix.socket_t, message_pool: [1]Message) !Message {
//     _ = try posix.recv(sock, @ptrCast(&message_pool), 0);
//     // TODO: assert received len == sizeof
//     return message_pool[0];
// }

// pub fn receiveInput3(server: *const Server) !engine.Input {
//     while (true) {
//         var pool: [1]Message = undefined;

//         const message = try receiveMessage(server.socket, &pool);

//         switch (message) {
//             .input => {
//                 return message.message.input.input;
//             },
//             .connection => continue,
//         }
//     }
// }

pub fn sendSnapshots(server: *const Server, world: *engine.World) !void {
    var iter = world.entities.iter();
    while (iter.next()) |entity| {
        if (world.entities.modified_this_frame[entity.id.index]) {
            const message = Message{
                .type = .snapshot_part,
                .message = .{ .snapshot_part = SnapshotPartMessage{
                    .entity_diff = entity.make_diff(),
                    .frame_number = world.time.frame_number,
                } },
            };
            for (server.client_addresses) |c| {
                if (c) |address| {
                    try sendMessage(server.socket, address, &message);
                }
            }
        }
    }
}
