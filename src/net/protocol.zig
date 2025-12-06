const game = @import("game");
const lib = @import("lib");

// Currently I source a couple of types from the rest of the project,
// as I'm okay with having them be bit-packed across the entire project.
// These might be changed to have packed variants here and non-packed
// variants in the original files when optimization is more important.
const EntityDiff = game.EntityDiff;
const Input = game.Input;
const FrameNumber = lib.FrameNumber;

pub const ClientId = packed struct {
    value: u8,

    pub fn client_id(value: u8) ClientId {
        return ClientId{ .value = value };
    }
};

/// Client->Server: A message asking to be connected, and to use the specified client-id.
pub const ConnectionMessage = packed struct {
    client_id: ClientId,
};

/// Server->Client: A message acknoledging the connection,
/// and updating the client with the current frame number.
pub const ConnectionAckMessage = packed struct {
    frame_number: FrameNumber,
};

/// Client->Server: A message containing the pressed inputs for the given frame.
pub const InputMessage = packed struct {
    frame_number: FrameNumber,
    client_id: ClientId,
    input: Input,
};

/// Server->Client: A message acknoledging the received input,
/// with metadata about when the input was sent and received, for the sake of synchronization.
/// Currently unused for input reliability.
pub const InputAckMessage = packed struct {
    /// The frame on the client in which the input message we're ack'ing was sent.
    ack_frame_number: FrameNumber,
    /// The frame on the server in which we received the input message.
    received_during_frame: FrameNumber,
};

/// Server->Client: A message containing the updated state of a single entity.
/// Part of the process of sending a snapshot from the server to the client.
pub const SnapshotPartMessage = packed struct {
    frame_number: FrameNumber,
    entity_diff: EntityDiff,
};

/// Server->Client: A message signifying the end of
/// the snapshot sending process for the given frame.
pub const FinishedSendingSnapshotsMessage = packed struct {
    frame_number: FrameNumber,
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

    pub fn isTypeValid(id: u8) bool {
        return switch (@as(ClientToServerMessageType, @enumFromInt(id))) {
            .connection => true,
            .input => true,
            else => false,
        };
    }

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

    pub fn isTypeValid(id: u8) bool {
        return switch (@as(ServerToClientMessageType, @enumFromInt(id))) {
            .connection_ack => true,
            .snapshot_part => true,
            .finished_sending_snapshots => true,
            .input_ack => true,
            else => false,
        };
    }

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
