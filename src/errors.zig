const std = @import("std");

pub const LispError = error{
    UnhashableType,
    WrongNumberOfArguments,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn wrongNumberOfArguments(self: *Self, expected: usize, actual: usize) LispError {
        self.clear();
        std.fmt.format(self.buffer.writer(self.allocator), "Wrong number of arguments, expected {}, got {}", .{ expected, actual });
        return LispError.WrongNumberOfArguments;
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
