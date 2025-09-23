const engine = @import("engine.zig");
const std = @import("std");
const posix = std.posix;

const port = 12348;
const server_address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);

pub const ClientId = packed struct {
    value: u4,

    pub fn client_id(value: u4) ClientId {
        return ClientId{ .value = value };
    }
};

/// A message sent from the client to the server, with the current input state.
pub const InputMessage = packed struct {
    client_id: ClientId,
    input: engine.Input,
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

pub fn connectToServer(id: ClientId) !NetworkState {
    const sockfd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, 0);
    errdefer posix.close(sockfd);

    try posix.connect(sockfd, &server_address.any, server_address.getOsSockLen());
    _ = try posix.send(sockfd, @as(*const [3:0]u8, "foo"), 0);

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

    var buff: [4]u8 = undefined;
    _ = try posix.recv(sock, &buff, 0);
    std.debug.print("Got stuff in my buffer {s}", .{buff});
    return NetworkState{ .server = .{ .socket = sock } };
}

pub fn sendInput(client: *const Client, input: engine.Input) !void {
    const message = InputMessage{ .client_id = client.id, .input = input };
    const ptr: []const u8 = @ptrCast(&message);

    _ = try posix.send(client.socket, ptr[0..@sizeOf(@TypeOf(message))], 0);
}

pub fn receiveInput(server: *const Server) !engine.Input {
    var buff: [@sizeOf(InputMessage)]u8 align(@alignOf(InputMessage)) = undefined;

    _ = try posix.recv(server.socket, &buff, 0);
    // TODO: assert received len == sizeof
    const message_ptr: *InputMessage = @ptrCast(&buff);
    return message_ptr.input;
}
