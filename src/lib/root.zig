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

        /// Helper for `at` - extends the list until `frame`, if allowed,
        /// filling the items with `empty_value`.
        fn extend(self: *Self, frame: u64) !void {
            while (self.first_frame + self.len <= frame) {
                if (!allow_empty) {
                    std.log.err("Tried to access frame {d}, only have {d}-{d}\n", .{ frame, self.first_frame, self.first_frame + self.len - 1 });
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

        /// Appends the next item in the list.
        /// Fails if the given frame number isn't the first frame not yet in the list.
        pub fn append(self: *Self, data: T, frame: u64) !void {
            if (self.first_frame + self.len != frame) {
                std.log.err("Tried to append frame {d}, but we have frames {d}-{d}\n", .{ frame, self.first_frame, self.first_frame + self.len - 1 });
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

        /// Accesses the value at frame `frame`, returning a pointer to it.
        /// If `frame` isn't yet in the list, /// extends the list until
        /// that point with `empty_values`, if allowed.
        /// Since this function returns a pointer and extends the list,
        /// it's meant to be used for updating the list as much as for reading from it.
        pub fn at(self: *Self, frame: u64) !*T {
            if (frame < self.first_frame) {
                // TODO: Consider retuning null
                std.log.err("Tried to access F{d}, valid range is F{d}-F{d}\n", .{ frame, self.first_frame, self.first_frame + self.len });
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

        /// Drops the first frame in the buffer, returning a pointer to it.
        /// Dropping a frame other than the first is considered against the contract of this class -
        /// and is thus considered unreachable, crashing the program.
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

        /// de-initializes the buffer, without de-initing the T values -
        /// do not use this if they have a cleanup function that needs to be called!
        pub fn shallowDeinit(self: *Self) void {
            while (self.list.popFirst()) |node| {
                const block = Block.from_node(node);
                self.freeBlock(block);
            }
        }
    };
}

test "cyclic buffer - basic operations" {
    const expect = std.testing.expect;
    _ = expect; // autofix
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u8, 0, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Initial state
    try expectEqual(0, cyclic_buffer.len);
    try expectEqual(1, cyclic_buffer.first_frame);

    // Access frame 4, auto-extends with empty values
    const at4 = try cyclic_buffer.at(4);
    try expectEqual(0, at4.*);
    at4.* = 2;
    try expectEqual(2, at4.*);
    try expectEqual(4, cyclic_buffer.len);

    // Access frames 1-3, all have default value
    try expectEqual(0, (try cyclic_buffer.at(1)).*);
    try expectEqual(0, (try cyclic_buffer.at(2)).*);
    try expectEqual(0, (try cyclic_buffer.at(3)).*);
    try expectEqual(4, cyclic_buffer.len);
    try expectEqual(1, cyclic_buffer.first_frame);

    // Drop frame 1, advance the window
    const dropped = cyclic_buffer.dropFrame(1);
    cyclic_buffer.freeBlock(dropped);
    try expectEqual(3, cyclic_buffer.len);
    try expectEqual(2, cyclic_buffer.first_frame);

    // Access remaining frames
    try expectEqual(0, (try cyclic_buffer.at(2)).*);
    try expectEqual(0, (try cyclic_buffer.at(3)).*);
    try expectEqual(2, (try cyclic_buffer.at(4)).*);
}

test "cyclic buffer - sequential frames" {
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u32, 0, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Add frames 1, 2, 3 sequentially
    const f1 = try cyclic_buffer.at(1);
    f1.* = 100;
    const f2 = try cyclic_buffer.at(2);
    f2.* = 200;
    const f3 = try cyclic_buffer.at(3);
    f3.* = 300;

    try expectEqual(3, cyclic_buffer.len);
    try expectEqual(100, (try cyclic_buffer.at(1)).*);
    try expectEqual(200, (try cyclic_buffer.at(2)).*);
    try expectEqual(300, (try cyclic_buffer.at(3)).*);
}

test "cyclic buffer - gap filling" {
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(i32, -1, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Access frame 1
    const f1 = try cyclic_buffer.at(1);
    f1.* = 10;

    // Jump to frame 5, filling gaps with -1
    const f5 = try cyclic_buffer.at(5);
    f5.* = 50;

    try expectEqual(5, cyclic_buffer.len);
    try expectEqual(10, (try cyclic_buffer.at(1)).*);
    try expectEqual(-1, (try cyclic_buffer.at(2)).*);
    try expectEqual(-1, (try cyclic_buffer.at(3)).*);
    try expectEqual(-1, (try cyclic_buffer.at(4)).*);
    try expectEqual(50, (try cyclic_buffer.at(5)).*);
}

test "cyclic buffer - drop and advance" {
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u8, 0, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Fill buffer with frames 1-5
    for (1..6) |i| {
        const f = try cyclic_buffer.at(i);
        f.* = @intCast(i * 10);
    }

    try expectEqual(5, cyclic_buffer.len);
    try expectEqual(1, cyclic_buffer.first_frame);

    // Drop frames 1-3
    for (1..4) |_| {
        const dropped = cyclic_buffer.dropFrame(cyclic_buffer.first_frame);
        cyclic_buffer.freeBlock(dropped);
    }

    try expectEqual(2, cyclic_buffer.len);
    try expectEqual(4, cyclic_buffer.first_frame);
    try expectEqual(40, (try cyclic_buffer.at(4)).*);
    try expectEqual(50, (try cyclic_buffer.at(5)).*);
}

test "cyclic buffer - reaccess values" {
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u64, 0, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Set value at frame 10
    const f10 = try cyclic_buffer.at(10);
    f10.* = 12345;

    // Re-access and verify
    try expectEqual(12345, (try cyclic_buffer.at(10)).*);

    // Access other frames and verify f10 is unchanged
    const f5 = try cyclic_buffer.at(5);
    f5.* = 999;
    try expectEqual(12345, (try cyclic_buffer.at(10)).*);
    try expectEqual(999, (try cyclic_buffer.at(5)).*);
}

test "cyclic buffer - complex struct" {
    const expectEqual = std.testing.expectEqual;

    const TestStruct = struct {
        x: i32,
        y: i32,
        z: u8,
    };

    const empty_struct = TestStruct{ .x = 0, .y = 0, .z = 0 };
    var cyclic_buffer = FrameCyclicBuffer(TestStruct, empty_struct, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Store complex data
    const f1 = try cyclic_buffer.at(1);
    f1.* = TestStruct{ .x = 10, .y = 20, .z = 5 };

    const f2 = try cyclic_buffer.at(2);
    f2.* = TestStruct{ .x = 30, .y = 40, .z = 15 };

    // Verify
    try expectEqual(10, (try cyclic_buffer.at(1)).*.x);
    try expectEqual(20, (try cyclic_buffer.at(1)).*.y);
    try expectEqual(5, (try cyclic_buffer.at(1)).*.z);

    try expectEqual(30, (try cyclic_buffer.at(2)).*.x);
    try expectEqual(40, (try cyclic_buffer.at(2)).*.y);
    try expectEqual(15, (try cyclic_buffer.at(2)).*.z);
}

test "cyclic buffer - maintain order after drops" {
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u8, 0, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Fill with 1-10
    for (1..11) |i| {
        const f = try cyclic_buffer.at(i);
        f.* = @intCast(i);
    }

    // Drop 1-5
    for (1..6) |_| {
        const dropped = cyclic_buffer.dropFrame(cyclic_buffer.first_frame);
        cyclic_buffer.freeBlock(dropped);
    }

    // Verify 6-10 are intact
    try expectEqual(6, (try cyclic_buffer.at(6)).*);
    try expectEqual(7, (try cyclic_buffer.at(7)).*);
    try expectEqual(8, (try cyclic_buffer.at(8)).*);
    try expectEqual(9, (try cyclic_buffer.at(9)).*);
    try expectEqual(10, (try cyclic_buffer.at(10)).*);
}

test "cyclic buffer - extend beyond current range" {
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u32, 42, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Access a far future frame
    const f100 = try cyclic_buffer.at(100);
    try expectEqual(42, f100.*);

    try expectEqual(100, cyclic_buffer.len);
    try expectEqual(1, cyclic_buffer.first_frame);

    // Verify a middle frame has the default value
    try expectEqual(42, (try cyclic_buffer.at(50)).*);

    // Modify it and verify
    const f50 = try cyclic_buffer.at(50);
    f50.* = 999;
    try expectEqual(999, (try cyclic_buffer.at(50)).*);
}

test "cyclic buffer - single frame operations" {
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u8, 0, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Only frame 1
    const f1 = try cyclic_buffer.at(1);
    f1.* = 77;

    try expectEqual(1, cyclic_buffer.len);
    try expectEqual(77, (try cyclic_buffer.at(1)).*);

    // Drop it
    const dropped = cyclic_buffer.dropFrame(1);
    cyclic_buffer.freeBlock(dropped);

    try expectEqual(0, cyclic_buffer.len);
    try expectEqual(2, cyclic_buffer.first_frame);
}

test "cyclic buffer - alternating access pattern" {
    const expectEqual = std.testing.expectEqual;

    var cyclic_buffer = FrameCyclicBuffer(u8, 0, true).init(std.testing.allocator);
    defer cyclic_buffer.shallowDeinit();

    // Access in alternating pattern
    (try cyclic_buffer.at(1)).* = 10;
    (try cyclic_buffer.at(3)).* = 30;
    (try cyclic_buffer.at(2)).* = 20;
    (try cyclic_buffer.at(5)).* = 50;
    (try cyclic_buffer.at(4)).* = 40;

    try expectEqual(5, cyclic_buffer.len);
    try expectEqual(10, (try cyclic_buffer.at(1)).*);
    try expectEqual(20, (try cyclic_buffer.at(2)).*);
    try expectEqual(30, (try cyclic_buffer.at(3)).*);
    try expectEqual(40, (try cyclic_buffer.at(4)).*);
    try expectEqual(50, (try cyclic_buffer.at(5)).*);
}
