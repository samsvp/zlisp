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
    function: *Function,
    record: Record,

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

        fn initArr(allocator: std.mem.Allocator, arr: []const LispType) ZArray {
            var items = std.ArrayListUnmanaged(LispType).initCapacity(allocator, arr.len) catch outOfMemory();

            for (arr) |*a| {
                items.appendAssumeCapacity(a.clone(allocator));
            }

            return items;
        }

        pub fn initList(allocator: std.mem.Allocator, arr: []const LispType) LispType {
            const new_arr = initArr(allocator, arr);
            const list = Array{ .array = new_arr, .array_type = .list };
            return .{ .list = list };
        }

        pub fn emptyList() LispType {
            return .{ .list = .{ .array = ZArray.empty, .array_type = .list } };
        }

        pub fn initVector(allocator: std.mem.Allocator, arr: []const LispType) LispType {
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

        pub fn append(self: Array, allocator: std.mem.Allocator, item: LispType) LispType {
            var items = std.ArrayListUnmanaged(LispType).initCapacity(allocator, self.getItems().len + 1) catch {
                outOfMemory();
            };
            items.appendSliceAssumeCapacity(self.array.items);
            items.appendAssumeCapacity(item.clone(allocator));

            return .{ .list = .{ .array = items, .array_type = self.array_type } };
        }

        pub fn appendMut(self: *Array, allocator: std.mem.Allocator, value: LispType) void {
            self.array.append(allocator, value.clone(allocator)) catch outOfMemory();
        }

        pub fn insert(self: Array, allocator: std.mem.Allocator, i: usize, item: LispType) LispType {
            var items = std.ArrayListUnmanaged(LispType).initCapacity(allocator, self.getItems().len + 1) catch {
                outOfMemory();
            };
            items.appendSliceAssumeCapacity(self.array.items);
            items.insertAssumeCapacity(i, item);

            return .{ .list = .{ .array = items, .array_type = self.array_type } };
        }

        pub fn prepend(allocator: std.mem.Allocator, item: LispType, self: Array) LispType {
            var items = std.ArrayListUnmanaged(LispType).initCapacity(allocator, self.getItems().len + 1) catch {
                outOfMemory();
            };

            items.appendAssumeCapacity(item);
            items.appendSliceAssumeCapacity(self.array.items);

            return .{ .list = .{ .array = items, .array_type = self.array_type } };
        }

        pub fn tail(self: Array, allocator: std.mem.Allocator) ?LispType {
            const items = self.getItems();
            if (items.len == 0) {
                return null;
            }

            var tail_ = std.ArrayListUnmanaged(LispType).initCapacity(allocator, self.getItems().len - 1) catch {
                outOfMemory();
            };
            tail_.appendSliceAssumeCapacity(items[1..]);
            return .{ .list = .{ .array = tail_, .array_type = self.array_type } };
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

        pub fn add(self: Dict, allocator: std.mem.Allocator, key: LispType, value: LispType) LispError!LispType {
            var dict = self.clone(allocator);
            return dict.dict.addMut(allocator, key, value);
        }

        pub fn isHashable(value: LispType) bool {
            return switch (value) {
                .int, .string, .keyword, .symbol => true,
                else => false,
            };
        }

        pub fn addMut(self: *Dict, allocator: std.mem.Allocator, key: LispType, value: LispType) LispError!void {
            if (isHashable(key)) {
                self.map.put(allocator, key, value) catch {
                    outOfMemory();
                };
            } else return LispError.UnhashableType;
        }

        pub fn remove(self: *Dict, key: LispType) LispError!void {
            if (isHashable(key)) {
                _ = self.map.remove(key);
            } else return LispError.UnhashableType;
        }

        pub fn addAssumeCapactity(self: *Dict, key: LispType, value: LispType) !void {
            if (isHashable(key)) {
                self.map.putAssumeCapacity(key, value);
            } else return LispError.UnhashableType;
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
        docstring: []const u8,
        is_macro: bool = false,

        pub fn init(
            allocator: std.mem.Allocator,
            val: LispType,
            args: [][]const u8,
            closure_names: [][]const u8,
            closure_vals: []LispType,
            docstring: []const u8,
            base_env: *Env,
        ) LispType {
            var env = Env.initFromParent(base_env.getLocal());
            for (closure_vals, closure_names) |v, name| {
                _ = env.putClone(name, v);
            }

            const ast = allocator.create(LispType) catch outOfMemory();
            ast.* = val.clone(allocator);

            var args_owned = allocator.alloc([]const u8, args.len) catch outOfMemory();
            for (args, 0..) |arg, i| {
                args_owned[i] = allocator.dupe(u8, arg) catch outOfMemory();
            }

            const m_fn = allocator.create(Function) catch outOfMemory();
            m_fn.* = .{
                .fn_ = Fn{
                    .ast = ast,
                    .args = args_owned,
                    .env = env,
                    .docstring = allocator.dupe(u8, docstring) catch outOfMemory(),
                },
            };
            return .{ .function = m_fn };
        }

        pub fn clone(self: Fn, allocator: std.mem.Allocator) LispType {
            var fn_ = init(
                allocator,
                self.ast.*,
                self.args,
                &[0][]u8{},
                &[0]LispType{},
                self.docstring,
                self.env.getLocal(),
            );
            fn_.function.fn_.is_macro = self.is_macro;

            var iter = self.env.mapping.iterator();
            while (iter.next()) |entry| {
                _ = fn_.function.fn_.env.putClone(entry.key_ptr.*, entry.value_ptr.*);
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

        pub fn createBuiltin(allocator: std.mem.Allocator, b: BuiltinFunc) LispType {
            const builtin = allocator.create(Function) catch outOfMemory();
            builtin.* = .{ .builtin = b };
            return .{ .function = builtin };
        }

        pub fn clone(self: *Function, allocator: std.mem.Allocator) LispType {
            return switch (self.*) {
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

    pub const Record = struct {
        bytes: []u8,
        type_info: TypeInfo,
        vtable: *const VTable,

        const VTable = struct {
            clone: *const fn (*anyopaque, std.mem.Allocator) LispType,
            equals: *const fn (*anyopaque, *anyopaque) bool,
        };

        const CloneFn = *const fn (*anyopaque, std.mem.Allocator) LispType;
        const EqualsFn = *const fn (*anyopaque, *anyopaque) bool;

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

        pub fn init(allocator: std.mem.Allocator, val: anytype) LispType {
            const T = @TypeOf(val);
            if (@typeInfo(T) != .@"struct") {
                @compileError("Record only accepts structs.");
            }

            const type_info = TypeInfo.init(T);

            const src = std.mem.asBytes(&val);
            const buf = allocator.alignedAlloc(u8, .of(T), type_info.size) catch outOfMemory();
            @memcpy(buf, src);

            const vtable = struct {
                fn cloneFn(ptr: *anyopaque, alloc: std.mem.Allocator) LispType {
                    const original: *T = @ptrCast(@alignCast(ptr));
                    const cloned = alloc.create(T) catch outOfMemory();
                    cloned.* = if (@hasDecl(T, "clone"))
                        @call(.auto, T.clone, .{ original.*, alloc })
                    else
                        original.*;
                    return LispType.Record.init(alloc, cloned.*);
                }

                fn equalsFn(a: *anyopaque, b: *anyopaque) bool {
                    const ta: *T = @ptrCast(@alignCast(a));
                    const tb: *T = @ptrCast(@alignCast(b));
                    return std.meta.eql(ta.*, tb.*);
                }

                const vtable_instance = VTable{
                    .clone = cloneFn,
                    .equals = equalsFn,
                };
            }.vtable_instance;

            return .{
                .record = .{
                    .bytes = buf,
                    .type_info = type_info,
                    .vtable = &vtable,
                },
            };
        }

        pub fn deinit(self: *Record, allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
        }

        pub fn fromHashMapToT(
            comptime T: type,
            allocator: std.mem.Allocator,
            map: std.StringHashMapUnmanaged(LispType),
        ) LispError!T {
            var result: T = undefined;

            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const name = field.name;
                const field_type = field.type;

                const entry = map.get(name) orelse {
                    return LispError.MissingRequiredField;
                };
                @field(result, name) = try entry.cast(field_type, allocator);
            }

            return result;
        }

        /// Populates a value of type `T` from a string-keyed hash map and wraps it in a `LispType.Record`.
        /// Expects each field of `T` to be present as a key in the map, with a `LispType`-encoded value.
        /// Fails if a field is missing or conversion fails.
        pub fn fromHashMap(
            comptime T: type,
            allocator: std.mem.Allocator,
            map: std.StringHashMapUnmanaged(LispType),
        ) LispError!LispType {
            const result: T = try fromHashMapToT(T, allocator, map);
            return init(allocator, result);
        }

        pub fn fromDictToT(
            comptime T: type,
            allocator: std.mem.Allocator,
            dict: LispType,
        ) LispError!T {
            const map = try dict.cast(std.StringHashMapUnmanaged(LispType), allocator);
            return fromHashMapToT(T, allocator, map);
        }

        /// Populates a value of type `T` from a string-keyed (string, keyword or symbol) LispType dict and wraps it in a
        /// `LispType.Record`. Expects each field of `T` to be present as a key in the map, with a `LispType`-encoded value.
        /// Fails if a field is missing or if any key is non-string.
        pub fn fromDict(
            comptime T: type,
            allocator: std.mem.Allocator,
            dict: LispType,
        ) LispError!LispType {
            const map = try dict.cast(std.StringHashMapUnmanaged(LispType), allocator);
            return fromHashMap(T, allocator, map);
        }

        pub fn clone(self: Record, allocator: std.mem.Allocator) LispType {
            return self.vtable.clone(@ptrCast(self.bytes.ptr), allocator);
        }

        pub fn eql(self: Record, other: Record) bool {
            if (!std.mem.eql(u8, self.type_info.name, other.type_info.name)) {
                return false;
            }

            return self.vtable.equals(self.bytes.ptr, other.bytes.ptr);
        }

        pub fn as(self: Record, comptime T: type) ?*T {
            if (!std.mem.eql(u8, self.type_info.name, @typeName(T))) {
                return null;
            }

            return @alignCast(std.mem.bytesAsValue(T, self.bytes));
        }
    };

    pub const String = struct {
        chars: Chars,

        const Chars = std.ArrayList(u8);

        fn initFrom(allocator: std.mem.Allocator, str: []const u8) String {
            var chars = std.ArrayList(u8).initCapacity(allocator, str.len) catch {
                outOfMemory();
            };
            chars.appendSliceAssumeCapacity(str);
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

        pub fn getItems(self: String) []const u8 {
            return self.getStr();
        }

        pub fn tail(self: String, allocator: std.mem.Allocator) ?LispType {
            const items = self.getItems();
            if (items.len == 0) {
                return null;
            }

            var tail_ = Chars.initCapacity(allocator, self.getItems().len - 1) catch {
                outOfMemory();
            };
            tail_.appendSliceAssumeCapacity(items[1..]);
            return .{ .string = .{ .chars = tail_ } };
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

    pub fn cast(self: LispType, comptime T: type, allocator: std.mem.Allocator) LispError!T {
        if (T == LispType) {
            return self;
        }

        const info = @typeInfo(T);
        return switch (self) {
            .int => |i| switch (info) {
                .int => @intCast(i),
                .float => @floatFromInt(i),
                .@"enum" => @enumFromInt(i),
                else => LispError.InvalidCast,
            },
            .float => |f| switch (info) {
                .float => @floatCast(f),
                else => LispError.InvalidCast,
            },
            .string, .symbol, .keyword => |s| switch (info) {
                .pointer => |p| if (p.child == u8)
                    if (p.sentinel()) |_|
                        allocator.dupeZ(u8, s.getStr()) catch outOfMemory()
                    else
                        s.getStr()
                else
                    LispError.InvalidCast,
                .@"enum" => |e| {
                    const name = switch (self) {
                        .string, .symbol => s.getStr(),
                        .keyword => s.getStr()[1..],
                        else => unreachable,
                    };
                    inline for (e.fields, 0..) |f, i| {
                        if (std.mem.eql(u8, f.name, name)) {
                            return @enumFromInt(i);
                        }
                    }
                    return LispError.InvalidCast;
                },
                else => LispError.InvalidCast,
            },
            .boolean => |b| switch (info) {
                .bool => b,
                else => LispError.InvalidCast,
            },
            .list, .vector => |array| {
                if (info != .pointer) {
                    return LispError.InvalidCast;
                }

                const p = info.pointer;
                const child_T = p.child;
                const is_sentinel = p.sentinel() != null;
                const len = if (is_sentinel) array.array.items.len + 1 else array.array.items.len;
                var arr = allocator.alloc(child_T, len) catch outOfMemory();
                for (array.getItems(), 0..) |val, i| {
                    arr[i] = try val.cast(child_T, allocator);
                }
                if (p.sentinel()) |_| {
                    arr[arr.len - 1] = 0;
                    return arr[0 .. arr.len - 1 :0];
                } else {
                    return arr;
                }
            },
            .atom => |a| a.value.cast(T, allocator),
            .record => |r| if (r.as(T)) |v| v.* else LispError.InvalidCast,
            .nil, .function => LispError.InvalidCast,
            .dict => |dict| {
                const getType = struct {
                    pub fn getType(t: std.builtin.Type) type {
                        const k_info = switch (t) {
                            .@"fn" => |func| if (func.return_type) |ret| @typeInfo(ret) else return LispError.InvalidCast,
                            else => return LispError.InvalidCast,
                        };
                        if (k_info != .optional) {
                            return LispError.InvalidCast;
                        }
                        return k_info.optional.child;
                    }
                }.getType;

                switch (info) {
                    .@"union" => |u| {
                        if (dict.map.size != 1) {
                            return LispError.InvalidCast;
                        }

                        var iter = dict.map.iterator();
                        const kv = iter.next().?;

                        const key_name = switch (kv.key_ptr.*) {
                            .string, .symbol => |s| s.getStr(),
                            .keyword => |k| k.getStr()[1..],
                            else => return LispError.InvalidCast,
                        };

                        inline for (u.fields) |field| {
                            if (std.mem.eql(u8, field.name, key_name)) {
                                const value = try kv.value_ptr.cast(field.type, allocator);
                                return @unionInit(T, field.name, value);
                            }
                        }
                        return LispError.InvalidCast;
                    },
                    .@"struct" => {
                        // check if is hash map
                        if (!std.meta.hasMethod(T, "put") or
                            !std.meta.hasMethod(T, "get") or
                            !std.meta.hasMethod(T, "getKey"))
                        {
                            return Record.fromDictToT(T, allocator, self);
                        }

                        const K = getType(@typeInfo(@TypeOf(T.getKey)));
                        const V = getType(@typeInfo(@TypeOf(T.get)));

                        var map: T = .empty;
                        var iter = dict.map.iterator();
                        while (iter.next()) |kv| {
                            const kv_key = switch (kv.key_ptr.*) {
                                .keyword => |k| String.initString(allocator, k.getStr()[1..]),
                                else => |v| v,
                            };
                            const key = try kv_key.cast(K, allocator);
                            const value = try kv.value_ptr.cast(V, allocator);
                            map.put(allocator, key, value) catch outOfMemory();
                        }
                        return map;
                    },
                    else => return LispError.InvalidCast,
                }
            },
        };
    }

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
        var buffer: std.ArrayListUnmanaged(u8) = .empty;
        try self.toStringInternal(allocator, &buffer);
        return try buffer.toOwnedSlice(allocator);
    }

    fn toStringInternal(
        self: LispType,
        allocator: std.mem.Allocator,
        buffer: *std.ArrayList(u8),
    ) !void {
        switch (self) {
            .symbol, .keyword => |s| try buffer.appendSlice(allocator, s.getStr()),
            .string => |s| try std.fmt.format(buffer.writer(allocator), "\"{s}\"", .{s.getStr()}),
            .atom => |a| {
                try buffer.appendSlice(allocator, "(atom ");
                try a.value.toStringInternal(allocator, buffer);
                try buffer.append(allocator, ')');
            },
            .nil => try buffer.appendSlice(allocator, "nil"),
            .list => |l| {
                try buffer.appendSlice(allocator, "(");
                for (l.getItems(), 0..) |item, i| {
                    if (i > 0) try buffer.append(allocator, ' ');
                    try item.toStringInternal(allocator, buffer);
                }
                try buffer.appendSlice(allocator, ")");
            },
            .vector => |a| {
                try buffer.appendSlice(allocator, "[");
                for (a.getItems(), 0..) |item, i| {
                    if (i > 0) try buffer.append(allocator, ' ');
                    try item.toStringInternal(allocator, buffer);
                }
                try buffer.appendSlice(allocator, "]");
            },
            .dict => |d| {
                try buffer.appendSlice(allocator, "{");
                var iter = d.map.iterator();
                var first: bool = true;
                while (iter.next()) |entry| {
                    if (!first) {
                        try buffer.append(allocator, ' ');
                    } else {
                        first = false;
                    }

                    try entry.key_ptr.toStringInternal(allocator, buffer);
                    try buffer.appendSlice(allocator, " ");
                    try entry.value_ptr.toStringInternal(allocator, buffer);
                }
                try buffer.appendSlice(allocator, "}");
            },
            .function => try buffer.appendSlice(allocator, "#<function>"),
            .record => |r| try std.fmt.format(buffer.writer(allocator), "#record {s}", .{r.type_info.name}),
            inline .int, .float, .boolean => |i| try std.fmt.format(buffer.writer(allocator), "{}", .{i}),
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
            .atom,
            .record,
            => |*f| f.deinit(allocator),
            .function => |f| f.deinit(allocator),
            .nil, .int, .float, .boolean => return,
        }
    }
};

/// An example on how to use a record to hold user defined data types.
/// This is just a C like enum, with names and an int value.
pub const Enum = struct {
    options: [][]const u8,
    selected: usize,

    const Self = @This();

    pub fn init(options: [][]const u8, selected: usize) !Self {
        if (selected >= options.len) {
            return error.ValueOutOfRange;
        }

        return Self{
            .options = options,
            .selected = selected,
        };
    }

    /// Any value that can become a lisp type must implement a clone function.
    /// This will be called when setting the value to the global environment (i.e. when using the
    /// `def` function) or when returning the value from an expression.
    pub fn clone(self: Self, allocator: std.mem.Allocator) Self {
        var new_options = std.ArrayListUnmanaged([]const u8).initCapacity(allocator, self.options.len) catch outOfMemory();
        for (self.options) |opts| {
            const o = allocator.dupe(u8, opts) catch outOfMemory();
            new_options.appendAssumeCapacity(o);
        }

        return .{
            .options = new_options.items,
            .selected = self.selected,
        };
    }

    pub fn setSelected(self: *Self, option: []const u8) !void {
        for (self.options, 0..) |opt, i| if (std.mem.eql(u8, opt, option)) {
            self.selected = i;
            return;
        };

        return error.ValueOutOfRange;
    }

    pub fn setIndex(self: *Self, s: usize) !void {
        if (s >= self.options.len) {
            return error.ValueOutOfRange;
        }

        self.selected = s;
    }

    pub fn getSelected(self: Self) []const u8 {
        return self.options[self.selected];
    }

    pub fn getSelectedIndex(self: Self) usize {
        return self.selected;
    }
};
