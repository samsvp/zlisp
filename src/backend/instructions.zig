const std = @import("std");

const errors = @import("../errors.zig");
const Obj = @import("../values/value.zig").Obj;
const Value = @import("../values/value.zig").Value;

const vm_module = @import("vm.zig");
const Error = vm_module.Error;
const VM = vm_module.VM;

fn wrongType(
    allocator: std.mem.Allocator,
    op_name: []const u8,
    type_name: []const u8,
    err_ctx: *errors.Ctx,
) anyerror {
    try err_ctx.setMsg(
        allocator,
        op_name,
        "mismatched type {s} - ensure all types are the same.",
        .{type_name},
    );
    return Error.WrongType;
}

fn divisionByZero(
    allocator: std.mem.Allocator,
    err_ctx: *errors.Ctx,
) anyerror {
    try err_ctx.setMsg(
        allocator,
        "/",
        "Division by zero.",
        .{},
    );
    return Error.DivisionByZero;
}

pub fn eql(vm: *VM, allocator: std.mem.Allocator, n: usize) Value {
    defer vm.stack.shrinkRetainingCapacity(vm.stack.items.len - n);
    defer for (0..n) |i| {
        vm.stack.items[vm.stack.items.len - i - 1].deinit(allocator);
    };

    const val = vm.stack.getLast();
    for (1..n) |i| {
        const value = vm.stack.items[vm.stack.items.len - i - 1];
        if (!val.eql(value)) {
            return Value.False;
        }
    }
    return Value.True;
}

pub fn not(vm: *VM, allocator: std.mem.Allocator) Value {
    const val = vm.stack.pop().?;
    defer val.deinit(allocator);

    return switch (val) {
        .nil => Value.True,
        .boolean => |b| if (b) Value.False else Value.True,
        else => Value.False,
    };
}

pub const CmpKind = enum {
    lt,
    gt,
    leq,
    geq,

    pub fn toStr(kind: CmpKind) []const u8 {
        return switch (kind) {
            .lt => "<",
            .gt => ">",
            .leq => "<=",
            .geq => ">=",
        };
    }
};

pub fn cmp(vm: *VM, allocator: std.mem.Allocator, n: usize, comptime k: CmpKind, err_ctx: *errors.Ctx) !Value {
    const op_str = k.toStr();

    defer vm.stack.shrinkRetainingCapacity(vm.stack.items.len - n);
    defer for (0..n) |i| {
        vm.stack.items[vm.stack.items.len - i - 1].deinit(allocator);
    };

    const value_last = vm.stack.getLast();
    const val: f32 = switch (value_last) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => return wrongType(allocator, op_str, @tagName(value_last), err_ctx),
    };
    for (1..n) |i| {
        const value = vm.stack.items[vm.stack.items.len - i - 1];
        const v: f32 = switch (value) {
            .int => |i_| @floatFromInt(i_),
            .float => |f| f,
            else => return wrongType(allocator, op_str, @tagName(value), err_ctx),
        };

        const res = switch (k) {
            .lt => v < val,
            .gt => v > val,
            .leq => v <= val,
            .geq => v >= val,
        };

        if (!res) {
            return Value.False;
        }
    }

    return Value.True;
}

/// Stack top: arity -> how many values to pop from the stack
/// Sums the remaining elements in the stack.
pub fn add(vm: *VM, allocator: std.mem.Allocator, n: usize, err_ctx: *errors.Ctx) !Value {
    defer {
        for (0..n) |i| {
            const value = vm.stack.items[vm.stack.items.len - i - 1];
            value.deinit(allocator);
        }
        vm.stack.shrinkRetainingCapacity(vm.stack.items.len - n);
    }

    const val = vm.stack.getLast();
    switch (val) {
        .int => |i_0| {
            var acc = i_0;
            for (1..n) |i| {
                const value = vm.stack.items[vm.stack.items.len - i - 1];
                switch (value) {
                    .int => |i_val| acc += i_val,
                    else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                }
            }
            return .{ .int = acc };
        },
        .float => |f_0| {
            var acc = f_0;
            for (1..n) |i| {
                const value = vm.stack.items[vm.stack.items.len - i - 1];
                switch (value) {
                    .float => |f_val| acc += f_val,
                    .int => |i_val| acc += @floatFromInt(i_val),
                    else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                }
            }
            return .{ .float = acc };
        },
        .obj => |o| switch (o.kind) {
            .string => {
                const s_0 = o.as(Obj.String);
                var acc = try s_0.copy(allocator);

                for (1..n) |i| {
                    const value = vm.stack.items[vm.stack.items.len - i - 1];
                    if (value != .obj) {
                        return wrongType(allocator, "+", @tagName(value), err_ctx);
                    }

                    switch (value.obj.kind) {
                        .string => try acc.appendMut(allocator, value.obj.as(Obj.String).items),
                        else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                    }
                }
                return .{ .obj = &acc.obj };
            },
            .list => {
                var acc = try o.as(Obj.List).copy(allocator);
                for (1..n) |i| {
                    const value = vm.stack.items[vm.stack.items.len - i - 1];
                    if (value != .obj) {
                        return wrongType(allocator, "+", @tagName(value), err_ctx);
                    }

                    switch (value.obj.kind) {
                        .list => try acc.appendManyMut(allocator, value.obj.as(Obj.List).vec.items),
                        else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                    }
                }
                return .{ .obj = &acc.obj };
            },
            .vector => {
                const pvec = o.as(Obj.PVector);
                const others = try allocator.alloc(Obj.PVector.VecT, n - 1);
                defer allocator.free(others);

                for (1..n) |i| {
                    const value = vm.stack.items[vm.stack.items.len - i - 1];
                    if (value != .obj) {
                        return wrongType(allocator, "+", @tagName(value), err_ctx);
                    }

                    switch (value.obj.kind) {
                        .vector => others[i - 1] = value.obj.as(Obj.PVector).vec,
                        else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                    }
                }
                const new_pvec = try pvec.add(allocator, others);
                return .{ .obj = &new_pvec.obj };
            },
            .hash_map => {
                var hash_map = try o.as(Obj.PHashMap).hash_map.clone(allocator);

                for (1..n) |i| {
                    const value = vm.stack.items[vm.stack.items.len - i - 1];
                    if (value != .obj) {
                        return wrongType(allocator, "+", @tagName(value), err_ctx);
                    }

                    switch (value.obj.kind) {
                        .hash_map => {
                            var hm = value.obj.as(Obj.PHashMap).hash_map;
                            var iter = hm.iterator();
                            while (iter.next()) |kv| {
                                try hash_map.assocMut(allocator, kv.key, kv.value);
                            }
                        },
                        else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                    }
                }
                const new_hash_map = try Obj.PHashMap.initFrom(allocator, hash_map);
                return .{ .obj = &new_hash_map.obj };
            },
            else => return wrongType(allocator, "+", @tagName(val), err_ctx),
        },
        else => return wrongType(allocator, "+", @tagName(val), err_ctx),
    }
}

