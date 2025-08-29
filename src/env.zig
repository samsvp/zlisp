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
    atoms: std.ArrayList([]const u8),
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
        self.arena.deinit();
    }

    pub fn initFromParent(parent: *Self) *Self {
        var env = init(parent.arena.allocator());
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

    /// The root env is the environment before the global env
    /// or the global env if parent == null
    pub fn getRoot(self: *Self) *Self {
        var root = self;
        while (root.parent) |p| {
            if (p.parent == null) {
                return root;
            }

            root = p;
        }
        return root;
    }

    /// The global env is the innermost env
    pub fn getGlobal(self: *Self) *Self {
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
        self.mapping.ensureUnusedCapacity(self.arena.allocator(), 1) catch outOfMemory();
        return self.putAssumeCapacity(key, val);
    }

    pub fn putClone(self: *Self, key: []const u8, val: LispType) LispType {
        self.mapping.ensureUnusedCapacity(self.arena.allocator(), 1) catch outOfMemory();
        const val_clone = val.clone(self.arena.allocator());
        return self.putAssumeCapacity(key, val_clone);
    }

    pub fn putAssumeCapacity(self: *Self, key: []const u8, val: LispType) LispType {
        const allocator = self.arena.allocator();
        const key_owned = std.mem.Allocator.dupe(allocator, u8, key) catch outOfMemory();
        if (val == .atom) {
            self.atoms.append(self.arena.allocator(), key_owned) catch outOfMemory();
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
        const allocator = self.arena.allocator();

        // builtins
        self.mapping.put(allocator, "def", LispType.Function.createBuiltin(allocator, core.def)) catch outOfMemory();
        self.mapping.put(allocator, "defmacro", LispType.Function.createBuiltin(allocator, core.defmacro)) catch outOfMemory();
        self.mapping.put(allocator, "if", LispType.Function.createBuiltin(allocator, core.if_)) catch outOfMemory();
        self.mapping.put(allocator, "fn", LispType.Function.createBuiltin(allocator, core.fn_)) catch outOfMemory();
        self.mapping.put(allocator, "do", LispType.Function.createBuiltin(allocator, core.do)) catch outOfMemory();
        self.mapping.put(allocator, "let", LispType.Function.createBuiltin(allocator, core.let)) catch outOfMemory();
        self.mapping.put(allocator, "quote", LispType.Function.createBuiltin(allocator, core.quote)) catch outOfMemory();
        self.mapping.put(allocator, "quasiquote", LispType.Function.createBuiltin(allocator, core.quasiquote)) catch outOfMemory();
        self.mapping.put(allocator, "eval", LispType.Function.createBuiltin(allocator, core.evalWrapper)) catch outOfMemory();
        self.mapping.put(allocator, "try", LispType.Function.createBuiltin(allocator, core.try_)) catch outOfMemory();
        self.mapping.put(allocator, "throw", LispType.Function.createBuiltin(allocator, core.throw)) catch outOfMemory();

        // functions
        self.mapping.put(allocator, "help", LispType.Function.createBuiltin(allocator, lisp_std.help)) catch outOfMemory();

        // comparison
        self.mapping.put(allocator, "=", LispType.Function.createBuiltin(allocator, lisp_std.eql)) catch outOfMemory();
        self.mapping.put(allocator, "!=", LispType.Function.createBuiltin(allocator, lisp_std.notEql)) catch outOfMemory();
        self.mapping.put(allocator, "<", LispType.Function.createBuiltin(allocator, lisp_std.less)) catch outOfMemory();
        self.mapping.put(allocator, "<=", LispType.Function.createBuiltin(allocator, lisp_std.lessEql)) catch outOfMemory();
        self.mapping.put(allocator, ">", LispType.Function.createBuiltin(allocator, lisp_std.bigger)) catch outOfMemory();
        self.mapping.put(allocator, ">=", LispType.Function.createBuiltin(allocator, lisp_std.biggerEql)) catch outOfMemory();
        self.mapping.put(allocator, "not", LispType.Function.createBuiltin(allocator, lisp_std.not)) catch outOfMemory();

        // math
        self.mapping.put(allocator, "+", LispType.Function.createBuiltin(allocator, lisp_std.add)) catch outOfMemory();
        self.mapping.put(allocator, "-", LispType.Function.createBuiltin(allocator, lisp_std.sub)) catch outOfMemory();
        self.mapping.put(allocator, "*", LispType.Function.createBuiltin(allocator, lisp_std.mul)) catch outOfMemory();
        self.mapping.put(allocator, "/", LispType.Function.createBuiltin(allocator, lisp_std.div)) catch outOfMemory();

        // list / vector
        self.mapping.put(allocator, "map", LispType.Function.createBuiltin(allocator, lisp_std.map)) catch outOfMemory();
        self.mapping.put(allocator, "nth", LispType.Function.createBuiltin(allocator, lisp_std.nth)) catch outOfMemory();
        self.mapping.put(allocator, "head", LispType.Function.createBuiltin(allocator, lisp_std.head)) catch outOfMemory();
        self.mapping.put(allocator, "first", LispType.Function.createBuiltin(allocator, lisp_std.head)) catch outOfMemory();
        self.mapping.put(allocator, "tail", LispType.Function.createBuiltin(allocator, lisp_std.tail)) catch outOfMemory();
        self.mapping.put(allocator, "rest", LispType.Function.createBuiltin(allocator, lisp_std.tail)) catch outOfMemory();
        self.mapping.put(allocator, "empty?", LispType.Function.createBuiltin(allocator, lisp_std.emptyQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "count", LispType.Function.createBuiltin(allocator, lisp_std.count)) catch outOfMemory();
        self.mapping.put(allocator, "cons", LispType.Function.createBuiltin(allocator, lisp_std.cons)) catch outOfMemory();
        self.mapping.put(allocator, "concat", LispType.Function.createBuiltin(allocator, lisp_std.concat)) catch outOfMemory();

        // atoms
        self.mapping.put(allocator, "atom", LispType.Function.createBuiltin(allocator, lisp_std.atom)) catch outOfMemory();
        self.mapping.put(allocator, "deref", LispType.Function.createBuiltin(allocator, lisp_std.deref)) catch outOfMemory();
        self.mapping.put(allocator, "reset!", LispType.Function.createBuiltin(allocator, lisp_std.resetBang)) catch outOfMemory();
        self.mapping.put(allocator, "swap!", LispType.Function.createBuiltin(allocator, lisp_std.swapBang)) catch outOfMemory();

        // dict
        self.mapping.put(allocator, "assoc", LispType.Function.createBuiltin(allocator, lisp_std.assoc)) catch outOfMemory();
        self.mapping.put(allocator, "dissoc", LispType.Function.createBuiltin(allocator, lisp_std.dissoc)) catch outOfMemory();
        self.mapping.put(allocator, "get", LispType.Function.createBuiltin(allocator, lisp_std.get)) catch outOfMemory();
        self.mapping.put(allocator, "contains?", LispType.Function.createBuiltin(allocator, lisp_std.contains)) catch outOfMemory();
        self.mapping.put(allocator, "keys", LispType.Function.createBuiltin(allocator, lisp_std.keys)) catch outOfMemory();
        self.mapping.put(allocator, "vals", LispType.Function.createBuiltin(allocator, lisp_std.values)) catch outOfMemory();

        // type conversions
        self.mapping.put(allocator, "list", LispType.Function.createBuiltin(allocator, lisp_std.list)) catch outOfMemory();
        self.mapping.put(allocator, "vec", LispType.Function.createBuiltin(allocator, lisp_std.vec)) catch outOfMemory();
        self.mapping.put(allocator, "vector", LispType.Function.createBuiltin(allocator, lisp_std.vector)) catch outOfMemory();
        self.mapping.put(allocator, "dict", LispType.Function.createBuiltin(allocator, lisp_std.dict)) catch outOfMemory();
        self.mapping.put(allocator, "str", LispType.Function.createBuiltin(allocator, lisp_std.str)) catch outOfMemory();
        self.mapping.put(allocator, "symbol", LispType.Function.createBuiltin(allocator, lisp_std.symbol)) catch outOfMemory();
        self.mapping.put(allocator, "keyword", LispType.Function.createBuiltin(allocator, lisp_std.keyword)) catch outOfMemory();

        // type checks
        self.mapping.put(allocator, "atom?", LispType.Function.createBuiltin(allocator, lisp_std.atomQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "nil?", LispType.Function.createBuiltin(allocator, lisp_std.nilQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "bool?", LispType.Function.createBuiltin(allocator, lisp_std.boolQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "int?", LispType.Function.createBuiltin(allocator, lisp_std.intQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "float?", LispType.Function.createBuiltin(allocator, lisp_std.floatQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "symbol?", LispType.Function.createBuiltin(allocator, lisp_std.symbolQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "keyword?", LispType.Function.createBuiltin(allocator, lisp_std.keywordQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "list?", LispType.Function.createBuiltin(allocator, lisp_std.listQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "vector?", LispType.Function.createBuiltin(allocator, lisp_std.vectorQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "dict?", LispType.Function.createBuiltin(allocator, lisp_std.dictQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "sequential?", LispType.Function.createBuiltin(allocator, lisp_std.sequentialQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "true?", LispType.Function.createBuiltin(allocator, lisp_std.trueQuestion)) catch outOfMemory();
        self.mapping.put(allocator, "false?", LispType.Function.createBuiltin(allocator, lisp_std.falseQuestion)) catch outOfMemory();

        // misc
        self.mapping.put(allocator, "slurp", LispType.Function.createBuiltin(allocator, lisp_std.slurp)) catch outOfMemory();
        self.mapping.put(allocator, "read-str", LispType.Function.createBuiltin(allocator, lisp_std.readStr)) catch outOfMemory();
        self.mapping.put(allocator, "load-file", LispType.Function.createBuiltin(allocator, lisp_std.loadFile)) catch outOfMemory();
        self.mapping.put(allocator, "apply", LispType.Function.createBuiltin(allocator, lisp_std.apply)) catch outOfMemory();

        // custom enum
        self.mapping.put(allocator, "enum-init", LispType.Function.createBuiltin(allocator, lisp_std.enumInit)) catch outOfMemory();
        self.mapping.put(allocator, "enum-selected", LispType.Function.createBuiltin(allocator, lisp_std.enumSelected)) catch outOfMemory();
        self.mapping.put(allocator, "enum-index", LispType.Function.createBuiltin(allocator, lisp_std.enumIndex)) catch outOfMemory();
        self.mapping.put(allocator, "enum-set-selected", LispType.Function.createBuiltin(allocator, lisp_std.enumSetSelected)) catch outOfMemory();
        self.mapping.put(allocator, "enum-set-index", LispType.Function.createBuiltin(allocator, lisp_std.enumSetIndex)) catch outOfMemory();

        self.mapping.put(allocator, "->", LispType.Function.createBuiltin(allocator, lisp_std.arrowFirst)) catch outOfMemory();
        self.mapping.put(allocator, "->>", LispType.Function.createBuiltin(allocator, lisp_std.arrowLast)) catch outOfMemory();

        return self;
    }
};
