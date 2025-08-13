const std = @import("std");
const outOfMemory = @import("utils.zig").outOfMemory;

pub const LispError = error{
    WrongArgumentType,
    SymbolNotFound,
    UnhashableType,
    WrongNumberOfArguments,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const buffer = std.ArrayListUnmanaged(u8).initCapacity(allocator, 500) catch outOfMemory();
        return Self{
            .allocator = allocator,
            .buffer = buffer,
        };
    }

    pub fn wrongNumberOfArguments(self: *Self, expected: usize, actual: usize) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Wrong number of arguments, expected {}, got {}.",
            .{ expected, actual },
        ) catch
            outOfMemory();
        return LispError.WrongNumberOfArguments;
    }

    pub fn symbolNotFound(self: *Self, name: []const u8) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Symbol {s} not found.",
            .{name},
        ) catch
            outOfMemory();
        return LispError.SymbolNotFound;
    }

    pub fn wrongParameterType(self: *Self, arg_name: []const u8, expected: []const u8) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "{s} must be of type {s}.",
            .{ arg_name, expected },
        ) catch outOfMemory();
        return LispError.WrongArgumentType;
    }

    pub fn getMessage(self: Self) []const u8 {
        return self.buffer.items;
    }

    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }
};
