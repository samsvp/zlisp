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

pub const Locals = struct {
    offset: u16,
    names: std.StringArrayHashMapUnmanaged(u16),
    node: std.SinglyLinkedList.Node,

    pub const empty: Locals = .{
        .offset = 0,
        .names = .empty,
        .node = .{},
    };

    pub fn createNext(self: *Locals) Locals {
        const size: u16 = @intCast(self.names.count());
        const next: Locals = .{
            .offset = self.offset + size,
            .names = .empty,
            .node = .{ .next = &self.node },
        };
        return next;
    }

    pub fn deinit(self: *Locals, allocator: std.mem.Allocator) void {
        self.names.deinit(allocator);
    }

    pub fn put(self: *Locals, allocator: std.mem.Allocator, name: []const u8) !void {
        const size: u16 = @intCast(self.names.count());
        _ = try self.names.getOrPutValue(allocator, name, self.offset + size);
    }

    pub fn get(self: *Locals, name: []const u8) ?u16 {
        var node: ?*std.SinglyLinkedList.Node = &self.node;
        while (node) |n| {
            var locals: *Locals = @fieldParentPtr("node", n);
            if (locals.names.get(name)) |index| {
                return index;
            }
            node = n.next;
        }
        return null;
    }
};

const Constants = enum {
    @"+",
    @"-",
    @"*",
    @"/",
    @"=",
    @"<",
    @">",
    @"<=",
    @">=",
    @"if",
    @"fn",
    list,
    def,
    not,
};

/// Returns false if the function is a builtin (+,-,*,/) or a true function to be called.
pub fn compileAtom(allocator: std.mem.Allocator, chunk: *Chunk, locals: *Locals, value: Value, line: usize) !void {
    switch (value) {
        .symbol => |s| {
            if (locals.get(s)) |index| {
                try chunk.emitGetLocal(allocator, index, line);
            } else {
                try chunk.emitGetGlobal(allocator, s, line);
            }
        },
        else => _ = try chunk.emitConstant(allocator, value, line),
    }
}

fn compileArgs(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    err_ctx: *errors.Ctx,
) anyerror!void {
    for (0..args.len) |i| {
        const token = args[args.len - i - 1];
        try compileToken(allocator, chunk, token, locals, err_ctx);
    }
}

fn compileOp(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    op: OpCode,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    try compileArgs(allocator, chunk, locals, args, err_ctx);
    try chunk.append(allocator, op, line);
    try chunk.emitByte(allocator, @intCast(args.len), line);
}

