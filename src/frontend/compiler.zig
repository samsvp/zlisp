const std = @import("std");
const errors = @import("../errors.zig");
const reader = @import("reader.zig");

const Obj = @import("../values/value.zig").Obj;
const Value = @import("../values/value.zig").Value;
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

    pub fn deinit(self: *Locals, gpa: std.mem.Allocator) void {
        self.names.deinit(gpa);
    }

    pub fn put(self: *Locals, gpa: std.mem.Allocator, name: []const u8) !void {
        const size: u16 = @intCast(self.names.count());
        _ = try self.names.getOrPutValue(gpa, name, self.offset + size);
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
    not,
    @"if",
    @"fn",
    list,
    def,
    let,
};

/// Returns false if the function is a builtin (+,-,*,/) or a true function to be called.
pub fn compileAtom(gpa: std.mem.Allocator, chunk: *Chunk, locals: *Locals, value: Value, line: usize) !void {
    switch (value) {
        .symbol => |s| {
            if (locals.get(s)) |index| {
                try chunk.emitGetLocal(gpa, index, line);
            } else {
                try chunk.emitGetGlobal(gpa, s, line);
            }
        },
        else => _ = try chunk.emitConstant(gpa, value, line),
    }
}

fn compileArgs(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    err_ctx: *errors.Ctx,
) anyerror!void {
    for (0..args.len) |i| {
        const token = args[args.len - i - 1];
        try compileToken(gpa, chunk, token, locals, err_ctx);
    }
}

fn compileOp(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    op: OpCode,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    try compileArgs(gpa, chunk, locals, args, err_ctx);
    try chunk.append(gpa, op, line);
    try chunk.emitByte(gpa, @intCast(args.len), line);
}

fn compileNot(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len != 1) {
        try err_ctx.setMsgWithLine(gpa, "not", "Not takes one parameter, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    const token = args[0];
    try compileToken(gpa, chunk, token, locals, err_ctx);
    try chunk.append(gpa, .not, line);
}

fn compileIf(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len != 2 and args.len != 3) {
        try err_ctx.setMsgWithLine(gpa, "if", "Expected 2 or 3 arguments, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    // place the expr result on the stack
    try compileToken(gpa, chunk, args[0], locals, err_ctx);
    const jump_false_index = try chunk.emitJumpIfFalse(gpa, 0, line);
    // compile the clauses
    try compileToken(gpa, chunk, args[1], locals, err_ctx);
    chunk.replaceJump(jump_false_index, @intCast(chunk.code.items.len - jump_false_index));

    const jump_index = try chunk.emitJump(gpa, 0, line);
    if (args.len == 2) {
        _ = try chunk.emitConstant(gpa, .nil, line);
    } else {
        try compileToken(gpa, chunk, args[2], locals, err_ctx);
    }

    chunk.replaceJump(jump_index, @intCast(chunk.code.items.len - jump_index - 3));
}

fn createArgs(
    gpa: std.mem.Allocator,
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
                try err_ctx.setMsgWithLine(gpa, "fn", "Function arguments must be symbols", .{}, line);
                return Errors.WrongArgumentType;
            };

        try locals.put(gpa, arg_name);

        if (i == args.len - 1) {
            is_variadic = arg_name[0] == '&';
        }
    }
    return is_variadic;
}

fn compileFn(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len > 4 or args.len < 2) {
        try err_ctx.setMsgWithLine(gpa, "fn", "Expected 2 to 4 arguments, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    const help = switch (args[0].kind) {
        .atom => |v| if (v == .obj and v.obj.kind == .string)
            v.obj.as(Obj.String).items
        else
            "",
        else => "",
    };

    var fn_chunk = try gpa.create(Chunk);
    fn_chunk.* = Chunk.empty;

    var fn_locals = locals.createNext();
    defer fn_locals.deinit(gpa);

    const is_closure = args.len >= 3 and args[args.len - 3].kind == .vector;
    if (is_closure) {
        const closure_tokens = args[args.len - 3];
        const closure_args = closure_tokens.kind.vector.items;

        _ = try createArgs(gpa, &fn_locals, closure_args, closure_tokens.line, err_ctx);
        for (closure_args) |arg| {
            try compileAtom(gpa, chunk, locals, arg.kind.atom, closure_tokens.line);
        }
    }

    const fn_args_token = args[args.len - 2];
    if (fn_args_token.kind != .vector) {
        try err_ctx.setMsgWithLine(gpa, "fn", "Function arguments must be a vector.", .{}, fn_args_token.line);
    }

    const fn_args = fn_args_token.kind.vector.items;
    const is_variadic = try createArgs(gpa, &fn_locals, fn_args, fn_args_token.line, err_ctx);

    const ast_token = args[args.len - 1];
    try compileToken(gpa, fn_chunk, ast_token, &fn_locals, err_ctx);
    try fn_chunk.append(gpa, .ret, ast_token.line);

    var func = try Obj.Function.init(gpa, fn_chunk, @intCast(fn_args.len), is_variadic, help);
    defer func.obj.deinit(gpa);

    _ = try chunk.emitConstant(gpa, .{ .obj = &func.obj }, line);

    if (is_closure) {
        try chunk.append(gpa, .create_closure, line);
        const closure_args: u16 = @intCast(args[args.len - 3].kind.vector.items.len);
        const bytes = std.mem.toBytes(closure_args);
        try chunk.emitBytes(gpa, &bytes, line);
    }
}

