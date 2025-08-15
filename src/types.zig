const std = @import("std");
const Env = @import("env.zig").Env;
const errors = @import("errors.zig");
const LispError = @import("errors.zig").LispError;
const outOfMemory = @import("utils.zig").outOfMemory;

pub const LispType = union(enum) {
    string: String,
    keyword: String,
    symbol: String,
    nil,
    int: i32,
    float: f32,
    boolean: bool,
    list: Array,
    vector: Array,
    dict: Dict,
    atom: Atom,
    function: Function,
    record: UserStruct,

    pub const lisp_true = LispType{ .boolean = true };
    pub const lisp_false = LispType{ .boolean = false };
    pub const BuiltinFunc = *const fn (
        allocator: std.mem.Allocator,
        args: []LispType,
        env: *Env,
        err_ctx: *errors.Context,
    ) LispError!LispType;

    pub const Array = struct {
        array: ZArray,
        array_type: ArrayType,

        const ArrayType = enum {
            list,
            vector,
        };

        const ZArray = std.ArrayListUnmanaged(LispType);

        fn initArr(allocator: std.mem.Allocator, arr: []LispType) ZArray {
            var items = std.ArrayListUnmanaged(LispType).initCapacity(allocator, arr.len) catch outOfMemory();

            for (arr) |*a| {
                items.appendAssumeCapacity(a.clone(allocator));
            }

            return items;
        }

        pub fn initList(allocator: std.mem.Allocator, arr: []LispType) LispType {
            const new_arr = initArr(allocator, arr);
            const list = Array{ .array = new_arr, .array_type = .list };
            return .{ .list = list };
        }

        pub fn emptyList() LispType {
            return .{ .list = .{ .array = ZArray.empty, .array_type = .list } };
        }

        pub fn initVector(allocator: std.mem.Allocator, arr: []LispType) LispType {
            const new_arr = initArr(allocator, arr);
            const vector = Array{ .array = new_arr, .array_type = .vector };
            return .{ .vector = vector };
        }

        pub fn emptyVector() LispType {
            return .{ .vector = .{ .array = ZArray.empty, .array_type = .vector } };
        }

        pub fn getItems(self: Array) []LispType {
            return self.array.items;
        }

        // value should be a pointer and we should clone
        pub fn append(self: *Array, allocator: std.mem.Allocator, value: LispType) void {
            self.array.append(allocator, value) catch outOfMemory();
        }

        pub fn prepend(allocator: std.mem.Allocator, item: LispType, self: Array) LispType {
            var items = std.ArrayListUnmanaged(LispType).initCapacity(allocator, self.getItems().len + 1) catch {
                outOfMemory();
            };

            items.appendAssumeCapacity(item.clone(allocator));
            for (self.array.items) |val| {
                items.appendAssumeCapacity(val.clone(allocator));
            }

            return .{ .list = .{ .array = items, .array_type = self.array_type } };
        }

        pub fn addMutSlice(self: *Array, allocator: std.mem.Allocator, other: []LispType) void {
            self.array.ensureUnusedCapacity(allocator, other.len) catch {
                outOfMemory();
            };

            for (other) |item| {
                self.array.appendAssumeCapacity(item.clone(allocator));
            }
        }

        pub fn addMut(self: *Array, allocator: std.mem.Allocator, other: Array) void {
            self.addMutSlice(allocator, other.array.items);
        }

        pub fn clone(self: Array, allocator: std.mem.Allocator) LispType {
            return switch (self.array_type) {
                .list => initList(allocator, self.array.items),
                .vector => initVector(allocator, self.array.items),
            };
        }

        pub fn deinit(self: *Array, allocator: std.mem.Allocator) void {
            for (self.array.items) |*item| {
                item.deinit(allocator);
            }
            self.array.deinit(allocator);
        }
    };

    pub const Atom = struct {
        value: *LispType,

        pub fn init(allocator: std.mem.Allocator, val: LispType) LispType {
            const new_val = std.mem.Allocator.create(allocator, LispType) catch outOfMemory();
            new_val.* = val.clone(allocator);
            return .{ .atom = .{ .value = new_val } };
        }

        pub fn deinit(self: *Atom, allocator: std.mem.Allocator) void {
            self.value.deinit(allocator);
            allocator.destroy(self.value);
        }

        pub fn get(self: Atom) LispType {
            return self.value.*;
        }

        pub fn reset(self: *Atom, allocator: std.mem.Allocator, val: LispType) LispType {
            const new_value = val.clone(allocator);
            self.value.deinit(allocator);
            self.value.* = new_value;
            return new_value;
        }

        pub fn clone(self: Atom, allocator: std.mem.Allocator) LispType {
            return init(allocator, self.value.*);
        }
    };

    pub const Dict = struct {
        map: Map,

        pub const Map = std.HashMapUnmanaged(
            LispType,
            LispType,
            Context,
            std.hash_map.default_max_load_percentage,
        );

        pub fn add(self: *Dict, allocator: std.mem.Allocator, key: LispType, value: LispType) LispError!void {
            switch (key) {
                .int, .string, .keyword, .symbol => {
                    self.map.put(allocator, key, value) catch {
                        outOfMemory();
                    };
                },
                else => return LispError.UnhashableType,
            }
        }

        pub fn addAssumeCapactity(self: *Dict, key: LispType, value: LispType) !void {
            switch (key) {
                .int, .string, .keyword, .symbol => {
                    self.map.putAssumeCapacity(key, value);
                },
                else => return LispError.UnhashableType,
            }
        }

        pub fn init() LispType {
            const values: Map = .empty;
            return .{ .dict = .{ .map = values } };
        }

        pub fn deinit(self: *Dict, allocator: std.mem.Allocator) void {
            var iter = self.map.iterator();
            while (iter.next()) |entry| {
                entry.key_ptr.deinit(allocator);
                entry.value_ptr.deinit(allocator);
            }
            self.map.deinit(allocator);
        }

        pub fn clone(self: Dict, allocator: std.mem.Allocator) LispType {
            var dict = init();
            dict.dict.map.ensureTotalCapacity(allocator, self.map.size) catch outOfMemory();

            var iter = self.map.iterator();
            while (iter.next()) |entry| {
                dict.dict.addAssumeCapactity(entry.key_ptr.clone(allocator), entry.value_ptr.clone(allocator)) catch unreachable;
            }

            return dict;
        }

        const Context = struct {
            pub fn hash(_: Context, value: LispType) u64 {
                var h: std.hash.Wyhash = .init(0);
                const b = switch (value) {
                    .int => |i| std.mem.asBytes(&i),
                    .string, .keyword => |s| s.getStr(),
                    else => "0",
                };
                h.update(b);
                return h.final();
            }

            pub fn eql(_: Context, a: LispType, b: LispType) bool {
                return a.eql(b);
            }
        };
    };

    pub const Fn = struct {
        ast: *LispType,
        args: [][]const u8,
        env: *Env,
        is_macro: bool = false,

        pub fn init(
            allocator: std.mem.Allocator,
            val: LispType,
            args: [][]const u8,
            closure_names: [][]const u8,
            closure_vals: []LispType,
            base_env: *Env,
        ) LispType {
            var env = Env.init(allocator);
            env.parent = base_env;
            for (closure_vals, closure_names) |v, name| {
                _ = env.put(name, v);
            }

            const ast = allocator.create(LispType) catch outOfMemory();
            ast.* = val.clone(allocator);

            var args_owned = allocator.alloc([]const u8, args.len) catch outOfMemory();
            for (args, 0..) |arg, i| {
                args_owned[i] = allocator.dupe(u8, arg) catch outOfMemory();
            }

            const m_fn = Fn{
                .ast = ast,
                .args = args_owned,
                .env = env,
            };
            return .{ .function = .{ .fn_ = m_fn } };
        }

        pub fn init2(
            allocator: std.mem.Allocator,
            ast: *LispType,
            args: []LispType,
            root: *Env,
        ) LispType {
            var args_owned = allocator.alloc([]const u8, args.len) catch {
                return .nil;
            };

            for (args, 0..) |arg, i| {
                switch (arg) {
                    .symbol => |s| args_owned[i] = allocator.dupe(u8, s.getStr()) catch unreachable,
                    else => {
                        return .nil;
                    },
                }
            }

            const env = root;

            const m_fn = Fn{
                .ast = ast,
                .args = args_owned,
                .env = env,
            };

            return .{ .function = .{ .fn_ = m_fn } };
        }

        pub fn clone(self: Fn, allocator: std.mem.Allocator) LispType {
            const fn_ = init(allocator, self.ast.*, self.args, &[0][]u8{}, &[0]LispType{}, self.env.getRoot());
            fn_.function.fn_.env.mapping.ensureTotalCapacity(allocator, self.env.mapping.count()) catch {
                outOfMemory();
            };

            var iter = self.env.mapping.iterator();
            while (iter.next()) |entry| {
                _ = fn_.function.fn_.env.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.*);
            }
            return fn_;
        }

        pub fn deinit(self: *Fn, allocator: std.mem.Allocator) void {
            self.ast.deinit(allocator);
            allocator.destroy(self.ast);
            self.env.deinit();
        }
    };

    pub const Function = union(enum) {
        fn_: Fn,
        builtin: BuiltinFunc,

        pub fn clone(self: Function, allocator: std.mem.Allocator) LispType {
            return switch (self) {
                .fn_ => |fn_| fn_.clone(allocator),
                .builtin => .{ .function = self },
            };
        }

        pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .fn_ => |*fn_| fn_.deinit(allocator),
                .builtin => {},
            }
        }
    };

    pub const String = struct {
        chars: Chars,

        const Chars = std.ArrayListUnmanaged(u8);

        fn initFrom(allocator: std.mem.Allocator, str: []const u8) String {
            var chars = std.ArrayListUnmanaged(u8).initCapacity(allocator, str.len) catch {
                outOfMemory();
            };
            const str_clone = allocator.dupe(u8, str) catch outOfMemory();
            chars.appendSliceAssumeCapacity(str_clone);
            return .{ .chars = chars };
        }

        pub fn initString(allocator: std.mem.Allocator, str: []const u8) LispType {
            return .{ .string = initFrom(allocator, str) };
        }

        pub fn initSymbol(allocator: std.mem.Allocator, str: []const u8) LispType {
            return .{ .symbol = initFrom(allocator, str) };
        }

        pub fn initKeyword(allocator: std.mem.Allocator, str: []const u8) LispType {
            return .{ .keyword = initFrom(allocator, str) };
        }

        pub fn getStr(self: String) []const u8 {
            return self.chars.items;
        }

        /// Concatenates s1 and s2 on a new string
        pub fn add(allocator: std.mem.Allocator, s1: String, s2: String) LispType {
            var chars = std.ArrayListUnmanaged(u8).initCapacity(allocator, s1.getStr().len + s2.getStr().len) catch {
                outOfMemory();
            };
            chars.appendSliceAssumeCapacity(s1.getStr());
            chars.appendSliceAssumeCapacity(s2.getStr());
            return .{ .string = .{ .chars = chars } };
        }

        pub fn addChars(self: *String, allocator: std.mem.Allocator, s: []const u8) void {
            self.chars.appendSlice(allocator, s) catch outOfMemory();
        }

        /// Add s to self
        pub fn addMut(self: *String, allocator: std.mem.Allocator, s: String) void {
            self.chars.appendSlice(allocator, s.getStr()) catch outOfMemory();
        }

        pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
            self.chars.deinit(allocator);
        }

        pub fn clone(self: String, allocator: std.mem.Allocator) LispType {
            const chars = self.chars.clone(allocator) catch outOfMemory();
            return .{ .string = .{ .chars = chars } };
        }
    };

    pub const UserStruct = struct {
        bytes: []u8,
        type_info: TypeInfo,

        pub const TypeInfo = struct {
            name: []const u8,
            size: usize,

            pub fn init(comptime T: type) TypeInfo {
                return .{
                    .name = @typeName(T),
                    .size = @sizeOf(T),
                };
            }
        };

        pub fn initFromBytes(allocator: std.mem.Allocator, src: []const u8, type_info: TypeInfo) LispType {
            const buf = allocator.alloc(u8, type_info.size) catch outOfMemory();
            @memcpy(buf, src);

            return .{
                .record = .{
                    .bytes = buf,
                    .type_info = type_info,
                },
            };
        }

        pub fn init(allocator: std.mem.Allocator, val: anytype) LispType {
            const T = @TypeOf(val);
            const type_info = TypeInfo.init(T);

            const src = std.mem.asBytes(&val);
            return initFromBytes(allocator, src, type_info);
        }

        pub fn deinit(self: *UserStruct, allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
        }

        pub fn clone(self: UserStruct, allocator: std.mem.Allocator) LispType {
            return initFromBytes(allocator, self.bytes, self.type_info);
        }

        pub fn eql(self: UserStruct, other: UserStruct) bool {
            return std.mem.eql(u8, self.bytes, other.bytes);
        }

        pub fn as(self: UserStruct, comptime T: type) ?*T {
            if (!std.mem.eql(u8, self.type_info.name, @typeName(T))) {
                return null;
            }

            return @alignCast(std.mem.bytesAsValue(T, self.bytes));
        }
    };

    pub fn clone(self: LispType, allocator: std.mem.Allocator) LispType {
        return switch (self) {
            inline .string,
            .vector,
            .list,
            .dict,
            .function,
            .atom,
            .record,
            => |s| s.clone(allocator),
            .keyword => |s| {
                const str = s.clone(allocator);
                return .{ .keyword = str.string };
            },
            .symbol => |s| {
                const str = s.clone(allocator);
                return .{ .symbol = str.string };
            },
            .int, .float, .boolean, .nil => return self,
        };
    }

    pub fn eql(a: LispType, b: LispType) bool {
        return switch (a) {
            .int => |v1| switch (b) {
                .int => |v2| v1 == v2,
                else => false,
            },
            .boolean => |v1| switch (b) {
                .boolean => |v2| v1 == v2,
                else => false,
            },
            .float => |v1| switch (b) {
                .float => |v2| v1 == v2,
                else => false,
            },
            .string => |s1| switch (b) {
                .string => |s2| std.mem.eql(u8, s1.getStr(), s2.getStr()),
                else => false,
            },
            .symbol => |s1| switch (b) {
                .symbol => |s2| std.mem.eql(u8, s1.getStr(), s2.getStr()),
                else => false,
            },
            .keyword => |s1| switch (b) {
                .keyword => |s2| std.mem.eql(u8, s1.getStr(), s2.getStr()),
                else => false,
            },
            .record => |r1| switch (b) {
                .record => |r2| r1.eql(r2),
                else => false,
            },
            .list => |l1| switch (b) {
                .list => |l2| {
                    const items1 = l1.getItems();
                    const items2 = l2.getItems();
                    if (items1.len != items2.len) return false;
                    for (items1, items2) |v1, v2| {
                        if (!v1.eql(v2)) {
                            return false;
                        }
                    }
                    return true;
                },
                else => false,
            },
            .vector => |l1| switch (b) {
                .vector => |l2| {
                    const items1 = l1.getItems();
                    const items2 = l2.getItems();
                    if (items1.len != items2.len) return false;
                    for (items1, items2) |v1, v2| {
                        if (!v1.eql(v2)) {
                            return false;
                        }
                    }
                    return true;
                },
                else => false,
            },
            .dict => |d1| switch (b) {
                .dict => |d2| {
                    const values1 = d1.map;
                    const values2 = d2.map;
                    if (values1.size != values2.size) return false;
                    var iter = values1.iterator();
                    while (iter.next()) |entry| {
                        if (values2.get(entry.key_ptr.*)) |val| {
                            if (!val.eql(entry.value_ptr.*)) return false;
                        } else return false;
                    }
                    return true;
                },
                else => false,
            },
            .atom => |a1| switch (b) {
                .atom => |a2| a1.value.eql(a2.value.*),
                else => false,
            },
            .nil => switch (b) {
                .nil => true,
                else => false,
            },
            .function => false,
        };
    }

    /// Converts the type to a zig string. This will convert the whole type, as such, it needs an allocator
    /// and the result must be freed by the caller.
    pub fn toStringFull(self: LispType, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        try self.toStringInternal(&buffer);
        return try buffer.toOwnedSlice();
    }

    /// Converts the type to a zig string, prints as much as the buffer can old.
    pub fn toString(self: LispType, buffer: []u8) []const u8 {
        var fba = std.heap.FixedBufferAllocator.init(buffer);
        const allocator = fba.allocator();
        var str_buffer = std.ArrayList(u8).init(allocator);
        self.toStringInternal(&str_buffer) catch {};
        return str_buffer.items;
    }

    fn toStringInternal(self: LispType, buffer: *std.ArrayList(u8)) !void {
        switch (self) {
            .symbol, .keyword => |s| try buffer.appendSlice(s.getStr()),
            .string => |s| try std.fmt.format(buffer.writer(), "\"{s}\"", .{s.getStr()}),
            .atom => |a| {
                try buffer.appendSlice("(atom ");
                try a.value.toStringInternal(buffer);
                try buffer.append(')');
            },
            .nil => try buffer.appendSlice("nil"),
            .list => |l| {
                try buffer.appendSlice("(");
                for (l.getItems(), 0..) |item, i| {
                    if (i > 0) try buffer.append(' ');
                    try item.toStringInternal(buffer);
                }
                try buffer.appendSlice(")");
            },
            .vector => |a| {
                try buffer.appendSlice("[");
                for (a.getItems(), 0..) |item, i| {
                    if (i > 0) try buffer.append(' ');
                    try item.toStringInternal(buffer);
                }
                try buffer.appendSlice("]");
            },
            .dict => |d| {
                try buffer.appendSlice("{");
                var iter = d.map.iterator();
                var first: bool = true;
                while (iter.next()) |entry| {
                    if (!first) {
                        try buffer.append(' ');
                    } else {
                        first = false;
                    }

                    try entry.key_ptr.toStringInternal(buffer);
                    try buffer.appendSlice(" ");
                    try entry.value_ptr.toStringInternal(buffer);
                }
                try buffer.appendSlice("}");
            },
            .function => try buffer.appendSlice("#<function>"),
            .record => |r| try std.fmt.format(buffer.writer(), "#record {s}", .{r.type_info.name}),
            inline .int, .float, .boolean => |i| try std.fmt.format(buffer.writer(), "{}", .{i}),
        }
    }

    pub fn deinit(self: *LispType, allocator: std.mem.Allocator) void {
        switch (self.*) {
            inline .list,
            .vector,
            .dict,
            .string,
            .keyword,
            .symbol,
            .function,
            .atom,
            .record,
            => |*f| {
                f.deinit(allocator);
            },
            .nil, .int, .float, .boolean => return,
        }
    }
};
