pub const client = @import("client.zig");
pub const consts = @import("consts.zig");
pub const protocol = @import("protocol.zig");
pub const utils = @import("utils.zig");
pub const server = @import("server.zig");

pub const ClientId = protocol.ClientId;

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

pub const HandleIncomingMessagesResult = enum {
    ok,
    quit,
};
