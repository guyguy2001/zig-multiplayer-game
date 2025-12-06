const std = @import("std");

pub const port = 12348;
pub const server_address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);
pub const server_bind_address = std.net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, port);
// We use ms because this is how it's defined in winsock - https://learn.microsoft.com/en-us/windows/win32/api/winsock/nf-winsock-setsockopt
pub const default_socket_timeout_ms: std.os.windows.DWORD = 2000;
pub const max_connection_attempts = 3;

pub const stop_holding_input_threshold = 5;
pub const frame_buffer_size = 3;

// The amount of frames we want our inputs to arrive at the server before it needs them
pub const desired_server_buffer = 6;

pub const simulation_speed = struct {
    pub const regular_fps = 60;

    pub const max_speedup = 10;
    pub const max_slowdown = 0.1;
    // How much to change the speed per missing frame.
    pub const speedup_intensity = 0.1;
};
