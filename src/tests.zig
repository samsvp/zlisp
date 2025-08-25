const std = @import("std");
const LispType = @import("types.zig").LispType;
const Interpreter = @import("interpreter.zig").Interpreter;

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

test "lisp mal" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    for ([_][]const u8{
        "src/test-files/env.lisp",
        "src/test-files/eval.lisp",
        "src/test-files/if_fn_do.lisp",
        "src/test-files/tco.lisp",
        "src/test-files/enum.lisp",
        "src/test-files/atoms.lisp",
        "src/test-files/quote.lisp",
        "src/test-files/macros.lisp",
        "src/test-files/try.lisp",
    }) |filename| {
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

            const ret = interpreter.re(line) catch {
                std.debug.print("ERR file {s} line {}: {s}\n", .{ filename, i, interpreter.err_ctx.buffer.items });
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
