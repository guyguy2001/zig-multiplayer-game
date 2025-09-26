const engine = @import("engine.zig");
const std = @import("std");
const posix = std.posix;

const port = 12348;
const server_address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);

pub const ClientId = packed struct {
    value: u8,

    pub fn client_id(value: u8) ClientId {
        return ClientId{ .value = value };
    }
};

pub const ConnectionMessage = packed struct {};

/// A message sent from the client to the server, with the current input state
pub const InputMessage = packed struct {
    frame_number: i64,
    input: engine.Input,
};

pub const MessageType = enum(u8) {
    connection = 5,
    input = 6,
};

pub const Message = packed struct {
    client_id: ClientId,
    type: MessageType,
    message: packed union {
        connection: ConnectionMessage,
        input: InputMessage,
    },

    pub fn sizeOf(self: *const @This()) u8 {
        const prefix_size = @bitSizeOf(@TypeOf(self.client_id)) + @bitSizeOf(@TypeOf(self.type));
        const payload_size: u8 = switch (self.type) {
            .connection => @bitSizeOf(ConnectionMessage),
            .input => @bitSizeOf(InputMessage),
        };
        return (prefix_size + payload_size + 7) / 8;
    }
};

pub const NetworkRole = enum {
    client,
    server,
};

pub const Server = struct {
    socket: posix.socket_t,
};
pub const Client = struct {
    id: ClientId,
    socket: posix.socket_t,
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

pub fn sendMessage(sock: posix.socket_t, message: *const Message) !void {
    // The problem is that since we don't know what the type of the message is, we don't know its size either
    // So we end up always sending the entire 16 bytes, even if we only have a Connection message, which isn't that long.
    std.debug.print("Sizeof Message: {}\n", .{@sizeOf(Message)});
    // std.debug.print("Sending {any}: \n", .{message.*});
    const ptr = @as([]const u8, @ptrCast(message))[0..message.sizeOf()];
    std.debug.print("Sending (hex): ", .{});
    for (ptr) |byte| {
        std.debug.print("{x:0>2} ", .{byte}); // Prints each byte in hex, padded with leading zero if necessary
    }
    std.debug.print("\n", .{});

    _ = try posix.send(sock, ptr, 0);
}

pub fn receiveMessage(sock: posix.socket_t) !Message {
    var message: Message = undefined;

    const len = try posix.recv(sock, @ptrCast(&message), 0);
    // message = Message{ .client_id = .client_id(4), .message = .{ .connection = .{} }, .type = .connection };
    // const len = 2;
    std.debug.print("Received (hex): ", .{});
    for (@as([]u8, @ptrCast(&message))[0..len]) |byte| {
        std.debug.print("{x:0>2} ", .{byte}); // Prints each byte in hex, padded with leading zero if necessary
    }
    std.debug.print("\n", .{});
    std.debug.print("Got {d} bytes, out of {d}\n", .{ len, @sizeOf(Message) });
    if (len < 2) {
        @panic("AAHHHHHHHHHHH");
    }
    if (len != message.sizeOf()) {
        @panic("AHH2");
    }
    // TODO: assert received len == sizeof
    return message;
}

pub fn connectToServer(id: ClientId) !NetworkState {
    const sockfd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, 0);
    errdefer posix.close(sockfd);

    try posix.connect(sockfd, &server_address.any, server_address.getOsSockLen());
    try sendMessage(
        sockfd,
        &Message{
            .type = .connection,
            .client_id = id,
            .message = .{ .connection = ConnectionMessage{} },
        },
    );

    return NetworkState{ .client = .{
        .socket = sockfd,
        .id = id,
    } };
}

pub fn waitForConnection() !NetworkState {
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(sock);

    try posix.bind(sock, &server_address.any, server_address.getOsSockLen());

    std.debug.print("UDP Server listening on port {d}\n", .{port});

    const message = receiveMessage(sock);
    std.debug.print("Got stuff in my buffer {any}", .{message});
    return NetworkState{ .server = .{ .socket = sock } };
}

pub fn sendInput(client: *const Client, input: engine.Input, frame_number: i64) !void {
    try sendMessage(
        client.socket,
        &Message{
            .type = .input,
            .client_id = client.id,
            .message = .{ .input = InputMessage{
                .input = input,
                .frame_number = frame_number,
            } },
        },
    );
}

pub fn receiveInput(server: *const Server) !engine.Input {
    while (true) {
        const message = try receiveMessage(server.socket);

        switch (message.type) {
            .input => {
                return message.message.input.input;
            },
            .connection => continue,
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
