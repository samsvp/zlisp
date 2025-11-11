const std = @import("std");

const errors = @import("../errors.zig");
const Obj = @import("../value.zig").Obj;
const Value = @import("../value.zig").Value;

const vm_module = @import("vm.zig");
const Error = vm_module.Error;
const VM = vm_module.VM;

pub const Instructions = struct {
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

    /// Stack top: arity -> how many values to pop from the stack
    /// Sums the remaining elements in the stack.
    pub fn add(vm: *VM, allocator: std.mem.Allocator, n: usize, err_ctx: *errors.Ctx) !Value {
        defer vm.stack.shrinkRetainingCapacity(vm.stack.items.len - n);

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
                            .string => try acc.appendManyMut(allocator, value.obj.as(Obj.String).items),
                            else => return wrongType(allocator, "+", @tagName(value), err_ctx),
                        }
                    }
                    return .{ .obj = &acc.obj };
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
};
