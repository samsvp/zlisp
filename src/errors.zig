const std = @import("std");
const LispType = @import("types.zig").LispType;
const ParserError = @import("reader.zig").ParserError;
const outOfMemory = @import("utils.zig").outOfMemory;

pub const LispError = error{
    DivisionByZero,
    IndexOutOfRange,
    InvalidCast,
    MissingRequiredField,
    EmptyCollection,
    MissingCatch,
    ParserError,
    WrongArgumentType,
    SymbolNotFound,
    UnhashableType,
    UserError,
    WrongNumberOfArguments,

    FileDoesNotExist,
    IOError,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const buffer = std.ArrayList(u8).initCapacity(allocator, 500) catch outOfMemory();
        return Self{
            .allocator = allocator,
            .buffer = buffer,
        };
    }

    pub fn customError(self: *Self, msg: []const u8) LispError {
        self.clear();
        self.buffer.appendSlice(self.allocator, msg) catch outOfMemory();
        return LispError.UserError;
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

    pub fn indexOutOfRange(self: *Self, index: usize, len: usize) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Index {} out of range. Collection size: {}",
            .{ index, len },
        ) catch outOfMemory();
        return LispError.IndexOutOfRange;
    }

    pub fn invalidCast(self: *Self, to_type: []const u8) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Could not convert type to {s}",
            .{to_type},
        ) catch outOfMemory();
        return LispError.InvalidCast;
    }

    pub fn emptyCollection(self: *Self) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Collection is empty",
            .{},
        ) catch outOfMemory();
        return LispError.EmptyCollection;
    }

    pub fn missingCatch(self: *Self) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Missing 'catch' keyword from 'try-catch' block",
            .{},
        ) catch outOfMemory();
        return LispError.MissingCatch;
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

    pub fn wrongNumberOfArgumentsThreeChoices(
        self: *Self,
        expected_1: usize,
        expected_2: usize,
        expected_3: usize,
        actual: usize,
    ) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Wrong number of arguments, expected {}, {} or {} arguments, got {}.",
            .{ expected_1, expected_2, expected_3, actual },
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

    pub fn unhashableType(self: *Self) LispError {
        self.clear();
        std.fmt.format(
            self.buffer.writer(self.allocator),
            "Unhashable type. Hashable types: string, int, keyword and symbol.",
            .{},
        ) catch outOfMemory();
        return LispError.UnhashableType;
    }

    pub fn toLispString(self: Self, allocator: std.mem.Allocator) LispType {
        const err_str = std.fmt.allocPrint(
            allocator,
            "ERROR: {s}",
            .{self.buffer.items},
        ) catch outOfMemory();
        return LispType.String.initString(allocator, err_str);
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
