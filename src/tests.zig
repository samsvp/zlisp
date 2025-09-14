const std = @import("std");
const LispType = @import("types.zig").LispType;
pub const Script = @import("script.zig").Script;
const Interpreter = @import("interpreter.zig").Interpreter;
const errors = @import("errors.zig");

test "complex struct conversions" {
    const E = enum {
        e1,
        e2,
        e3,
    };

    const U = union(enum) {
        v1: S1,
        v2: S2,
        const S1 = struct {
            value: i32,

            const Self = @This();
            pub fn clone(self: Self, _: std.mem.Allocator) Self {
                return .{ .value = self.value };
            }
        };
        const S2 = struct {
            value: f32,

            const Self = @This();
            pub fn clone(self: Self, _: std.mem.Allocator) Self {
                return .{ .value = self.value };
            }
        };
    };

    const S2 = struct {
        value1: i32,
        value2: E,

        const Self = @This();

        pub fn clone(self: Self, _: std.mem.Allocator) Self {
            return .{ .value1 = self.value1, .value2 = self.value2 };
        }
    };

    const S1 = struct {
        member_1: i32,
        s2: S2,
        e1: E,
        e2: E,
        u: U,

        const Self = @This();

        pub fn clone(self: Self, _: std.mem.Allocator) Self {
            return .{
                .member_1 = self.member_1,
                .s2 = self.s2,
                .e1 = self.e1,
                .e2 = self.e2,
                .u = self.u,
            };
        }
    };

    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var map = std.StringHashMapUnmanaged(LispType).empty;
    defer map.deinit(allocator);

    const member_1 = 42;
    try map.put(allocator, "member_1", .{ .int = member_1 });
    try map.put(allocator, "e1", .{ .int = 0 });
    try map.put(allocator, "e2", LispType.String.initString(allocator, "e2"));

    const s2_v1 = 89;
    var dict = LispType.Dict.init();
    try dict.dict.addMut(allocator, LispType.String.initString(allocator, "value1"), .{ .int = s2_v1 });
    try dict.dict.addMut(allocator, LispType.String.initString(allocator, "value2"), LispType.String.initString(allocator, "e3"));
    try map.put(allocator, "s2", dict);

    const u_value = 43.0;
    var u_dict = LispType.Dict.init();
    var s_dict = LispType.Dict.init();
    try s_dict.dict.addMut(allocator, LispType.String.initString(allocator, "value"), .{ .float = u_value });
    try u_dict.dict.addMut(allocator, LispType.String.initString(allocator, "v2"), s_dict);
    try map.put(allocator, "u", u_dict);

    const v = try LispType.Record.fromHashMap(S1, allocator, map);
    const s = try v.cast(S1, allocator);

    try std.testing.expectEqual(member_1, s.member_1);
    try std.testing.expectEqual(E.e1, s.e1);
    try std.testing.expectEqual(E.e2, s.e2);
    try std.testing.expectEqual(u_value, s.u.v2.value);
    try std.testing.expectEqual(s2_v1, s.s2.value1);
    try std.testing.expectEqual(E.e3, s.s2.value2);
}

test "struct conversions" {
    const S = struct {
        member_1: i32,
        member_2: []const u8,
        member_3: f32,
        member_4: []const f32,
        member_5: [][]const u8,
        member_6: std.StringHashMapUnmanaged(i32),

        const Self = @This();

        pub fn clone(self: Self, _: std.mem.Allocator) Self {
            return .{
                .member_1 = self.member_1,
                .member_2 = self.member_2,
                .member_3 = self.member_3,
                .member_4 = self.member_4,
                .member_5 = self.member_5,
                .member_6 = self.member_6,
            };
        }
    };

    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var map = std.StringHashMapUnmanaged(LispType).empty;
    defer map.deinit(allocator);

    try map.put(allocator, "member_1", .{ .int = 42 });
    try map.put(allocator, "member_2", LispType.String.initString(allocator, "hello"));
    try map.put(allocator, "member_3", .{ .float = 3.14 });
    try map.put(allocator, "member_4", LispType.Array.initList(
        allocator,
        &[_]LispType{ .{ .float = 3.5 }, .{ .float = 5.0 } },
    ));
    try map.put(allocator, "member_5", LispType.Array.initList(
        allocator,
        &[_]LispType{
            LispType.String.initString(allocator, "hello"),
            LispType.String.initSymbol(allocator, "world"),
        },
    ));
    var dict = LispType.Dict.init();
    try dict.dict.addMut(allocator, LispType.String.initString(allocator, "hello"), .{ .int = 6 });
    try dict.dict.addMut(allocator, LispType.String.initString(allocator, "world"), .{ .int = 12 });
    try map.put(allocator, "member_6", dict);

    const v = try LispType.Record.fromHashMap(S, allocator, map);
    const s = try v.cast(S, allocator);

    try std.testing.expect(s.member_1 == map.get("member_1").?.int);
    try std.testing.expect(std.mem.eql(u8, s.member_2, map.get("member_2").?.string.getItems()));
    try std.testing.expect(s.member_3 == map.get("member_3").?.float);
    for (s.member_5, map.get("member_5").?.list.getItems()) |m, i| {
        const str = switch (i) {
            .string, .symbol, .keyword => |str| str.getStr(),
            else => {
                try std.testing.expect(false);
                unreachable;
            },
        };
        try std.testing.expect(std.mem.eql(u8, str, m));
    }

    for (s.member_4, map.get("member_4").?.list.getItems()) |m, i| {
        try std.testing.expect(m == i.float);
    }

    const lisp_map = map.get("member_6").?.dict.map;
    var iter = lisp_map.iterator();
    while (iter.next()) |kv| {
        const key = kv.key_ptr.string.getStr();
        const val = s.member_6.get(key).?;
        try std.testing.expect(val == kv.value_ptr.int);
    }
}

test "local envs" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    var script1 = interpreter.createScript();
    var script2 = interpreter.createScript();

    _ = try script1.re("(def x 3)");
    _ = try script1.re("x");

    _ = try script2.re("(def y 4)");
    _ = try script2.re("y");

    // check that y does not exist on script 1
    try std.testing.expectError(errors.LispError.SymbolNotFound, script1.re("y"));
    // check that x does not exist on script 2
    try std.testing.expectError(errors.LispError.SymbolNotFound, script2.re("x"));
}

test "lisp mal" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    var script = interpreter.createScript();
    for ([_][]const u8{
        "src/test-files/env.lisp",
        "src/test-files/eval.lisp",
        "src/test-files/if_fn_do.lisp",
        "src/test-files/enum.lisp",
        "src/test-files/atoms.lisp",
        "src/test-files/quote.lisp",
        "src/test-files/macros.lisp",
        "src/test-files/try.lisp",
        "src/test-files/tco.lisp",
    }) |filename| {
        std.debug.print("Testing {s}\n", .{filename});
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(buffer);

        _ = try file.readAll(buffer);

        var it = std.mem.splitScalar(u8, buffer, '\n');
        var i: usize = 0;
        while (it.next()) |line| {
            i += 1;
            if (line.len == 0) {
                continue;
            }

            const ret = script.re(line) catch {
                std.debug.print("ERR file {s} line {}: {s}\n", .{ filename, i, script.err_ctx.buffer.items });
                try std.testing.expect(false);
                return;
            };
            std.testing.expect(ret.eql(LispType.lisp_true)) catch {
                const str = try ret.toStringFull(allocator);
                defer allocator.free(str);
                std.debug.print("ERR file {s} line {}: return value {s}\n", .{ filename, i, str });
                try std.testing.expect(false);
            };
        }
    }
}
