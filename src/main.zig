const std = @import("std");
const Linenoise = @import("linenoize").Linenoise;
const Interpreter = @import("interpreter.zig").Interpreter;
const LispType = @import("types.zig").LispType;

const S = struct {
    member_1: i32,
    member_2: []const u8,
    member_3: f32,
    member_4: []const f32,
    member_5: [][]const u8,
    member_6: std.StringHashMapUnmanaged(i32),

    pub fn clone(self: S, _: std.mem.Allocator) S {
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

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();
    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    var map = std.StringHashMapUnmanaged(LispType).empty;
    defer map.deinit(allocator);

    // Insert values (simulate parsed data)
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
    std.debug.print("{}, {s} {}\n", .{ s.member_1, s.member_2, s.member_3 });
    for (s.member_5) |m| {
        std.debug.print("{s}\n", .{m});
    }
    for (s.member_4) |m| {
        std.debug.print("{}\n", .{m});
    }
    var iter = s.member_6.iterator();
    while (iter.next()) |kv| {
        std.debug.print("{s}: {}\n", .{ kv.key_ptr.*, kv.value_ptr.* });
    }

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    ln.history.load("history.txt") catch {};
    defer ln.history.save("history.txt") catch |err| {
        std.debug.print("Failed to print history {any}\n", .{err});
    };

    const stdout = std.io.getStdOut().writer();
    while (try ln.linenoise("user> ")) |input| {
        defer allocator.free(input);
        const res = interpreter.rep(input) catch |err| {
            try stdout.print("{any}\n", .{err});
            continue;
        };

        try stdout.print("{s}\n", .{res});
        try ln.history.add(input);
    }
}

test {
    _ = @import("tests.zig");
}