fn compileNot(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len != 1) {
        try err_ctx.setMsgWithLine(allocator, "not", "Not takes one parameter, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    const token = args[0];
    try compileToken(allocator, chunk, token, locals, err_ctx);
    try chunk.append(allocator, .not, line);
}

fn compileIf(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len != 2 and args.len != 3) {
        try err_ctx.setMsgWithLine(allocator, "if", "Expected 2 or 3 arguments, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    // place the expr result on the stack
    try compileToken(allocator, chunk, args[0], locals, err_ctx);
    const jump_false_index = try chunk.emitJumpIfFalse(allocator, 0, line);
    // compile the clauses
    try compileToken(allocator, chunk, args[1], locals, err_ctx);
    chunk.replaceJump(jump_false_index, @intCast(chunk.code.items.len - jump_false_index));

    const jump_index = try chunk.emitJump(allocator, 0, line);
    if (args.len == 2) {
        _ = try chunk.emitConstant(allocator, .nil, line);
    } else {
        try compileToken(allocator, chunk, args[2], locals, err_ctx);
    }

    chunk.replaceJump(jump_index, @intCast(chunk.code.items.len - jump_index - 3));
}

fn createArgs(
    allocator: std.mem.Allocator,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!bool {
    var is_variadic = false;
    for (args, 0..) |v, i| {
        const arg_name =
            if (v.kind == .atom and v.kind.atom == .symbol)
                v.kind.atom.symbol
            else {
                try err_ctx.setMsgWithLine(
                    allocator,
                    "fn",
                    "Function arguments must be symbols",
                    .{},
                    line,
                );
                return Errors.WrongArgumentType;
            };

        try locals.put(allocator, arg_name);

        if (i == args.len - 1) {
            is_variadic = arg_name[0] == '&';
        }
    }
    return is_variadic;
}

fn compileFn(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len > 4 or args.len < 2) {
        try err_ctx.setMsgWithLine(allocator, "fn", "Expected 2 to 4 arguments, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    const help = switch (args[0].kind) {
        .atom => |v| if (v == .obj and v.obj.kind == .string)
            v.obj.as(Obj.String).items
        else
            "",
        else => "",
    };

    var fn_chunk = try allocator.create(Chunk);
    fn_chunk.* = Chunk.empty;

    var fn_locals = locals.createNext();
    defer fn_locals.deinit(allocator);

    const is_closure = args.len >= 3 and args[args.len - 3].kind == .vector;
    if (is_closure) {
        const closure_tokens = args[args.len - 3];
        const closure_args = closure_tokens.kind.vector.items;

        _ = try createArgs(allocator, &fn_locals, closure_args, closure_tokens.line, err_ctx);
        for (closure_args) |arg| {
            try compileAtom(allocator, chunk, locals, arg.kind.atom, closure_tokens.line);
        }
    }

    const fn_args_token = args[args.len - 2];
    if (fn_args_token.kind != .vector) {
        try err_ctx.setMsgWithLine(allocator, "fn", "Function arguments must be a vector.", .{}, fn_args_token.line);
    }

    const fn_args = fn_args_token.kind.vector.items;
    const is_variadic = try createArgs(allocator, &fn_locals, fn_args, fn_args_token.line, err_ctx);

    const ast_token = args[args.len - 1];
    try compileToken(allocator, fn_chunk, ast_token, &fn_locals, err_ctx);
    try fn_chunk.append(allocator, .ret, ast_token.line);

    var func = try Obj.Function.init(allocator, fn_chunk, @intCast(fn_args.len), is_variadic, help);
    defer func.obj.deinit(allocator);

    _ = try chunk.emitConstant(allocator, .{ .obj = &func.obj }, line);

    if (is_closure) {
        try chunk.append(allocator, .create_closure, line);
        const closure_args: u16 = @intCast(args[args.len - 3].kind.vector.items.len);
        const bytes = std.mem.toBytes(closure_args);
        try chunk.emitBytes(allocator, &bytes, line);
    }
}

fn compileDef(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
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

    try compileToken(allocator, chunk, args[1], locals, err_ctx);
    _ = try chunk.emitConstant(allocator, args[0].kind.atom, args[0].line);
    try chunk.append(allocator, .def_global, line);
}

pub fn compileList(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    list: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    if (list.items.len == 0) {
        const empty_list = try Obj.List.empty(allocator);
        defer empty_list.obj.deinit(allocator);

        _ = try chunk.emitConstant(allocator, .{ .obj = &empty_list.obj }, line);
        return;
    }

    err_ctx.line = line;
    const first = list.items[0];
    switch (first.kind) {
        .list => {},
        .atom => |a| if (a != .symbol) {
            try err_ctx.setMsg(allocator, "COMPILE", "List first element must be function.", .{});
            return Errors.NonFunctionAsHeadOfList;
        },
        .vector, .hash_map => {
            try err_ctx.setMsg(allocator, "COMPILE", "List first element must be function.", .{});
            return Errors.NonFunctionAsHeadOfList;
        },
    }

    const args = list.items[1..];
    if (first.kind == .atom and first.kind.atom == .symbol) {
        if (std.meta.stringToEnum(Constants, first.kind.atom.symbol)) |c| {
            switch (c) {
                .@"+" => try compileOp(allocator, chunk, locals, .add, args, line, err_ctx),
                .@"-" => try compileOp(allocator, chunk, locals, .subtract, args, line, err_ctx),
                .@"*" => try compileOp(allocator, chunk, locals, .multiply, args, line, err_ctx),
                .@"/" => try compileOp(allocator, chunk, locals, .divide, args, line, err_ctx),
                .@"=" => try compileOp(allocator, chunk, locals, .eq, args, line, err_ctx),
                .@"<" => try compileOp(allocator, chunk, locals, .lt, args, line, err_ctx),
                .@">" => try compileOp(allocator, chunk, locals, .gt, args, line, err_ctx),
                .@"<=" => try compileOp(allocator, chunk, locals, .leq, args, line, err_ctx),
                .@">=" => try compileOp(allocator, chunk, locals, .geq, args, line, err_ctx),
                .@"if" => try compileIf(allocator, chunk, locals, args, line, err_ctx),
                .@"fn" => try compileFn(allocator, chunk, locals, args, line, err_ctx),
                .list => {
                    try compileArgs(allocator, chunk, locals, args, err_ctx);
                    try chunk.emitList(allocator, @intCast(args.len), line);
                },
                .not => try compileNot(allocator, chunk, locals, args, line, err_ctx),
                .def => try compileDef(allocator, chunk, locals, args, line, err_ctx),
            }
            return;
        }
    }

    // compile the atom last
    try compileArgs(allocator, chunk, locals, list.items[1..], err_ctx);
    switch (first.kind) {
        .atom => |atom| try compileAtom(allocator, chunk, locals, atom, line),
        .list => |l| try compileList(allocator, chunk, locals, l, line, err_ctx),
        else => unreachable,
    }
    try chunk.append(allocator, .call, line);
    try chunk.emitByte(allocator, @intCast(list.items.len - 1), line);
}

pub fn compileVector(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    vector: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    try compileArgs(allocator, chunk, locals, vector.items, err_ctx);
    try chunk.emitVec(allocator, @intCast(vector.items.len), line);
}

pub fn compileHashMap(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    vector: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    if (vector.items.len % 2 != 0) {
        try err_ctx.setMsgWithLine(
            allocator,
            "hash_map",
            "Expects an even number of arguments, got {}.",
            .{vector.items.len},
            line,
        );
        return Errors.WrongNumberOfArguments;
    }

    try compileArgs(allocator, chunk, locals, vector.items, err_ctx);
    try chunk.emitHashMap(allocator, @intCast(vector.items.len), line);
}

pub fn compileToken(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    token: reader.Token,
    locals: *Locals,
    err_ctx: *errors.Ctx,
) !void {
    switch (token.kind) {
        .atom => |v| try compileAtom(allocator, chunk, locals, v, token.line),
        .list => |l| try compileList(allocator, chunk, locals, l, token.line, err_ctx),
        .vector => |v| try compileVector(allocator, chunk, locals, v, token.line, err_ctx),
        .hash_map => |hm| try compileHashMap(allocator, chunk, locals, hm, token.line, err_ctx),
    }
}

pub fn compileToChunk(
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(reader.Token),
    chunk: *Chunk,
    locals: *Locals,
    err_ctx: *errors.Ctx,
) !void {
    for (tokens.items, 0..) |token, i| switch (token.kind) {
        .atom => |a| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }
            try compileAtom(allocator, chunk, locals, a, token.line);
        },
        .vector => |vec| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }

            try compileVector(allocator, chunk, locals, vec, token.line, err_ctx);
        },
        .hash_map => |hm| {
            if (i != tokens.items.len - 1) {
                continue;
            }

            try compileHashMap(allocator, chunk, locals, hm, token.line, err_ctx);
        },
        .list => |list| {
            if (list.items.len == 0 and i != tokens.items.len - 1) {
                continue;
            }

            try compileList(allocator, chunk, locals, list, token.line, err_ctx);
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

    var locals: Locals = .empty;
    try compileToChunk(allocator, tokens, chunk, &locals, err_ctx);

    return chunk;
}
