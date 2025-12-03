const std = @import("std");
const posix = std.posix;

pub fn hasMessageWaiting(socket: posix.socket_t) !bool {
    var fds = [_]posix.pollfd{.{
        .fd = socket,
        .events = posix.POLL.IN,
        .revents = 0,
    }};
    return try posix.poll(&fds, 0) > 0;
}
