const std = @import("std");
const eval = @import("eval.zig");
const LispType = @import("types.zig").LispType;
const core = @import("core.zig");
const outOfMemory = @import("utils.zig").outOfMemory;

pub const Env = struct {
    // arena to hold the clones which the mapping will hold
    arena: std.heap.ArenaAllocator,
    // mapping will get all of its allocations from the arena child allocator
    mapping: std.StringArrayHashMapUnmanaged(LispType),
    // keep track of all atoms, as they need to clean up their values once the
    // environment goes out of scope.
    atoms: std.ArrayListUnmanaged([]const u8),
    parent: ?*Self,

    const Self = @This();

    pub fn init(base_allocator: std.mem.Allocator) *Self {
        var arena = std.heap.ArenaAllocator.init(base_allocator);
        const env = arena.allocator().create(Self) catch unreachable;
        env.* = .{
            .arena = arena,
            .atoms = .{},
            .mapping = .{},
            .parent = null,
        };
        return env;
    }

    pub fn deinit(self: *Self) void {
        self.atoms.deinit(self.arena.child_allocator);
        self.mapping.deinit(self.arena.child_allocator);
        self.arena.deinit();
    }

    pub fn initFromParent(parent: *Self) *Self {
        var env = init(parent.arena.child_allocator);
        env.parent = parent;
        return env;
    }

    pub fn get(self: Self, key: []const u8) ?LispType {
        return self.mapping.get(key) orelse {
            if (self.parent) |parent| {
                return parent.get(key);
            }
            return null;
        };
    }

    pub fn getPtr(self: Self, key: []const u8) ?*LispType {
        return self.mapping.getPtr(key) orelse {
            if (self.parent) |parent| {
                return parent.getPtr(key);
            }
            return null;
        };
    }

    pub fn getRoot(self: *Self) *Self {
        var root = self;
        while (root.parent) |p| {
            root = p;
        }
        return root;
    }

    pub fn isRoot(self: Self) bool {
        return self.parent == null;
    }

    pub fn put(self: *Self, key: []const u8, val: LispType) LispType {
        self.mapping.ensureUnusedCapacity(self.arena.child_allocator, 1) catch outOfMemory();
        return self.putAssumeCapacity(key, val);
    }

    pub fn putClone(self: *Self, key: []const u8, val: LispType) LispType {
        self.mapping.ensureUnusedCapacity(self.arena.child_allocator, 1) catch outOfMemory();
        const val_clone = val.clone(self.arena.allocator());
        return self.putAssumeCapacity(key, val_clone);
    }

    pub fn putAssumeCapacity(self: *Self, key: []const u8, val: LispType) LispType {
        const allocator = self.arena.allocator();
        const key_owned = std.mem.Allocator.dupe(allocator, u8, key) catch outOfMemory();
        if (val == .atom) {
            self.atoms.append(self.arena.child_allocator, key_owned) catch outOfMemory();
        }
        self.mapping.putAssumeCapacity(key_owned, val);
        return val;
    }

    pub fn clone(self: *Self, allocator: std.mem.Allocator) *Self {
        var env = if (self.parent) |parent| initFromParent(parent) else init(allocator);
        env.mapping.ensureTotalCapacity(allocator, self.mapping.count()) catch outOfMemory();

        var iter = self.mapping.iterator();
        while (iter.next()) |entry| {
            _ = env.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.*);
        }
        return env;
    }

    pub fn setFunctions(self: *Self) *Self {
        const allocator = self.arena.child_allocator;

        self.mapping.put(allocator, "def", .{ .function = .{ .builtin = eval.def } }) catch outOfMemory();
        self.mapping.put(allocator, "defmacro", .{ .function = .{ .builtin = eval.defmacro } }) catch outOfMemory();
        self.mapping.put(allocator, "if", .{ .function = .{ .builtin = eval.if_ } }) catch outOfMemory();
        self.mapping.put(allocator, "fn", .{ .function = .{ .builtin = eval.fn_ } }) catch outOfMemory();
        self.mapping.put(allocator, "let", .{ .function = .{ .builtin = eval.let } }) catch outOfMemory();
        self.mapping.put(allocator, "quote", .{ .function = .{ .builtin = eval.quote } }) catch outOfMemory();
        self.mapping.put(allocator, "quasiquote", .{ .function = .{ .builtin = eval.quasiquote } }) catch outOfMemory();
        self.mapping.put(allocator, "eval", .{ .function = .{ .builtin = eval.evalWrapper } }) catch outOfMemory();
        self.mapping.put(allocator, "try", .{ .function = .{ .builtin = eval.try_ } }) catch outOfMemory();
        self.mapping.put(allocator, "throw", .{ .function = .{ .builtin = eval.throw } }) catch outOfMemory();

        self.mapping.put(allocator, "=", .{ .function = .{ .builtin = core.eql } }) catch outOfMemory();
        self.mapping.put(allocator, "!=", .{ .function = .{ .builtin = core.notEql } }) catch outOfMemory();
        self.mapping.put(allocator, "<", .{ .function = .{ .builtin = core.less } }) catch outOfMemory();
        self.mapping.put(allocator, "<=", .{ .function = .{ .builtin = core.lessEql } }) catch outOfMemory();
        self.mapping.put(allocator, ">", .{ .function = .{ .builtin = core.bigger } }) catch outOfMemory();
        self.mapping.put(allocator, ">=", .{ .function = .{ .builtin = core.biggerEql } }) catch outOfMemory();

        self.mapping.put(allocator, "+", .{ .function = .{ .builtin = core.add } }) catch outOfMemory();
        self.mapping.put(allocator, "-", .{ .function = .{ .builtin = core.sub } }) catch outOfMemory();
        self.mapping.put(allocator, "*", .{ .function = .{ .builtin = core.mul } }) catch outOfMemory();
        self.mapping.put(allocator, "/", .{ .function = .{ .builtin = core.div } }) catch outOfMemory();

        self.mapping.put(allocator, "list", .{ .function = .{ .builtin = core.list } }) catch outOfMemory();
        self.mapping.put(allocator, "list?", .{ .function = .{ .builtin = core.listQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "empty", .{ .function = .{ .builtin = core.emptyQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "count", .{ .function = .{ .builtin = core.count } }) catch outOfMemory();
        self.mapping.put(allocator, "cons", .{ .function = .{ .builtin = core.cons } }) catch outOfMemory();
        self.mapping.put(allocator, "concat", .{ .function = .{ .builtin = core.concat } }) catch outOfMemory();

        self.mapping.put(allocator, "atom", .{ .function = .{ .builtin = core.atom } }) catch outOfMemory();
        self.mapping.put(allocator, "atom?", .{ .function = .{ .builtin = core.atomQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "deref", .{ .function = .{ .builtin = core.deref } }) catch outOfMemory();
        self.mapping.put(allocator, "reset!", .{ .function = .{ .builtin = core.resetBang } }) catch outOfMemory();

        self.mapping.put(allocator, "str", .{ .function = .{ .builtin = core.str } }) catch outOfMemory();
        self.mapping.put(allocator, "slurp", .{ .function = .{ .builtin = core.slurp } }) catch outOfMemory();
        self.mapping.put(allocator, "readStr", .{ .function = .{ .builtin = core.readStr } }) catch outOfMemory();

        return self;
    }
};
