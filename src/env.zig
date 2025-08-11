const std = @import("std");
const LispType = @import("types.zig").LispType;
const outOfMemory = @import("utils.zig").outOfMemory;

pub const Env = struct {
    mapping: std.StringHashMapUnmanaged(LispType),
    parent: ?*Self,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) *Self {
        const env = allocator.create(Self) catch unreachable;
        env.* = .{
            .mapping = .empty,
            .parent = null,
        };
        return env;
    }

    pub fn initWithParent(allocator: std.mem.Allocator, parent: *Self) *Self {
        const env = allocator.create(Self) catch unreachable;
        env.* = .{
            .mapping = .empty,
            .parent = parent,
        };
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

    pub fn isRoot(self: *Self) bool {
        return self.parent == null;
    }

    pub fn put(self: *Self, allocator: std.mem.Allocator, key: []const u8, val: LispType) void {
        const key_owned = std.mem.Allocator.dupe(allocator, u8, key) catch outOfMemory();
        self.mapping.put(allocator, key_owned, val.clone(allocator)) catch outOfMemory();
    }

    pub fn putAssumeCapacity(self: *Self, allocator: std.mem.Allocator, key: []const u8, val: LispType) void {
        const key_owned = std.mem.Allocator.dupe(allocator, u8, key) catch outOfMemory();
        self.mapping.putAssumeCapacity(key_owned, val.clone(allocator));
    }

    pub fn clone(self: *Self, allocator: std.mem.Allocator) *Self {
        var env = initWithParent(allocator, self.parent);
        env.mapping.ensureTotalCapacity(allocator, self.mapping.size) catch outOfMemory();

        var iter = self.mapping.iterator();
        while (iter.next()) |entry| {
            env.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.*);
        }
        return env;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        var iter = self.mapping.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }

        if (self.parent) |p| {
            p.deinit(allocator);
        }
    }
};
