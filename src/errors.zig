const std = @import("std");
const ParserError = @import("reader.zig").ParserError;
const outOfMemory = @import("utils.zig").outOfMemory;

pub const LispError = error{
    DivisionByZero,
    ParserError,
    WrongArgumentType,
    SymbolNotFound,
    UnhashableType,
    WrongNumberOfArguments,

    FileDoesNotExist,
    IOError,
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

    pub fn atLeastNArguments(self: *Self, at_least: usize) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Wrong number of arguments, expected at least {} arguments",
            .{at_least},
        ) catch outOfMemory();
        return LispError.WrongNumberOfArguments;
    }

    pub fn divisionByZero(self: *Self) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Division by zero",
            .{},
        ) catch outOfMemory();
        return LispError.DivisionByZero;
    }

    pub fn fileDoesNotExit(self: *Self, filename: []const u8) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "File {s} does not exist",
            .{filename},
        ) catch outOfMemory();
        return LispError.FileDoesNotExist;
    }

    pub fn ioError(self: *Self) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "IO Error",
            .{},
        ) catch outOfMemory();
        return LispError.IOError;
    }

    pub fn parserError(self: *Self, err: ParserError) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Parser error {any}",
            .{err},
        ) catch outOfMemory();
        return LispError.ParserError;
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

    pub fn wrongNumberOfArgumentsTwoChoices(
        self: *Self,
        expected_1: usize,
        expected_2: usize,
        actual: usize,
    ) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Wrong number of arguments, expected {} or {} arguments, got {}.",
            .{ expected_1, expected_2, actual },
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
