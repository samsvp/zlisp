const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;

pub const Value = union(enum) {
    int: i32,
    float: f32,
    boolean: bool,
    symbol: []const u8,
    nil,
    obj: *Obj,

    pub const True = Value{ .boolean = true };
    pub const False = Value{ .boolean = false };

    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .obj => |o| o.deinit(allocator),
            else => {},
        }
    }

    pub fn borrow(self: Value) Value {
        switch (self) {
            .obj => |o| o.count += 1,
            else => {},
        }
        return self;
    }

    pub fn printValue(v: Value) void {
        switch (v) {
            .obj => |o| switch (o.kind) {
                .string => std.debug.print("{s}", .{o.as(Obj.String).bytes}),
                .function => std.debug.print("<fn = {s}>", .{o.as(Obj.Function).name}),
            },
            .symbol => |s| std.debug.print("{s}", .{s}),
            else => std.debug.print("{}", .{v}),
        }
    }

    pub fn eql(a: Value, b: Value) bool {
        return switch (a) {
            .int => |i_1| switch (b) {
                .int => |i_2| i_1 == i_2,
                else => false,
            },
            .float => |f_1| switch (b) {
                .float => |f_2| f_1 == f_2,
                else => false,
            },
            .boolean => |b_1| switch (b) {
                .boolean => |b_2| b_1 == b_2,
                else => false,
            },
            .symbol => |s_1| switch (b) {
                .symbol => |s_2| std.mem.eql(u8, s_1, s_2),
                else => false,
            },
            .nil => switch (b) {
                .nil => true,
                else => false,
            },
            .obj => |o_1| switch (b) {
                .obj => |o_2| switch (o_1.kind) {
                    .string => switch (o_2.kind) {
                        .string => std.mem.eql(
                            u8,
                            o_1.as(Obj.String).bytes,
                            o_2.as(Obj.String).bytes,
                        ),
                        .function => false,
                    },
                    .function => false,
                },
                else => false,
            },
        };
    }
};

pub const Obj = struct {
    kind: Kind,
    count: usize,

    pub const Kind = enum {
        string,
        function,
    };

    pub fn init(kind: Kind) Obj {
        return .{ .kind = kind, .count = 1 };
    }

    pub fn deinit(self: *Obj, allocator: std.mem.Allocator) void {
        if (self.count == 0) return;

        self.count -= 1;

        if (self.count == 0) switch (self.kind) {
            .string => self.as(String).deinit(allocator),
            .function => self.as(Function).deinit(allocator),
        };
    }

    pub fn as(self: *Obj, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

    /// Objects which live in the heap and must be garbage collected.
    pub const String = struct {
        obj: Obj,
        bytes: []u8,

        pub fn init(allocator: std.mem.Allocator, v: []const u8) !*String {
            const string_ptr = try allocator.create(String);
            string_ptr.* = String{
                .obj = Obj.init(.string),
                .bytes = try allocator.dupe(u8, v),
            };
            return string_ptr;
        }

        pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
            allocator.destroy(self);
        }

        pub fn copy(self: String, allocator: std.mem.Allocator) !*String {
            return String.init(allocator, self.bytes);
        }

        pub fn appendMut(self: *String, allocator: std.mem.Allocator, v: []const u8) !void {
            const old_len = self.bytes.len;
            self.bytes = try allocator.realloc(self.bytes, self.bytes.len + v.len);
            @memcpy(self.bytes.ptr + old_len, v);
        }
    };

    pub const Function = struct {
        obj: Obj,
        arity: u32,
        chunk: *Chunk,
        name: []const u8,
        help: []const u8,

        pub fn init(allocator: std.mem.Allocator, arity: u32, chunk: *Chunk, name: []const u8, help: []const u8) !*Function {
            const func = try allocator.create(Function);
            func.* = Function{
                .obj = Obj.init(.function),
                .arity = arity,
                .chunk = chunk,
                .name = name,
                .help = help,
            };
            return func;
        }

        pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
            self.chunk.deinit(allocator);
            allocator.destroy(self.chunk);
            allocator.destroy(self);
        }
    };
};
