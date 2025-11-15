const std = @import("std");
const builtin = @import("builtin");

const errors = @import("../errors.zig");
const debug = @import("debug.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const Obj = @import("../value.zig").Obj;
const Value = @import("../value.zig").Value;
const instructions = @import("instructions.zig");

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
};

pub const VM = struct {
    stack: std.ArrayList(Value),
    local_stack: std.ArrayList(Value),
    globals: std.StringArrayHashMapUnmanaged(Value),

    frames: [FRAMES_MAX]CallFrame,
    frame_count: u32,

    err_ctx: errors.Ctx,

    const FRAMES_MAX = 1024;

    pub fn init(func: *Obj.Function) VM {
        var vm = VM{
            .stack = .empty,
            .local_stack = .empty,
            .globals = .empty,

            .frames = undefined,
            .frame_count = 1,

            .err_ctx = .empty,
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

        for (self.stack.items) |s| {
            s.deinit(allocator);
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

    fn peekByte(vm: *VM) u8 {
        return vm.frames[vm.frame_count - 1].ip[0];
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

    fn emptyFnStack(vm: *VM, allocator: std.mem.Allocator) void {
        const frame = &vm.frames[vm.frame_count - 1];
        for (frame.stack_pos..vm.local_stack.items.len) |i| {
            vm.local_stack.items[i].deinit(allocator);
        }
        vm.local_stack.shrinkRetainingCapacity(frame.stack_pos);
    }

    fn getFnArgs(
        vm: *VM,
        allocator: std.mem.Allocator,
        args: []const Value,
        arity: usize,
        arg_count: usize,
        is_variadic: bool,
    ) !void {
        for (args) |arg| {
            try vm.local_stack.append(allocator, arg);
        }

        if (arity == 0) {
            return;
        }

        for (0..arity - 1) |_| {
            const v = try vm.stackPop();
            try vm.local_stack.append(allocator, v);
        }

        if (!is_variadic) {
            const v = try vm.stackPop();
            try vm.local_stack.append(allocator, v);
            return;
        }

        const variadic_len = arg_count + 1 - arity;
        const variadic_start = vm.stack.items.len - variadic_len;
        const list = try Obj.List.init(allocator, vm.stack.items[variadic_start..]);
        for (vm.stack.items[variadic_start..]) |item| {
            item.deinit(allocator);
        }

        vm.stack.shrinkRetainingCapacity(variadic_start);
        try vm.local_stack.append(allocator, .{ .obj = &list.obj });
    }

    fn call(
        vm: *VM,
        allocator: std.mem.Allocator,
        f: *Obj.Function,
        arg_count: u8,
        args: []const Value,
    ) !*CallFrame {
        if (arg_count != f.arity and (!f.is_variadic or arg_count < f.arity - 1)) {
            return Error.WrongArgumentNumber;
        }

        if (vm.frame_count != 1) {
            if (std.enums.fromInt(OpCode, vm.peekByte())) |op| if (op == .ret) {
                vm.emptyFnStack(allocator);
                try vm.getFnArgs(allocator, args, f.arity, arg_count, f.is_variadic);

                var frame = &vm.frames[vm.frame_count - 1];
                frame.function = f;
                frame.ip = f.chunk.code.items.ptr;
                return frame;
            };
        }

        vm.frame_count += 1;
        if (vm.frame_count == FRAMES_MAX) {
            return Error.StackOverflow;
        }

        const frame = CallFrame{
            .function = f,
            .ip = f.chunk.code.items.ptr,
            // function arguments are loaded at the top of the local stack
            .stack_pos = vm.local_stack.items.len,
        };

        try vm.getFnArgs(allocator, args, f.arity, arg_count, f.is_variadic);
        vm.frames[vm.frame_count - 1] = frame;
        return &vm.frames[vm.frame_count - 1];
    }

    fn callClosure(vm: *VM, allocator: std.mem.Allocator, f: *Obj.Closure, arg_count: u8) !*CallFrame {
        return vm.call(allocator, f.function, arg_count, f.args);
    }

    fn callNative(vm: *VM, allocator: std.mem.Allocator, f: *Obj.NativeFunction, arg_count: u8) !*CallFrame {
        var args = try allocator.alloc(Value, arg_count);
        defer allocator.free(args);

        for (0..arg_count, 0..) |_, i| {
            args[i] = try vm.stackPop();
        }

        const res = try f.native_fn(allocator, args, &vm.err_ctx);
        try vm.stack.append(allocator, res);

        return vm.call(allocator, f.function, arg_count, &.{});
    }

    fn callValue(vm: *VM, allocator: std.mem.Allocator, v: Value, arg_count: u8) !*CallFrame {
        if (v != .obj) {
            return Error.TypeNotCallable;
        }

        return switch (v.obj.kind) {
            .function => try vm.call(allocator, v.obj.as(Obj.Function), arg_count, &.{}),
            .closure => try vm.callClosure(allocator, v.obj.as(Obj.Closure), arg_count),
            .native_fn => try vm.callNative(allocator, v.obj.as(Obj.NativeFunction), arg_count),
            else => Error.TypeNotCallable,
        };
    }

    fn createVector(vm: *VM, allocator: std.mem.Allocator, n: usize) !Value {
        const vec = try Obj.Vector.init(allocator, vm.stack.items[vm.stack.items.len - n ..]);
        for (vm.stack.items[vm.stack.items.len - n ..]) |item| {
            item.deinit(allocator);
        }

        vm.stack.shrinkRetainingCapacity(vm.stack.items.len - n);
        const val: Value = .{ .obj = &vec.obj };
        try vm.stack.append(allocator, val);
        return val;
    }

    fn createClosure(vm: *VM, allocator: std.mem.Allocator, n: u16) !void {
        const func_val = try vm.stackPop();
        const func = func_val.obj.as(Obj.Function);

        var args = try allocator.alloc(Value, n);
        defer allocator.free(args);

        for (0..n) |i| {
            const val = try vm.stackPop();
            args[i] = val.borrow();
        }

        const closure = try Obj.Closure.init(allocator, func, args);
        try vm.stack.append(allocator, .{ .obj = &closure.obj });
    }

    pub fn run(vm: *VM, allocator: std.mem.Allocator) !void {
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
                    i.print();
                    std.debug.print(", ", .{});
                }
                std.debug.print("]\n", .{});

                std.debug.print("==== OP ====\n", .{});
                std.debug.print("[ {s}\n", .{op_name});
            }

            switch (instruction) {
                .ret => {
                    const result = try vm.stackPop();
                    vm.emptyFnStack(allocator);
                    vm.frame_count -= 1;
                    if (vm.frame_count == 0) {
                        result.deinit(allocator);
                        return;
                    }

                    try vm.stack.append(allocator, result);
                    frame = &vm.frames[vm.frame_count - 1];
                },
                .constant => {
                    const v = vm.readConstant();
                    try vm.stack.append(allocator, v.borrow());
                },
                .constant_long => {
                    const v = vm.readConstantLong();
                    try vm.stack.append(allocator, v.borrow());
                },
                .add => {
                    const arg_count = vm.readByte();
                    const val = try instructions.add(vm, allocator, arg_count, &vm.err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .subtract => {
                    const arg_count = vm.readByte();
                    const val = try instructions.sub(vm, allocator, arg_count, &vm.err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .multiply => {
                    const arg_count = vm.readByte();
                    const val = try instructions.mult(vm, allocator, arg_count, &vm.err_ctx);
                    try vm.stack.append(allocator, val);
                },
                .divide => {
                    const arg_count = vm.readByte();
                    const val = try instructions.div(vm, allocator, arg_count, &vm.err_ctx);
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

                    const val = try vm.stackPeek();
                    try vm.globals.put(allocator, name_str, val.borrow());
                },
                .get_global => {
                    const name = try vm.stackPop();
                    const name_str = name.symbol;

                    const val = vm.globals.get(name_str) orelse return Error.UndefinedVariable;
                    try vm.stack.append(allocator, val.borrow());
                },
                .def_local => {
                    const v = try vm.stackPeek();
                    try vm.local_stack.append(allocator, v.borrow());
                },
                .get_local => {
                    const slot = std.mem.bytesToValue(u16, vm.readBytes(2));
                    const slot_index = @as(usize, @intCast(slot)) + vm.frames[vm.frame_count - 1].stack_pos;

                    try vm.stack.append(allocator, vm.local_stack.items[slot_index].borrow());
                },
                .create_vec => {
                    const n = vm.readByte();
                    const vec = try vm.createVector(allocator, @intCast(n));
                    try frame.function.chunk.constants.append(allocator, vec);
                },
                .create_vec_long => {
                    const n = std.mem.bytesToValue(u16, vm.readBytes(2));
                    const vec = try vm.createVector(allocator, @intCast(n));
                    try frame.function.chunk.constants.append(allocator, vec);
                },
                .create_closure => {
                    const n = std.mem.bytesToValue(u16, vm.readBytes(2));
                    try vm.createClosure(allocator, n);
                },
                .pop => {
                    var res = try vm.stackPop();
                    res.deinit(allocator);
                },
                .call => {
                    const arg_count = vm.readByte();
                    const v = try vm.stackPop();
                    defer v.deinit(allocator);

                    frame = try vm.callValue(allocator, v, arg_count);
                },
                .noop => {},
            }
        }
    }
};
