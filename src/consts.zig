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
