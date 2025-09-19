const engine = @import("engine");
const std = @import("std");
const posix = std.posix;

const port = 12348;
const server_address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);

pub const NetworkMessage = struct {
    data: [4]u8,
};

pub const NetworkRoleTag = enum {
    client,
    server,
};
pub const NetworkRole = union(NetworkRoleTag) {
    client: struct { socket: posix.socket_t },
    server: struct {
        server: std.net.Server,
    },

    pub fn cleanup(self: *@This()) !void {
        switch (self.*) {
            .client => |c| {
                posix.close(c.socket);
            },
            .server => |s| {
                _ = s; // autofix

            },
        }
    }
};

pub fn connectToServer() !void {
    const sockfd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, 0);
    errdefer posix.close(sockfd);

    try posix.connect(sockfd, &server_address.any, server_address.getOsSockLen());
    _ = try posix.send(sockfd, @as(*const [3:0]u8, "foo"), 0);
}

pub fn waitForConnection() !posix.socket_t {
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(sock);

    try posix.bind(sock, &server_address.any, server_address.getOsSockLen());

    std.debug.print("UDP Server listening on port {d}\n", .{port});

    var buff: [4]u8 = undefined;
    _ = try posix.recv(sock, &buff, 0);
    std.debug.print("Got stuff in my buffer {s}", .{buff});
    return sock;
}

// fn sendToServer(world: *World) {

// }
