const std = @import("std");
const builtin = @import("builtin");

const errors = @import("errors.zig");
const debug = @import("debug.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const Obj = @import("value.zig").Obj;
const Value = @import("value.zig").Value;
const compiler = @import("compiler.zig");
const Instructions = @import("instructions.zig").Instructions;

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
    UndefinedVariable,
};

pub const Error = CompileError || InterpreterError || RuntimeError;

pub const VM = struct {
    chunk: Chunk,
    ip: [*]u8,
    stack: std.ArrayList(Value),
    globals: std.StringArrayHashMapUnmanaged(Value),

    pub fn init() VM {
        return .{
            .chunk = .empty,
            .ip = undefined,
            .stack = .empty,
            .globals = .empty,
        };
    }

    pub fn deinit(self: *VM, allocator: std.mem.Allocator) void {
        defer self.stack.deinit(allocator);
        defer self.globals.deinit(allocator);

        for (self.stack.items) |*v| {
            v.deinit(allocator);
        }

        var iter = self.globals.iterator();
        while (iter.next()) |kv| {
            kv.value_ptr.deinit(allocator);
        }
    }

    fn resetStack(vm: *VM) void {
        vm.stack.clearRetainingCapacity();
    }

    pub fn stackPeek(vm: *VM) Error!Value {
        if (vm.stack.items.len == 0) {
            return Error.StackEmpty;
        }

        return vm.stack.items[vm.stack.items.len - 1];
    }

    pub fn stackPop(vm: *VM) Error!Value {
        return vm.stack.pop() orelse Error.StackEmpty;
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

    pub fn run(vm: *VM, allocator: std.mem.Allocator, err_ctx: *errors.Ctx) !void {
        // debug stuff
        var line_i: usize = 0;
        var index: usize = 0;

        while (true) {
            const instruction = std.enums.fromInt(OpCode, vm.readByte()) orelse {
                return Error.InvalidInstruction;
            };

            const line = vm.chunk.lines.items[line_i];
            line_i += 1;

            if (builtin.mode == .Debug) {
                const op_name, const offset = debug.disassembleInstruction(allocator, vm.chunk, index) catch unreachable;
                defer allocator.free(op_name);

                std.debug.print("==== STACK ====\n", .{});
                std.debug.print("[ ", .{});
                for (vm.stack.items) |i| {
                    i.printValue();
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
                    defer v.deinit(allocator);

                    v.printValue();
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
                .add => {
                    const val = try Instructions.add(vm, allocator, line, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .subtract => {
                    const val = try Instructions.sub(vm, allocator, line, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .multiply => {
                    const val = try Instructions.mult(vm, allocator, line, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .divide => {
                    const val = try Instructions.div(vm, allocator, line, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .def_global => {
                    const name = try vm.stackPop();
                    const name_str = name.symbol;

                    const val = try vm.stackPop();
                    try vm.globals.put(allocator, name_str, val);
                },
                .get_global => {
                    const name = try vm.stackPop();
                    const name_str = name.symbol;

                    const val = vm.globals.get(name_str) orelse return Error.UndefinedVariable;
                    try vm.stack.append(allocator, val.borrow());
                },
                .noop => {},
            }
        }
    }
};
