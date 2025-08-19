const std = @import("std");
const core = @import("core.zig");
const LispType = @import("types.zig").LispType;
const lisp_std = @import("lisp_std.zig");
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

        // builtins
        self.mapping.put(allocator, "def", .{ .function = .{ .builtin = core.def } }) catch outOfMemory();
        self.mapping.put(allocator, "defmacro", .{ .function = .{ .builtin = core.defmacro } }) catch outOfMemory();
        self.mapping.put(allocator, "if", .{ .function = .{ .builtin = core.if_ } }) catch outOfMemory();
        self.mapping.put(allocator, "fn", .{ .function = .{ .builtin = core.fn_ } }) catch outOfMemory();
        self.mapping.put(allocator, "do", .{ .function = .{ .builtin = core.do } }) catch outOfMemory();
        self.mapping.put(allocator, "let", .{ .function = .{ .builtin = core.let } }) catch outOfMemory();
        self.mapping.put(allocator, "quote", .{ .function = .{ .builtin = core.quote } }) catch outOfMemory();
        self.mapping.put(allocator, "quasiquote", .{ .function = .{ .builtin = core.quasiquote } }) catch outOfMemory();
        self.mapping.put(allocator, "eval", .{ .function = .{ .builtin = core.evalWrapper } }) catch outOfMemory();
        self.mapping.put(allocator, "try", .{ .function = .{ .builtin = core.try_ } }) catch outOfMemory();
        self.mapping.put(allocator, "throw", .{ .function = .{ .builtin = core.throw } }) catch outOfMemory();

        // comparison
        self.mapping.put(allocator, "=", .{ .function = .{ .builtin = lisp_std.eql } }) catch outOfMemory();
        self.mapping.put(allocator, "!=", .{ .function = .{ .builtin = lisp_std.notEql } }) catch outOfMemory();
        self.mapping.put(allocator, "<", .{ .function = .{ .builtin = lisp_std.less } }) catch outOfMemory();
        self.mapping.put(allocator, "<=", .{ .function = .{ .builtin = lisp_std.lessEql } }) catch outOfMemory();
        self.mapping.put(allocator, ">", .{ .function = .{ .builtin = lisp_std.bigger } }) catch outOfMemory();
        self.mapping.put(allocator, ">=", .{ .function = .{ .builtin = lisp_std.biggerEql } }) catch outOfMemory();

        // math
        self.mapping.put(allocator, "+", .{ .function = .{ .builtin = lisp_std.add } }) catch outOfMemory();
        self.mapping.put(allocator, "-", .{ .function = .{ .builtin = lisp_std.sub } }) catch outOfMemory();
        self.mapping.put(allocator, "*", .{ .function = .{ .builtin = lisp_std.mul } }) catch outOfMemory();
        self.mapping.put(allocator, "/", .{ .function = .{ .builtin = lisp_std.div } }) catch outOfMemory();

        // list / vector
        self.mapping.put(allocator, "list", .{ .function = .{ .builtin = lisp_std.list } }) catch outOfMemory();
        self.mapping.put(allocator, "vector", .{ .function = .{ .builtin = lisp_std.vector } }) catch outOfMemory();
        self.mapping.put(allocator, "nth", .{ .function = .{ .builtin = lisp_std.nth } }) catch outOfMemory();
        self.mapping.put(allocator, "head", .{ .function = .{ .builtin = lisp_std.head } }) catch outOfMemory();
        self.mapping.put(allocator, "tail", .{ .function = .{ .builtin = lisp_std.tail } }) catch outOfMemory();
        self.mapping.put(allocator, "empty", .{ .function = .{ .builtin = lisp_std.emptyQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "count", .{ .function = .{ .builtin = lisp_std.count } }) catch outOfMemory();
        self.mapping.put(allocator, "cons", .{ .function = .{ .builtin = lisp_std.cons } }) catch outOfMemory();
        self.mapping.put(allocator, "concat", .{ .function = .{ .builtin = lisp_std.concat } }) catch outOfMemory();

        // atoms
        self.mapping.put(allocator, "atom", .{ .function = .{ .builtin = lisp_std.atom } }) catch outOfMemory();
        self.mapping.put(allocator, "deref", .{ .function = .{ .builtin = lisp_std.deref } }) catch outOfMemory();
        self.mapping.put(allocator, "reset!", .{ .function = .{ .builtin = lisp_std.resetBang } }) catch outOfMemory();
        self.mapping.put(allocator, "swap!", .{ .function = .{ .builtin = lisp_std.swapBang } }) catch outOfMemory();

        // dict
        self.mapping.put(allocator, "dict", .{ .function = .{ .builtin = lisp_std.dict } }) catch outOfMemory();
        self.mapping.put(allocator, "assoc", .{ .function = .{ .builtin = lisp_std.assoc } }) catch outOfMemory();
        self.mapping.put(allocator, "dissoc", .{ .function = .{ .builtin = lisp_std.dissoc } }) catch outOfMemory();
        self.mapping.put(allocator, "get", .{ .function = .{ .builtin = lisp_std.get } }) catch outOfMemory();
        self.mapping.put(allocator, "contains", .{ .function = .{ .builtin = lisp_std.contains } }) catch outOfMemory();
        self.mapping.put(allocator, "keys", .{ .function = .{ .builtin = lisp_std.keys } }) catch outOfMemory();
        self.mapping.put(allocator, "values", .{ .function = .{ .builtin = lisp_std.values } }) catch outOfMemory();

        // type conversions
        self.mapping.put(allocator, "str", .{ .function = .{ .builtin = lisp_std.str } }) catch outOfMemory();
        self.mapping.put(allocator, "symbol", .{ .function = .{ .builtin = lisp_std.symbol } }) catch outOfMemory();
        self.mapping.put(allocator, "keyword", .{ .function = .{ .builtin = lisp_std.keyword } }) catch outOfMemory();

        // type checks
        self.mapping.put(allocator, "atom?", .{ .function = .{ .builtin = lisp_std.atomQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "nil?", .{ .function = .{ .builtin = lisp_std.nilQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "bool?", .{ .function = .{ .builtin = lisp_std.boolQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "int?", .{ .function = .{ .builtin = lisp_std.intQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "float?", .{ .function = .{ .builtin = lisp_std.floatQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "symbol?", .{ .function = .{ .builtin = lisp_std.symbolQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "keyword?", .{ .function = .{ .builtin = lisp_std.keywordQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "list?", .{ .function = .{ .builtin = lisp_std.listQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "vector?", .{ .function = .{ .builtin = lisp_std.vectorQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "dict?", .{ .function = .{ .builtin = lisp_std.dictQuestion } }) catch outOfMemory();
        self.mapping.put(allocator, "sequential?", .{ .function = .{ .builtin = lisp_std.sequentialQuestion } }) catch outOfMemory();

        // misc
        self.mapping.put(allocator, "slurp", .{ .function = .{ .builtin = lisp_std.slurp } }) catch outOfMemory();
        self.mapping.put(allocator, "readStr", .{ .function = .{ .builtin = lisp_std.readStr } }) catch outOfMemory();

        return self;
    }
};