fn compileDef(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len != 2) {
        try err_ctx.setMsgWithLine(gpa, "def", "Wrong number of arguments. Expected 2, got {}", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    if (args[0].kind != .atom and args[0].kind.atom != .symbol) {
        try err_ctx.setMsgWithLine(gpa, "def", "Wrong argument type {s}.", .{@tagName(args[0].kind.atom)}, args[0].line);
        return Errors.WrongArgumentType;
    }

    try compileToken(gpa, chunk, args[1], locals, err_ctx);
    _ = try chunk.emitConstant(gpa, args[0].kind.atom, args[0].line);
    try chunk.append(gpa, .def_global, line);
}

pub fn compileLet(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    args: []const reader.Token,
    line: usize,
    err_ctx: *errors.Ctx,
) anyerror!void {
    if (args.len != 2) {
        try err_ctx.setMsgWithLine(gpa, "let", "Wrong number of arguments. Expected 2, got {}.", .{args.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    const args_token = args[0];
    if (args_token.kind != .vector) {
        try err_ctx.setMsgWithLine(
            gpa,
            "let",
            "Wrong argument type. Expected vector, got {s}.",
            .{@tagName(args_token.kind)},
            args_token.line,
        );
        return Errors.WrongArgumentType;
    }

    const vec = args_token.kind.vector;
    if (vec.items.len % 2 != 0) {
        try err_ctx.setMsgWithLine(gpa, "let", "Expect an even number of value-bindings.", .{}, args_token.line);
        return Errors.WrongNumberOfArguments;
    }

    var let_locals = locals.createNext();
    defer let_locals.deinit(gpa);

    for (0..vec.items.len / 2) |idx| {
        const i = 2 * idx;
        const key = vec.items[i];
        const value = vec.items[i + 1];

        const arg_name =
            if (key.kind == .atom and key.kind.atom == .symbol)
                key.kind.atom.symbol
            else {
                try err_ctx.setMsgWithLine(gpa, "let", "Varuable name must be symbol", .{}, key.line);
                return Errors.WrongArgumentType;
            };
        try let_locals.put(gpa, arg_name);
        try compileToken(gpa, chunk, value, &let_locals, err_ctx);
        try chunk.append(gpa, .def_local, line);
    }

    try compileToken(gpa, chunk, args[1], &let_locals, err_ctx);

    if (vec.items.len > 0) {
        try chunk.emitShrinkLocals(gpa, @intCast(let_locals.names.count()), line);
    }
}

pub fn compileList(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    list: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    if (list.items.len == 0) {
        const empty_list = try Obj.List.empty(gpa);
        defer empty_list.obj.deinit(gpa);

        _ = try chunk.emitConstant(gpa, .{ .obj = &empty_list.obj }, line);
        return;
    }

    err_ctx.line = line;
    const first = list.items[0];
    switch (first.kind) {
        .list => {},
        .atom => |a| if (a != .symbol) {
            try err_ctx.setMsg(gpa, "COMPILE", "List first element must be function.", .{});
            return Errors.NonFunctionAsHeadOfList;
        },
        .vector, .hash_map => {
            try err_ctx.setMsg(gpa, "COMPILE", "List first element must be function.", .{});
            return Errors.NonFunctionAsHeadOfList;
        },
    }

    const args = list.items[1..];
    if (first.kind == .atom and first.kind.atom == .symbol) {
        if (std.meta.stringToEnum(Constants, first.kind.atom.symbol)) |c| {
            switch (c) {
                .@"+" => try compileOp(gpa, chunk, locals, .add, args, line, err_ctx),
                .@"-" => try compileOp(gpa, chunk, locals, .subtract, args, line, err_ctx),
                .@"*" => try compileOp(gpa, chunk, locals, .multiply, args, line, err_ctx),
                .@"/" => try compileOp(gpa, chunk, locals, .divide, args, line, err_ctx),
                .@"=" => try compileOp(gpa, chunk, locals, .eq, args, line, err_ctx),
                .@"<" => try compileOp(gpa, chunk, locals, .lt, args, line, err_ctx),
                .@">" => try compileOp(gpa, chunk, locals, .gt, args, line, err_ctx),
                .@"<=" => try compileOp(gpa, chunk, locals, .leq, args, line, err_ctx),
                .@">=" => try compileOp(gpa, chunk, locals, .geq, args, line, err_ctx),
                .not => try compileNot(gpa, chunk, locals, args, line, err_ctx),
                .@"if" => try compileIf(gpa, chunk, locals, args, line, err_ctx),
                .@"fn" => try compileFn(gpa, chunk, locals, args, line, err_ctx),
                .list => {
                    try compileArgs(gpa, chunk, locals, args, err_ctx);
                    try chunk.emitList(gpa, @intCast(args.len), line);
                },
                .def => try compileDef(gpa, chunk, locals, args, line, err_ctx),
                .let => try compileLet(gpa, chunk, locals, args, line, err_ctx),
            }
            return;
        }
    }

    // compile the atom last
    try compileArgs(gpa, chunk, locals, list.items[1..], err_ctx);
    switch (first.kind) {
        .atom => |atom| try compileAtom(gpa, chunk, locals, atom, line),
        .list => |l| try compileList(gpa, chunk, locals, l, line, err_ctx),
        else => unreachable,
    }
    try chunk.append(gpa, .call, line);
    try chunk.emitByte(gpa, @intCast(list.items.len - 1), line);
}

pub fn compileVector(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    vector: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    try compileArgs(gpa, chunk, locals, vector.items, err_ctx);
    try chunk.emitVec(gpa, @intCast(vector.items.len), line);
}

pub fn compileHashMap(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    locals: *Locals,
    vector: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    if (vector.items.len % 2 != 0) {
        try err_ctx.setMsgWithLine(gpa, "hash_map", "Expects an even number of arguments, got {}.", .{vector.items.len}, line);
        return Errors.WrongNumberOfArguments;
    }

    try compileArgs(gpa, chunk, locals, vector.items, err_ctx);
    try chunk.emitHashMap(gpa, @intCast(vector.items.len), line);
}

pub fn compileToken(
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    token: reader.Token,
    locals: *Locals,
    err_ctx: *errors.Ctx,
) !void {
    switch (token.kind) {
        .atom => |v| try compileAtom(gpa, chunk, locals, v, token.line),
        .list => |l| try compileList(gpa, chunk, locals, l, token.line, err_ctx),
        .vector => |v| try compileVector(gpa, chunk, locals, v, token.line, err_ctx),
        .hash_map => |hm| try compileHashMap(gpa, chunk, locals, hm, token.line, err_ctx),
    }
}

pub fn compileToChunk(
    gpa: std.mem.Allocator,
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
            try compileAtom(gpa, chunk, locals, a, token.line);
        },
        .vector => |vec| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }

            try compileVector(gpa, chunk, locals, vec, token.line, err_ctx);
        },
        .hash_map => |hm| {
            if (i != tokens.items.len - 1) {
                continue;
            }

            try compileHashMap(gpa, chunk, locals, hm, token.line, err_ctx);
        },
        .list => |list| {
            if (list.items.len == 0 and i != tokens.items.len - 1) {
                continue;
            }

            try compileList(gpa, chunk, locals, list, token.line, err_ctx);
            // pop the last statement value
            if (i != tokens.items.len - 1) {
                try chunk.append(gpa, .pop, 0);
            }
        },
    };

    try chunk.append(gpa, .ret, 0);
}

pub fn compile(gpa: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !*Chunk {
    var tokens = try reader.readStr(gpa, source, err_ctx);
    defer tokens.deinit(gpa);

    defer for (tokens.items) |*token| token.deinit(gpa);

    const chunk = try gpa.create(Chunk);
    chunk.* = Chunk.empty;

    var locals: Locals = .empty;
    try compileToChunk(gpa, tokens, chunk, &locals, err_ctx);

    return chunk;
}
