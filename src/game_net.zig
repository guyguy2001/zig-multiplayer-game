const engine = @import("engine");
const std = @import("std");
const posix = std.posix;

const port = 12348;
const server_address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);

pub const NetworkMessage = struct {
    data: [4]u8,
};

pub const NetworkRole = enum {
    client,
    server,
};
pub const NetworkState = union(NetworkRole) {
    client: struct { socket: posix.socket_t },
    server: struct { socket: posix.socket_t },

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

pub fn connectToServer() !NetworkState {
    const sockfd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, 0);
    errdefer posix.close(sockfd);

    try posix.connect(sockfd, &server_address.any, server_address.getOsSockLen());
    _ = try posix.send(sockfd, @as(*const [3:0]u8, "foo"), 0);

    return NetworkState{ .client = .{ .socket = sockfd } };
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

// fn sendToServer(world: *World) {

// }
