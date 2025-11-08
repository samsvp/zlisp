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
    TypeNotCallable,
    WrongArgumentNumber,
    StackOverflow,
};

pub const Error = CompileError || InterpreterError || RuntimeError;

const CallFrame = struct {
    function: *Obj.Function,
    ip: [*]u8,
    stack_pos: usize,

    pub fn deinit(self: *CallFrame, allocator: std.mem.Allocator) void {
        self.function.deinit(allocator);
    }
};

pub const VM = struct {
    stack: std.ArrayList(Value),
    local_stack: std.ArrayList(Value),
    globals: std.StringArrayHashMapUnmanaged(Value),

    frames: [FRAMES_MAX]CallFrame,
    frame_count: u32,

    const FRAMES_MAX = 1024;

    pub fn init(func: *Obj.Function) VM {
        var vm = VM{
            .stack = .empty,
            .local_stack = .empty,
            .globals = .empty,

            .frames = undefined,
            .frame_count = 1,
        };

        vm.frames[0] = CallFrame{
            .function = func,
            .ip = func.chunk.code.items.ptr,
            .stack_pos = 0,
        };

        return vm;
    }

    pub fn deinit(self: *VM, allocator: std.mem.Allocator) void {
        defer self.stack.deinit(allocator);
        defer self.local_stack.deinit(allocator);
        defer self.globals.deinit(allocator);

        for (0..self.frame_count + 1) |i| {
            self.frames[i].deinit(allocator);
        }

        for (self.local_stack.items) |*v| {
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
        const b = vm.frames[vm.frame_count - 1].ip[0];
        vm.frames[vm.frame_count - 1].ip += 1;
        return b;
    }

    fn readBytes(vm: *VM, n: usize) []const u8 {
        const bs = vm.frames[vm.frame_count - 1].ip[0..n];
        vm.frames[vm.frame_count - 1].ip += n;
        return bs;
    }

    fn readConstant(vm: *VM) Value {
        const i = vm.readByte();
        return vm.frames[vm.frame_count - 1].function.chunk.constants.items[i];
    }

    fn readConstantLong(vm: *VM) Value {
        const bs = vm.readBytes(2);
        const c_index = std.mem.bytesToValue(u16, bs);
        return vm.frames[vm.frame_count - 1].function.chunk.constants.items[c_index];
    }

    fn call(vm: *VM, f: *Obj.Function, arg_count: u8) !*CallFrame {
        if (arg_count != f.arity) {
            return Error.WrongArgumentNumber;
        }

        vm.frame_count += 1;
        if (vm.frame_count == FRAMES_MAX) {
            return Error.StackOverflow;
        }

        const frame = CallFrame{
            .function = f,
            .ip = f.chunk.code.items.ptr,
            // function arguments are loaded at the top of the local stack
            .stack_pos = vm.local_stack.items.len - arg_count,
        };

        vm.frames[vm.frame_count - 1] = frame;
        return &vm.frames[vm.frame_count - 1];
    }

    fn callValue(vm: *VM, v: Value, arg_count: u8) !*CallFrame {
        if (v != .obj) {
            return Error.TypeNotCallable;
        }

        return switch (v.obj.kind) {
            .function => try vm.call(v.obj.as(Obj.Function), arg_count),
            else => Error.TypeNotCallable,
        };
    }

    pub fn run(vm: *VM, allocator: std.mem.Allocator, err_ctx: *errors.Ctx) !void {
        var frame = &vm.frames[vm.frame_count - 1];

        while (true) {
            const instruction = std.enums.fromInt(OpCode, vm.readByte()) orelse {
                return Error.InvalidInstruction;
            };

            if (builtin.mode == .Debug) {
                const op_name, _ = debug.disassembleInstruction(
                    allocator,
                    frame.function.chunk.*,
                    frame.ip - frame.function.chunk.code.items.ptr - 1,
                ) catch unreachable;
                defer allocator.free(op_name);

                std.debug.print("==== STACK ====\n", .{});
                std.debug.print("[ ", .{});
                for (vm.stack.items) |i| {
                    i.printValue();
                    std.debug.print(", ", .{});
                }
                std.debug.print("]\n", .{});

                std.debug.print("==== OP ====\n", .{});
                std.debug.print("[ {s}\n", .{op_name});
            }

            switch (instruction) {
                .ret => {
                    const result = try vm.stackPop();
                    vm.frame_count -= 1;
                    if (vm.frame_count == 0) {
                        result.deinit(allocator);
                        return;
                    }

                    try vm.stack.append(allocator, result);
                    for (frame.stack_pos..vm.local_stack.items.len) |i| {
                        vm.local_stack.items[i].deinit(allocator);
                    }
                    vm.local_stack.shrinkRetainingCapacity(frame.stack_pos);
                    frame = &vm.frames[vm.frame_count - 1];
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
                    const val = try Instructions.add(vm, allocator, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .subtract => {
                    const val = try Instructions.sub(vm, allocator, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .multiply => {
                    const val = try Instructions.mult(vm, allocator, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .divide => {
                    const val = try Instructions.div(vm, allocator, err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .jump => {
                    const offset: u16 = std.mem.bytesToValue(u16, vm.readBytes(2));
                    frame.ip += offset;
                },
                .jump_if_false => {
                    const val = try vm.stackPop();
                    const offset: u16 = std.mem.bytesToValue(u16, vm.readBytes(2));

                    if (val == .nil or val.eql(Value.False)) {
                        frame.ip += offset;
                    }
                },
                .def_global => {
                    const name = try vm.stackPop();
                    const name_str = name.symbol;

                    const val = try vm.stackPop();
                    try vm.globals.put(allocator, name_str, val.borrow());
                },
                .get_global => {
                    const name = try vm.stackPop();
                    const name_str = name.symbol;

                    const val = vm.globals.get(name_str) orelse return Error.UndefinedVariable;
                    try vm.stack.append(allocator, val);
                },
                .def_local => {
                    const v = try vm.stackPop();
                    try vm.local_stack.append(allocator, v);
                },
                .get_local => {
                    const slot: u16 = std.mem.bytesToValue(u16, vm.readBytes(2));
                    const slot_index = @as(usize, @intCast(slot)) + vm.frames[vm.frame_count - 1].stack_pos;

                    try vm.stack.append(allocator, vm.local_stack.items[slot_index].borrow());
                },
                .call => {
                    const arg_count = vm.readByte();
                    const v = try vm.stackPop();
                    frame = try vm.callValue(v, arg_count);
                },
                .noop => {},
            }
        }
    }
};
