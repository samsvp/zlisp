const std = @import("std");
const builtin = @import("builtin");

const reader = @import("reader.zig");
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

pub const Error = CompileError || InterpreterError;

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

    fn run(vm: *VM, allocator: std.mem.Allocator) !void {
        // debug stuff
        var buf: [32]u8 = undefined;
        var line_i: usize = 0;
        var index: usize = 0;

        while (true) {
            const instruction = std.enums.fromInt(OpCode, vm.readByte()) orelse {
                return Error.InvalidInstruction;
            };

            if (builtin.mode == .Debug) {
                const line = vm.chunk.lines.items[line_i];
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
                line_i += 1;
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
                    vm.stack.items[vm.stack.items.len - 1] = -vm.stack.items[vm.stack.items.len - 1];
                },
                .add => {
                    const b, const a = try vm.stackPopN(2);
                    try vm.stack.append(allocator, a + b);
                },
                .subtract => {
                    const b, const a = try vm.stackPopN(2);
                    try vm.stack.append(allocator, a - b);
                },
                .multiply => {
                    const b, const a = try vm.stackPopN(2);
                    try vm.stack.append(allocator, a * b);
                },
                .divide => {
                    const b, const a = try vm.stackPopN(2);
                    try vm.stack.append(allocator, a / b);
                },
                .noop => {},
            }
        }
    }

    pub fn interpret(vm: *VM, allocator: std.mem.Allocator, source: []const u8) !reader.TokenDataList {
        _ = vm;
        return compiler.compile(allocator, source);
    }
};
