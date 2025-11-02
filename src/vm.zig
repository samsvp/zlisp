const std = @import("std");
const builtin = @import("builtin");

const errors = @import("errors.zig");
const debug = @import("debug.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const Value = @import("value.zig").Value;
const compiler = @import("compiler.zig");
const printValue = @import("value.zig").printValue;

pub const CompileError = error{
    InvalidInstruction,
};

pub const InterpreterError = error{
    StackFull,
    StackEmpty,
};

pub const RuntimeError = error{
    WrongType,
    DivisionByZero,
};

pub const Error = CompileError || InterpreterError || RuntimeError;

pub const VM = struct {
    chunk: Chunk,
    ip: [*]u8,
    stack: std.ArrayList(Value),

    const STACK_MAX = 256;

    pub fn init() VM {
        return .{
            .chunk = .empty,
            .ip = undefined,
            .stack = .empty,
        };
    }

    pub fn deinit(self: *VM, allocator: std.mem.Allocator) void {
        self.stack.deinit(allocator);
    }

    fn resetStack(vm: *VM) void {
        vm.stack.clearRetainingCapacity();
    }

    fn stackPush(vm: *VM, v: Value) Error!void {
        if (VM.STACK_MAX <= vm.stack_top) {
            return Error.StackFull;
        }

        vm.stack[vm.stack_top] = v;
        vm.stack_top += 1;
    }

    fn stackPeek(vm: *VM) Error!Value {
        if (vm.stack.items.len == 0) {
            return Error.StackEmpty;
        }

        return vm.stack.items[vm.stack.items.len - 1];
    }

    fn stackPop(vm: *VM) Error!Value {
        return vm.stack.pop() orelse Error.StackEmpty;
    }

    fn stackPopN(vm: *VM, comptime N: usize) Error![N]Value {
        var res: [N]Value = undefined;
        for (0..N) |i| {
            res[i] = try vm.stackPop();
        }
        return res;
    }

    fn readByte(vm: *VM) u8 {
        const b = vm.ip[0];
        vm.ip += 1;
        return b;
    }

    fn readBytes(vm: *VM, n: usize) []const u8 {
        const bs = vm.ip[0..n];
        vm.ip += n;
        return bs;
    }

    fn readConstant(vm: *VM) Value {
        const i = vm.readByte();
        return vm.chunk.constants.items[i];
    }

    fn readConstantLong(vm: *VM) Value {
        const bs = vm.readBytes(2);
        const c_index = std.mem.bytesToValue(u16, bs);
        return vm.chunk.constants.items[c_index];
    }

    fn add(vm: *VM, allocator: std.mem.Allocator, n: usize, line: usize, err_ctx: *errors.Ctx) !Value {
        const val = try vm.stackPop();

        return switch (val) {
            .int => |i| {
                var acc: i32 = i;
                for (1..n) |_| {
                    const value = try vm.stackPop();
                    switch (value) {
                        .int => |i_val| acc += i_val,
                        else => {
                            try err_ctx.setMsg(allocator, "'+' line {}: unsupported type {s}", .{ line, @tagName(value) });
                            return Error.WrongType;
                        },
                    }
                }
                return .{ .int = acc };
            },
            .float => |f| {
                var acc: f32 = f;
                for (1..n) |_| {
                    const value = try vm.stackPop();
                    switch (value) {
                        .float => |f_val| acc += f_val,
                        .int => |i_val| acc += @floatFromInt(i_val),
                        else => {
                            try err_ctx.setMsg(allocator, "'+' line {}: unsupported type {s}", .{ line, @tagName(value) });
                            return Error.WrongType;
                        },
                    }
                }
                return .{ .float = acc };
            },
            else => {
                try err_ctx.setMsg(allocator, "'+' line {}: unsupported type {s}", .{ line, @tagName(val) });
                return Error.WrongType;
            },
        };
    }

    fn sub(vm: *VM, allocator: std.mem.Allocator, n: usize, line: usize, err_ctx: *errors.Ctx) !Value {
        const val = try vm.stackPop();

        return switch (val) {
            .int => |i| {
                if (n == 1) {
                    return .{ .int = -i };
                }

                var acc: i32 = i;
                for (1..n) |_| {
                    const value = try vm.stackPop();
                    switch (value) {
                        .int => |i_val| acc -= i_val,
                        else => {
                            try err_ctx.setMsg(allocator, "'-' line {}: unsupported type {s}", .{ line, @tagName(value) });
                            return Error.WrongType;
                        },
                    }
                }
                return .{ .int = acc };
            },
            .float => |f| {
                if (n == 1) {
                    return .{ .float = -f };
                }

                var acc: f32 = f;
                for (1..n) |_| {
                    const value = try vm.stackPop();
                    switch (value) {
                        .float => |f_val| acc -= f_val,
                        .int => |i_val| acc -= @floatFromInt(i_val),
                        else => {
                            try err_ctx.setMsg(allocator, "'-' line {}: unsupported type {s}", .{ line, @tagName(value) });
                            return Error.WrongType;
                        },
                    }
                }
                return .{ .float = acc };
            },
            else => {
                try err_ctx.setMsg(allocator, "'-' line {}: unsupported type {s}", .{ line, @tagName(val) });
                return Error.WrongType;
            },
        };
    }

    fn multiply(vm: *VM, allocator: std.mem.Allocator, n: usize, line: usize, err_ctx: *errors.Ctx) !Value {
        const val = try vm.stackPop();

        return switch (val) {
            .int => |i| {
                var acc: i32 = i;
                for (1..n) |_| {
                    const value = try vm.stackPop();
                    switch (value) {
                        .int => |i_val| acc *= i_val,
                        else => {
                            try err_ctx.setMsg(allocator, "'*' line {}: unsupported type {s}", .{ line, @tagName(value) });
                            return Error.WrongType;
                        },
                    }
                }
                return .{ .int = acc };
            },
            .float => |f| {
                var acc: f32 = f;
                for (1..n) |_| {
                    const value = try vm.stackPop();
                    switch (value) {
                        .float => |f_val| acc *= f_val,
                        .int => |i_val| acc *= @floatFromInt(i_val),
                        else => {
                            try err_ctx.setMsg(allocator, "'*' line {}: unsupported type {s}", .{ line, @tagName(value) });
                            return Error.WrongType;
                        },
                    }
                }
                return .{ .float = acc };
            },
            else => {
                try err_ctx.setMsg(allocator, "'*' line {}: unsupported type {s}", .{ line, @tagName(val) });
                return Error.WrongType;
            },
        };
    }

    fn div(vm: *VM, allocator: std.mem.Allocator, n: usize, line: usize, err_ctx: *errors.Ctx) !Value {
        const val = try vm.stackPop();

        return switch (val) {
            .int => |i| {
                var acc: i32 = i;
                for (1..n) |_| {
                    const value = try vm.stackPop();
                    switch (value) {
                        .int => |i_val| if (i_val != 0) {
                            acc = @divFloor(acc, i_val);
                        } else {
                            try err_ctx.setMsg(allocator, "'/' line {}: division by zero", .{line});
                            return Error.DivisionByZero;
                        },
                        else => {
                            try err_ctx.setMsg(allocator, "'*' line {}: unsupported type {s}", .{ line, @tagName(value) });
                            return Error.WrongType;
                        },
                    }
                }
                return .{ .int = acc };
            },
            .float => |f| {
                var acc: f32 = f;
                for (1..n) |_| {
                    const value = try vm.stackPop();
                    switch (value) {
                        .float => |f_val| if (f_val != 0) {
                            acc /= f_val;
                        } else {
                            try err_ctx.setMsg(allocator, "'/' line {}: division by zero", .{line});
                            return Error.DivisionByZero;
                        },
                        .int => |i_val| if (i_val != 0) {
                            acc /= @floatFromInt(i_val);
                        } else {
                            try err_ctx.setMsg(allocator, "'/' line {}: division by zero", .{line});
                            return Error.DivisionByZero;
                        },
                        else => {
                            try err_ctx.setMsg(allocator, "'*' line {}: unsupported type {s}", .{ line, @tagName(value) });
                            return Error.WrongType;
                        },
                    }
                }
                return .{ .float = acc };
            },
            else => {
                try err_ctx.setMsg(allocator, "'*' line {}: unsupported type {s}", .{ line, @tagName(val) });
                return Error.WrongType;
            },
        };
    }

    fn run(vm: *VM, allocator: std.mem.Allocator, err_ctx: *errors.Ctx) !void {
        // debug stuff
        var buf: [32]u8 = undefined;
        var line_i: usize = 0;
        var index: usize = 0;

        while (true) {
            const instruction = std.enums.fromInt(OpCode, vm.readByte()) orelse {
                return Error.InvalidInstruction;
            };

            const line = vm.chunk.lines.items[line_i];
            line_i += 1;

            if (builtin.mode == .Debug) {
                const op_name, const offset = debug.disassembleInstruction(vm.chunk, index, &buf) catch unreachable;

                std.debug.print("==== STACK ====\n", .{});
                std.debug.print("[ ", .{});
                for (vm.stack.items) |i| {
                    printValue(i);
                    std.debug.print(", ", .{});
                }
                std.debug.print("]\n", .{});

                std.debug.print("==== OP ====\n", .{});
                std.debug.print("[ {d:0>4} ] {d:0>4} {s}\n", .{ index, line, op_name });
                index += offset;
            }

            switch (instruction) {
                .ret => {
                    const v = try vm.stackPop();
                    printValue(v);
                    std.debug.print("\n", .{});
                    return;
                },
                .constant => {
                    const v = vm.readConstant();
                    try vm.stack.append(allocator, v);
                },
                .constant_long => {
                    const v = vm.readConstantLong();
                    try vm.stack.append(allocator, v);
                },
                .negate => {
                    vm.stack.items[vm.stack.items.len - 1] = switch (vm.stack.items[vm.stack.items.len - 1]) {
                        .int => |i| .{ .int = -i },
                        .float => |f| .{ .float = -f },
                        else => {
                            try err_ctx.setMsg(allocator, "'-': wrong argument type on line {}.", .{line});
                            return Error.WrongType;
                        },
                    };
                },
                .add => {
                    const val = try vm.add(allocator, 2, line, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .subtract => {
                    const val = try vm.sub(allocator, 2, line, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .multiply => {
                    const val = try vm.multiply(allocator, 2, line, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .divide => {
                    const val = try vm.div(allocator, 2, line, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .noop => {},
            }
        }
    }

    pub fn interpret(vm: *VM, allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !void {
        var chunk = try compiler.compile(allocator, source, err_ctx);
        defer chunk.deinit(allocator);

        vm.chunk = chunk;
        vm.ip = vm.chunk.code.items.ptr;

        try vm.run(allocator, err_ctx);
    }
};
