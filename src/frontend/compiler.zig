const std = @import("std");
const errors = @import("../errors.zig");
const reader = @import("reader.zig");

const Obj = @import("../value.zig").Obj;
const Value = @import("../value.zig").Value;
const Chunk = @import("../backend/chunk.zig").Chunk;
const OpCode = @import("../backend/chunk.zig").OpCode;

pub const Errors = error{
    NonFunctionAsHeadOfList,
    WrongNumberOfArguments,
    WrongArgumentType,
};

pub const Compiler = struct {
    chunk: *Chunk,
};

const Constants = enum {
    @"+",
    @"-",
    @"*",
    @"/",
    def,
};

/// Returns false if the function is a builtin (+,-,*,/) or a true function to be called.
pub fn compileAtom(allocator: std.mem.Allocator, chunk: *Chunk, value: Value, line: usize) !void {
    switch (value) {
        .symbol => {
            // TODO! check if variable is a local
            try chunk.emitGetGlobal(allocator, value.symbol, line);
        },
        else => _ = try chunk.emitConstant(allocator, value, line),
    }
}

fn compileArgs(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    args: []const reader.Token,
    err_ctx: *errors.Ctx,
) anyerror!void {
    for (0..args.len) |i| {
        const token = args[args.len - i - 1];
        try compileToken(allocator, chunk, token, err_ctx);
    }
}

fn compileOp(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    op: OpCode,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    try compileArgs(allocator, chunk, args, err_ctx);
    try chunk.append(allocator, op, line);
    try chunk.emitByte(allocator, @intCast(args.len), 125);
}

fn compileDef(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len != 2) {
        try err_ctx.setMsgWithLine(
            allocator,
            "def",
            "Wrong number of arguments. Expected 2, got {}",
            .{args.len},
            line,
        );
        return Errors.WrongNumberOfArguments;
    }

    if (args[0].kind != .atom and args[0].kind.atom != .symbol) {
        try err_ctx.setMsgWithLine(allocator, "def", "Wrong argument type {s}.", .{@tagName(args[0].kind.atom)}, args[0].line);
        return Errors.WrongArgumentType;
    }

    try compileToken(allocator, chunk, args[1], err_ctx);
    _ = try chunk.emitConstant(allocator, args[0].kind.atom, args[0].line);
    try chunk.append(allocator, .def_global, line);
}

pub fn compileList(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    list: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    if (list.items.len == 0) {
        const empty_list = try Obj.List.empty(allocator);
        _ = try chunk.emitConstant(allocator, .{ .obj = &empty_list.obj }, line);
        return;
    }

    const first = list.items[0];
    if (first.kind != .atom) {
        // TODO! The first element could be a list if it defines an anonymous function
        err_ctx.line = line;
        try err_ctx.setMsg(allocator, "COMPILE", "List first element must be function.", .{});
        return Errors.NonFunctionAsHeadOfList;
    }

    const atom = first.kind.atom;
    if (atom != .symbol) {
        err_ctx.line = line;
        try err_ctx.setMsg(allocator, "COMPILE", "List first element must be function.", .{});
        return Errors.NonFunctionAsHeadOfList;
    }

    if (atom == .symbol) if (std.meta.stringToEnum(Constants, atom.symbol)) |c| {
        switch (c) {
            .@"+" => try compileOp(allocator, chunk, .add, list.items[1..], line, err_ctx),
            .@"-" => try compileOp(allocator, chunk, .subtract, list.items[1..], line, err_ctx),
            .@"*" => try compileOp(allocator, chunk, .multiply, list.items[1..], line, err_ctx),
            .@"/" => try compileOp(allocator, chunk, .divide, list.items[1..], line, err_ctx),
            .def => try compileDef(allocator, chunk, list.items[1..], line, err_ctx),
        }
        return;
    };

    // compile the atom last
    try compileArgs(allocator, chunk, list.items[1..], err_ctx);
    try compileAtom(allocator, chunk, atom, line);
    try chunk.append(allocator, .call, 125);
    try chunk.emitByte(allocator, @intCast(list.items.len - 1), 125);
}

pub fn compileToken(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    token: reader.Token,
    err_ctx: *errors.Ctx,
) !void {
    switch (token.kind) {
        .atom => |v| try compileAtom(allocator, chunk, v, token.line),
        .list => |l| try compileList(allocator, chunk, l, token.line, err_ctx),
    }
}

pub fn compile(allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !*Chunk {
    var tokens = try reader.readStr(allocator, source, err_ctx);
    defer tokens.deinit(allocator);

    defer for (tokens.items) |*token| token.deinit(allocator);

    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.empty;
    for (tokens.items, 0..) |token, i| switch (token.kind) {
        .atom => |a| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }
            _ = try compileAtom(allocator, chunk, a, token.line);
        },
        .list => |list| {
            if (list.items.len == 0 and i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }

            try compileList(allocator, chunk, list, token.line, err_ctx);
            // pop the last statement value
            if (i != tokens.items.len - 1) {
                try chunk.append(allocator, .pop, 0);
            }
        },
    };

    try chunk.append(allocator, .ret, 0);
    return chunk;
}
