const std = @import("std");
const ln = @import("linenoise");

const Chunk = @import("backend/chunk.zig").Chunk;
const errors = @import("errors.zig");
const VM = @import("backend/vm.zig").VM;
const reader = @import("reader.zig");
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;

pub fn createFn(allocator: std.mem.Allocator) !*Obj.Function {
    var chunk = try allocator.create(Chunk);
    chunk.* = Chunk.empty;

    try chunk.emitGetLocal(allocator, 3, 123);
    try chunk.emitGetLocal(allocator, 2, 123);
    try chunk.emitGetLocal(allocator, 1, 123);
    try chunk.emitGetLocal(allocator, 0, 123);

    _ = try chunk.emitConstant(allocator, .{ .int = 4 }, 123);
    try chunk.append(allocator, .add, 123);
    try chunk.append(allocator, .ret, 124);

    const function = try Obj.Function.init(allocator, chunk, 4, "add-4", "Adds 4 values");
    return function;
}

pub fn createClosure(allocator: std.mem.Allocator) !*Obj.Closure {
    var chunk = try allocator.create(Chunk);
    chunk.* = Chunk.empty;

    try chunk.emitGetLocal(allocator, 3, 123);
    try chunk.emitGetLocal(allocator, 2, 123);
    try chunk.emitGetLocal(allocator, 1, 123);
    try chunk.emitGetLocal(allocator, 0, 123);

    _ = try chunk.emitConstant(allocator, .{ .int = 4 }, 123);
    try chunk.append(allocator, .add, 123);
    try chunk.append(allocator, .ret, 124);

    const s = try Obj.String.init(allocator, "closure");
    var args = [_]Value{.{ .obj = &s.obj }};

    const closure = try Obj.Closure.init(
        allocator,
        chunk,
        3,
        "add-3",
        "adds 3 values with initial condition",
        // simulate closing over a variable with value
        &args,
    );
    return closure;
}

fn testFn(allocator: std.mem.Allocator, _: []const Value, _: *errors.Ctx) anyerror!Value {
    std.debug.print("Hello\n", .{});
    const str = try Obj.String.init(allocator, "hello?");
    return .{ .obj = &str.obj };
}

pub fn createNative(allocator: std.mem.Allocator) !*Obj.NativeFunction {
    return Obj.NativeFunction.init(allocator, testFn, 0, "test", "");
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var chunk = try allocator.create(Chunk);
    chunk.* = Chunk.empty;
    const function = try Obj.Function.init(allocator, chunk, 0, "main", "");

    var native_fn = try createNative(allocator);
    _ = try chunk.emitConstant(allocator, .{ .obj = &native_fn.obj }, 10);
    try chunk.emitDefGlobal(allocator, "my_nat_fn", 10);

    var func = try createFn(allocator);
    _ = try chunk.emitConstant(allocator, .{ .obj = &func.obj }, 11);
    try chunk.emitDefGlobal(allocator, "my_fn", 11);

    var cls = try createClosure(allocator);
    _ = try chunk.emitConstant(allocator, .{ .obj = &cls.obj }, 11);
    try chunk.emitDefGlobal(allocator, "my_cls", 11);

    var s0_1 = try Obj.String.init(allocator, "wow man!");
    var s0_2 = try Obj.String.init(allocator, "wow woman!");

    _ = try chunk.emitConstant(allocator, Value.False, 123);

    const jump_false_index = try chunk.emitJumpIfFalse(allocator, 0, 12);
    const offset_1 = try chunk.emitConstant(allocator, .{ .obj = &s0_1.obj }, 13);
    const jump_index = try chunk.emitJump(allocator, 0, 13);

    chunk.replaceJump(jump_false_index, offset_1 + 3);

    const offset_2 = try chunk.emitConstant(allocator, .{ .obj = &s0_2.obj }, 14);
    chunk.replaceJump(jump_index, offset_2);

    try chunk.emitDefGlobal(allocator, "my_var", 10);

    _ = try chunk.emitConstant(allocator, .{ .float = 1.2 }, 123);
    _ = try chunk.emitConstant(allocator, .{ .float = 3.4 }, 123);
    _ = try chunk.emitConstant(allocator, .{ .int = 2 }, 123);
    try chunk.append(allocator, .add, 123);

    _ = try chunk.emitConstant(allocator, .{ .float = 5.6 }, 123);
    _ = try chunk.emitConstant(allocator, .{ .int = 2 }, 123);
    try chunk.append(allocator, .divide, 123);

    _ = try chunk.emitConstant(allocator, .{ .int = 1 }, 123);
    try chunk.append(allocator, .subtract, 123);

    var s3 = try Obj.String.init(allocator, "!");
    var s2 = try Obj.String.init(allocator, "world");
    var s1 = try Obj.String.init(allocator, "hello ");
    _ = try chunk.emitConstant(allocator, .{ .obj = &s3.obj }, 123);
    _ = try chunk.emitConstant(allocator, .{ .obj = &s2.obj }, 123);
    _ = try chunk.emitConstant(allocator, .{ .obj = &s1.obj }, 123);
    try chunk.emitGetGlobal(allocator, "my_var", 123);

    // call with arity
    try chunk.emitGetGlobal(allocator, "my_fn", 123);
    try chunk.append(allocator, .call, 123);
    try chunk.emitByte(allocator, 4, 123);

    _ = try chunk.emitConstant(allocator, .{ .obj = &s3.obj }, 123);
    _ = try chunk.emitConstant(allocator, .{ .obj = &s2.obj }, 123);
    _ = try chunk.emitConstant(allocator, .{ .obj = &s1.obj }, 123);
    try chunk.emitGetGlobal(allocator, "my_cls", 123);
    try chunk.append(allocator, .call, 123);
    try chunk.emitByte(allocator, 3, 123);

    try chunk.emitGetGlobal(allocator, "my_nat_fn", 125);
    try chunk.append(allocator, .call, 125);
    try chunk.emitByte(allocator, 0, 125);

    try chunk.append(allocator, .ret, 124);

    var vm = VM.init(function);
    defer vm.deinit(allocator);

    vm.run(allocator) catch |err| {
        std.debug.print("ERROR: {any}\n", .{err});
        return err;
    };
}