/// Stack top: arity -> how many values to pop from the stack
/// If arity == 1, return the negated next element in the stack.
/// Else subtract the remaining elements from the next.
pub fn sub(vm: *VM, allocator: std.mem.Allocator, n: usize, err_ctx: *errors.Ctx) !Value {
    defer vm.stack.shrinkRetainingCapacity(vm.stack.items.len - n);

    const val = vm.stack.getLast();
    switch (val) {
        .int => |i_0| {
            if (n == 1) {
                return .{ .int = -i_0 };
            }

            var acc: i32 = i_0;
            for (1..n) |i| {
                const value = vm.stack.items[vm.stack.items.len - i - 1];
                switch (value) {
                    .int => |i_val| acc -= i_val,
                    else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                }
            }
            return .{ .int = acc };
        },
        .float => |f_0| {
            if (n == 1) {
                return .{ .float = -f_0 };
            }

            var acc: f32 = f_0;
            for (1..n) |i| {
                const value = vm.stack.items[vm.stack.items.len - i - 1];
                switch (value) {
                    .float => |f_val| acc -= f_val,
                    .int => |i_val| acc -= @floatFromInt(i_val),
                    else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                }
            }
            return .{ .float = acc };
        },
        else => return wrongType(allocator, "+", @tagName(val), err_ctx),
    }
}

/// Stack top: arity -> how many values to pop from the stack
/// Multiplies the remaining elements in the stack.
pub fn mult(vm: *VM, allocator: std.mem.Allocator, n: usize, err_ctx: *errors.Ctx) !Value {
    defer vm.stack.shrinkRetainingCapacity(vm.stack.items.len - n);

    const val = vm.stack.getLast();

    return switch (val) {
        .int => |i_0| {
            var acc: i32 = i_0;
            for (1..n) |i| {
                const value = vm.stack.items[vm.stack.items.len - i - 1];
                switch (value) {
                    .int => |i_val| acc *= i_val,
                    else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                }
            }
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (1..n) |i| {
                const value = vm.stack.items[vm.stack.items.len - i - 1];
                switch (value) {
                    .float => |f_val| acc *= f_val,
                    .int => |i_val| acc *= @floatFromInt(i_val),
                    else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                }
            }
            return .{ .float = acc };
        },
        else => return wrongType(allocator, "+", @tagName(val), err_ctx),
    };
}

/// Stack top: arity -> how many values to pop from the stack
/// Divides the remaining elements in the stack.
pub fn div(vm: *VM, allocator: std.mem.Allocator, n: usize, err_ctx: *errors.Ctx) !Value {
    defer vm.stack.shrinkRetainingCapacity(vm.stack.items.len - n);

    const val = vm.stack.getLast();
    return switch (val) {
        .int => |i_0| {
            var acc: i32 = i_0;
            for (1..n) |i| {
                const value = vm.stack.items[vm.stack.items.len - i - 1];
                switch (value) {
                    .int => |i_val| if (i_val != 0) {
                        acc = @divFloor(acc, i_val);
                    } else {
                        return divisionByZero(allocator, err_ctx);
                    },
                    else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                }
            }
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (1..n) |i| {
                const value = vm.stack.items[vm.stack.items.len - i - 1];
                switch (value) {
                    .float => |f_val| if (f_val != 0) {
                        acc /= f_val;
                    } else {
                        return divisionByZero(allocator, err_ctx);
                    },
                    .int => |i_val| if (i_val != 0) {
                        acc /= @floatFromInt(i_val);
                    } else {
                        return divisionByZero(allocator, err_ctx);
                    },
                    else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                }
            }
            return .{ .float = acc };
        },
        else => return wrongType(allocator, "+", @tagName(val), err_ctx),
    };
}
