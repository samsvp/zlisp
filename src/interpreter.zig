const std = @import("std");
const eval = @import("core.zig").eval;
const errors = @import("errors.zig");
const LispType = @import("types.zig").LispType;
const Env = @import("env.zig").Env;
const reader = @import("reader.zig");
const Script = @import("script.zig").Script;
const outOfMemory = @import("utils.zig").outOfMemory;

pub const Interpreter = struct {
    arena: std.heap.ArenaAllocator,
    env: *Env,
    scripts: std.ArrayList(*Script),

    const Self = @This();

    pub fn init(base_allocator: std.mem.Allocator) Self {
        const arena = std.heap.ArenaAllocator.init(base_allocator);
        const env = Env.init(base_allocator).setFunctions();

        var self = Self{
            .arena = arena,
            .env = env,
            .scripts = .{},
        };

        // load std lib
        const std_lisp_str = @embedFile("std.lisp");
        const src = std.fmt.allocPrint(base_allocator, "(eval (do {s} nil))", .{std_lisp_str}) catch outOfMemory();
        defer base_allocator.free(src);

        const allocator = self.arena.allocator();
        const val = reader.readStr(allocator, src) catch unreachable;

        var err_ctx = errors.Context.init(base_allocator);
        defer err_ctx.deinit();
        _ = eval(allocator, val, env, &err_ctx) catch unreachable;

        return self;
    }

    pub fn addBuiltin(self: *Self, name: []const u8, b: LispType.BuiltinFunc) void {
        self.env.addBuiltint(name, b);
    }

    pub fn createScript(self: *Self) *Script {
        const allocator = self.arena.child_allocator;
        const script = allocator.create(Script) catch outOfMemory();
        script.* = Script.init(allocator, self.env);
        self.scripts.append(self.arena.child_allocator, script) catch outOfMemory();
        return script;
    }

    pub fn deinit(self: *Self) void {
        for (self.scripts.items) |s| {
            s.deinit();
            self.arena.child_allocator.destroy(s);
        }
        self.scripts.deinit(self.arena.child_allocator);
        self.env.deinit();
        self.arena.deinit();
    }
};
