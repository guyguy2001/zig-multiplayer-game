const std = @import("std");

pub const utils = @import("utils.zig");

pub const FrameNumber = u64;

/// A queue of frames, in sequence. The queue is supposed to remain at roughly a fixed size,
/// with frames being dequeued as often as they're queued.
///
/// `T` is the type of the elements of the buffer.
///
/// When `allow_empty` is true, accessing a "future" frame enqueue all
/// frames between the last queued farme and it, inclusive, and uses the value of `empty_value`.
/// When it is false, new frames must be added manually, with a specified value.
///
/// If `allow_empty` is true, `empty_value` is the value that's enqueued when skipping frames,
/// or when accessing the next one.
/// If it is false, then `empty_value` is unused, and should be set to `undefined`.
///
/// Currently, the implementation uses a linked list - in the future,
/// I plan to move to a fixed-size buffer,as we can define during compilation
/// the maximum number of frames we need to look ahead/behind for each case.
pub fn FrameCyclicBuffer(comptime T: type, comptime empty_value: T, comptime allow_empty: bool) type {
    return struct {
        const Self = @This();

        const Block = struct {
            node: std.DoublyLinkedList.Node,
            data: T,

            /// Returns a pointer to the `Block` the given `node` is part of -
            /// the way to accessing a `Block` from the linked list.
            pub fn from_node(node: *std.DoublyLinkedList.Node) *Block {
                return @alignCast(@fieldParentPtr("node", node));
            }
        };

        allocator: std.mem.Allocator,
        list: std.DoublyLinkedList,
        first_frame: u64,
        len: u64,

        pub fn init(gpa: std.mem.Allocator) Self {
            return Self{
                .allocator = gpa,
                .list = .{},
                .first_frame = 1,
                .len = 0,
            };
        }

        pub fn extend(self: *Self, frame: u64) !void {
            while (self.first_frame + self.len <= frame) {
                if (!allow_empty) {
                    std.debug.print("Tried to access frame {d}, only have {d}-{d}\n", .{ frame, self.first_frame, self.first_frame + self.len - 1 });
                    return error.InvalidExtendWithDisallowEmpty;
                }
                const block = try self.allocator.create(Block);
                block.* = .{
                    .data = empty_value,
                    .node = .{},
                };
                self.list.append(&block.node);
                self.len += 1;
            }
        }

        pub fn append(self: *Self, data: T, frame: u64) !void {
            if (self.first_frame + self.len != frame) {
                std.debug.print("Tried to append frame {d}, but we have frames {d}-{d}\n", .{ frame, self.first_frame, self.first_frame + self.len - 1 });
                return error.InvalidFrameAppend;
            }
            const block = try self.allocator.create(Block);
            block.* = .{
                .data = data,
                .node = .{},
            };
            self.list.append(&block.node);
            self.len += 1;
        }

        pub fn at(self: *Self, frame: u64) !*T {
            if (frame < self.first_frame) {
                // TODO: Consider retuning null
                std.debug.print("Tried to access F{d}, valid range is F{d}-F{d}\n", .{ frame, self.first_frame, self.first_frame + self.len });
                return error.InvalidFrameAccess;
            }
            var f = self.first_frame;
            if (frame - f > 2000) {
                // I think I meant this to catch past frames, but this doesn't work because frame is signed.
                // I should probably fix it and remove the first if, since it would break on frame number overflow
                return error.InvalidFrameAccess;
            }
            try self.extend(frame);
            var curr = self.list.first.?;
            while (f < frame) {
                f += 1;
                curr = curr.next.?;
            }

            const block = Block.from_node(curr);
            return &block.data;
        }

        pub fn dropFrame(self: *Self, frame: u64) *Block {
            if (frame != self.first_frame) {
                unreachable;
            }
            const first = self.list.popFirst().?;
            const block = Block.from_node(first);
            self.len -= 1;
            self.first_frame += 1;
            return block;
        }

        pub fn freeBlock(self: *Self, block: *Block) void {
            self.allocator.destroy(block);
        }
    };
}

test "cyclic buffer" {
    const expect = std.testing.expect;
    _ = expect; // autofix
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u8, 0).init(std.testing.allocator);
    defer cyclic_buffer.deinit();
    try expectEqual(0, cyclic_buffer.len);
    const at4 = try cyclic_buffer.at(4);
    try expectEqual(0, at4.*);
    at4.* = 2;
    try expectEqual(2, at4.*);
    try expectEqual(4, cyclic_buffer.len);
    try expectEqual(0, (try cyclic_buffer.at(1)).*);
    try expectEqual(4, cyclic_buffer.len);
    try expectEqual(0, (try cyclic_buffer.at(2)).*);
    try expectEqual(4, cyclic_buffer.len);
    try expectEqual(0, (try cyclic_buffer.at(3)).*);
    try expectEqual(4, cyclic_buffer.len);
    try expectEqual(1, cyclic_buffer.first_frame);

    try cyclic_buffer.dropFrame(1);
    try expectEqual(3, cyclic_buffer.len);
    try expectEqual(0, (try cyclic_buffer.at(2)).*);
    try expectEqual(0, (try cyclic_buffer.at(3)).*);
    try expectEqual(2, (try cyclic_buffer.at(4)).*);
    try expectEqual(3, cyclic_buffer.len);
    try expectEqual(2, cyclic_buffer.first_frame);
}
