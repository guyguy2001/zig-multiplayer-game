const std = @import("std");

pub fn pack_type(T: type) type {
    var type_info = @typeInfo(T);
    switch (type_info) {
        .@"struct" => |*s| {
            s.decls = &[0]std.builtin.Type.Declaration{};
            s.layout = .@"packed";
            var fields: [s.fields.len]std.builtin.Type.StructField = undefined;
            @memcpy(&fields, s.fields.ptr);
            for (&fields) |*f| {
                f.type = pack_type(f.type);
                f.alignment = 0;
            }
            s.fields = &fields;
        },
        else => @compileError("utils.as_packed only works for structs!"),
    }

    return @Type(type_info);
}

pub fn to_packed(T: type, source: T) pack_type(T) {
    var result: pack_type(T) = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        @field(result, field.name) = @field(source, field.name);
    }
    return result;
}

pub fn to_unpacked(T: type, source: pack_type(T)) T {
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        @field(result, field.name) = @field(source, field.name);
    }
    return result;
}

// This currently uses an allocation-based linked list, while the implementation I actually want
// would be with a fixed-sized buffer, as part of the point of this struct
// is for cases where I'm expecting a fixed amount of messages at a time.
pub fn FrameCyclicBuffer(comptime T: type, comptime empty_value: T) type {
    return struct {
        const Self = @This();

        const Block = struct {
            node: std.DoublyLinkedList.Node,
            data: T,
        };

        // invariant: "buff.last.frame" == first_frame + buff.length - 1
        allocator: std.mem.Allocator,
        list: std.DoublyLinkedList,
        first_frame: i64,
        len: i64,

        pub fn init(gpa: std.mem.Allocator) Self {
            return Self{
                .allocator = gpa,
                .list = .{},
                .first_frame = 1,
                .len = 0,
            };
        }

        pub fn extend(self: *Self, frame: i64) !void {
            while (self.first_frame + self.len <= frame) {
                const block = try self.allocator.create(Block);
                block.* = .{
                    .data = empty_value,
                    .node = .{},
                };
                self.list.append(&block.node);
                self.len += 1;
            }
        }

        pub fn at(self: *Self, frame: i64) !*T {
            try self.extend(frame);
            var f = self.first_frame;
            var curr = self.list.first.?;
            if (frame - f > 2000) {
                return error.InvalidFrameAccess;
            }
            while (f < frame) {
                f += 1;
                curr = curr.next.?;
            }

            const block: *Block = @fieldParentPtr("node", curr);
            return &block.data;
        }

        fn freeNode(self: Self, node: *std.DoublyLinkedList.Node) void {
            const block: *Block = @fieldParentPtr("node", node);
            self.allocator.destroy(block);
        }

        pub fn dropFrame(self: *Self, frame: i64) !void {
            if (frame != self.first_frame) {
                return error.TriedToDropWrongFrame;
            }
            const first = self.list.first.?;
            _ = self.list.popFirst();
            self.freeNode(first);
            self.len -= 1;
            self.first_frame += 1;
        }

        pub fn deinit(self: *Self) void {
            while (self.list.pop()) |node| {
                self.freeNode(node);
            }
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
