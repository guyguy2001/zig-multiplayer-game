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
