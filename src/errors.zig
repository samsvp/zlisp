const std = @import("std");

pub const LispError = error{
    UnhashableType,
    WrongNumberOfArguments,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) Context {
        return Context{
            .allocator = allocator,
        };
    }

    pub fn wrongNumberOfArguments(self: *Context, expected: usize, actual: usize) LispError {
        self.clear();
        std.fmt.format(self.buffer.writer(self.allocator), "Wrong number of arguments, expected {}, got {}", .{ expected, actual });
        return LispError.WrongNumberOfArguments;
    }

    pub fn getMessage(self: Context) []const u8 {
        return self.buffer.items;
    }

    pub fn clear(self: *Context) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn deinit(self: *Context) void {
        self.buffer.deinit(self.allocator);
    }
};
