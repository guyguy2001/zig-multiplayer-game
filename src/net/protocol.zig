// Currently I source a couple of types from the rest of the project,
// as I'm okay with having them be bit-packed across the entire project.
// These might be changed to have packed variants here and non-packed
// variants in the original files when optimization is more important.
const engine = @import("../engine.zig");
const utils = @import("../utils.zig");

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
    frame_number: u64,
    client_id: ClientId,
    input: engine.Input,
};

pub const ConnectionAckMessage = packed struct {
    frame_number: utils.FrameNumber,
};

pub const SnapshotPartMessage = packed struct {
    frame_number: u64,
    entity_diff: engine.EntityDiff,
};

pub const FinishedSendingSnapshotsMessage = packed struct {
    frame_number: u64,
};

pub const InputAckMessage = packed struct {
    ack_frame_number: u64,
    received_during_frame: u64,
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
    connection_ack = 16,
    snapshot_part = 17,
    finished_sending_snapshots = 18,
    input_ack = 19,
};

pub const ServerToClientMessage = packed struct {
    type: ServerToClientMessageType,
    message: packed union {
        connection_ack: ConnectionAckMessage,
        snapshot_part: SnapshotPartMessage,
        finished_sending_snapshots: FinishedSendingSnapshotsMessage,
        input_ack: InputAckMessage,
    },

    pub fn sizeOf(self: *const @This()) usize {
        const prefix_size = @bitSizeOf(@TypeOf(self.type));
        const payload_size: usize = switch (self.type) {
            .connection_ack => @bitSizeOf(ConnectionAckMessage),
            .snapshot_part => @bitSizeOf(SnapshotPartMessage),
            .finished_sending_snapshots => @bitSizeOf(FinishedSendingSnapshotsMessage),
            .input_ack => @bitSizeOf(InputAckMessage),
        };
        return (prefix_size + payload_size + 7) / 8;
    }
};
