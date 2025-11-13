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
    @"if",
    @"fn",
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
    try chunk.emitByte(allocator, @intCast(args.len), line);
}

fn compileIf(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len != 2 and args.len != 3) {
        try err_ctx.setMsgWithLine(allocator, "if", "Expected 2 or 3 arguments, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    // place the expr result on the stack
    try compileToken(allocator, chunk, args[0], err_ctx);
    const jump_false_index = try chunk.emitJumpIfFalse(allocator, 0, line);
    // compile the clauses
    try compileToken(allocator, chunk, args[1], err_ctx);
    chunk.replaceJump(jump_false_index, @intCast(chunk.code.items.len - jump_false_index));

    const jump_index = try chunk.emitJump(allocator, 0, line);
    if (args.len == 2) {
        _ = try chunk.emitConstant(allocator, .nil, line);
    } else {
        try compileToken(allocator, chunk, args[2], err_ctx);
    }

    chunk.replaceJump(jump_index, @intCast(chunk.code.items.len - jump_index - 3));
}

fn compileFn(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len > 5 or args.len < 3) {
        try err_ctx.setMsgWithLine(allocator, "fn", "Expected 3 to 5 arguments, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    if (args[0].kind != .atom and args[0].kind.atom != .symbol) {
        try err_ctx.setMsgWithLine(allocator, "fn", "Expected function name.", .{}, args[0].line);
        return Errors.WrongArgumentType;
    }

    const name = args[0].kind.atom.symbol;

    const help = switch (args[1].kind) {
        .atom => |v| if (v == .obj and v.obj.kind == .string)
            v.obj.as(Obj.String).items
        else
            "",
        else => "",
    };

    var fn_chunk = try allocator.create(Chunk);
    fn_chunk.* = Chunk.empty;

    const fn_args = switch (args[args.len - 2].kind) {
        .vector => |vs| blk: {
            const fn_args = try allocator.alloc([]const u8, vs.items.len);
            for (vs.items, 0..) |v, i| {
                const arg_name =
                    if (v.kind == .atom and v.kind.atom == .symbol)
                        v.kind.atom.symbol
                    else {
                        try err_ctx.setMsgWithLine(
                            allocator,
                            "fn",
                            "Function arguments must be symbols",
                            .{},
                            args[args.len - 2].line,
                        );
                        return Errors.WrongArgumentType;
                    };

                try fn_chunk.emitDefLocal(allocator, arg_name, v.line);
                fn_args[i] = arg_name;
            }
            break :blk fn_args;
        },
        else => {
            try err_ctx.setMsgWithLine(allocator, "fn", "Arguments must be a list of symbols.", .{}, line);
            return Errors.WrongArgumentType;
        },
    };

    if (args[args.len - 1].kind != .list) {
        try err_ctx.setMsgWithLine(allocator, "fn", "Function body must be list.", .{}, args[args.len - 1].line);
        return Errors.WrongArgumentType;
    }

    try compileToChunk(allocator, args[args.len].kind.list, chunk, err_ctx);

    const func = try Obj.Function.init(allocator, chunk, @intCast(fn_args.len), name, help);
    _ = try chunk.emitConstant(allocator, .{ .obj = &func.obj }, line);
    try chunk.emitDefGlobal(allocator, name, line);
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

    const args = list.items[1..];
    if (atom == .symbol) if (std.meta.stringToEnum(Constants, atom.symbol)) |c| {
        switch (c) {
            .@"+" => try compileOp(allocator, chunk, .add, args, line, err_ctx),
            .@"-" => try compileOp(allocator, chunk, .subtract, args, line, err_ctx),
            .@"*" => try compileOp(allocator, chunk, .multiply, args, line, err_ctx),
            .@"/" => try compileOp(allocator, chunk, .divide, args, line, err_ctx),
            .@"if" => try compileIf(allocator, chunk, args, line, err_ctx),
            .@"fn" => try compileFn(allocator, chunk, args, line, err_ctx),
            .def => try compileDef(allocator, chunk, args, line, err_ctx),
        }
        return;
    };

    // compile the atom last
    try compileArgs(allocator, chunk, list.items[1..], err_ctx);
    try compileAtom(allocator, chunk, atom, line);
    try chunk.append(allocator, .call, line);
    try chunk.emitByte(allocator, @intCast(list.items.len - 1), line);
}

pub fn compileVector(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    vector: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    try compileArgs(allocator, chunk, vector.items, err_ctx);
    _ = line;
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
        .vector => |v| try compileVector(allocator, chunk, v, token.line, err_ctx),
    }
}

pub fn compileToChunk(
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(reader.Token),
    chunk: *Chunk,
    err_ctx: *errors.Ctx,
) !void {
    for (tokens.items, 0..) |token, i| switch (token.kind) {
        .atom => |a| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }
            _ = try compileAtom(allocator, chunk, a, token.line);
        },
        .vector => |vec| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }

            try compileVector(allocator, chunk, vec, token.line, err_ctx);
        },
        .list => |list| {
            if (list.items.len == 0 and i != tokens.items.len - 1) {
                // ignore empty list
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
}

pub fn compile(allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !*Chunk {
    var tokens = try reader.readStr(allocator, source, err_ctx);
    defer tokens.deinit(allocator);

    defer for (tokens.items) |*token| token.deinit(allocator);

    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.empty;

    try compileToChunk(allocator, tokens, chunk, err_ctx);

    return chunk;
}
