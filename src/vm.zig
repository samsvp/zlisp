const std = @import("std");
const builtin = @import("builtin");

const debug = @import("debug.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const Value = @import("value.zig").Value;
const printValue = @import("value.zig").printValue;

pub const CompileError = error{
    InvalidInstruction,
};

pub const InterpreterError = error{};

pub const Error = CompileError || InterpreterError;

pub const InterpreterResult = enum {
    ok,
};

pub const VM = struct {
    chunk: Chunk,
    ip: [*]u8,

    pub fn init() VM {
        return .{
            .chunk = .empty,
            .ip = undefined,
        };
    }

    pub fn deinit(self: *VM, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
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

    fn run(vm: *VM) Error!InterpreterResult {
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

                std.debug.print("[ {d:0>4} ] {d:0>4} {s}\n", .{ index, line, op_name });
                index += offset;
                line_i += 1;
            }

            switch (instruction) {
                .ret => {
                    return .ok;
                },
                .constant => {
                    const v = vm.readConstant();
                    _ = v;
                },
                .constant_long => {
                    const v = vm.readConstantLong();
                    _ = v;
                },
                .noop => {},
            }
        }
    }

    pub fn interpret(vm: *VM, chunk: Chunk) Error!InterpreterResult {
        vm.chunk = chunk;
        vm.ip = chunk.code.items.ptr;
        return vm.run();
    }
};
