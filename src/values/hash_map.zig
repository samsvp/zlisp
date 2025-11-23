const std = @import("std");

const pstructs = @import("pstruct");
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;

pub const PHashMap = struct {
    obj: Obj,
    hash_map: HashMapT,
    const HashMapT = pstructs.Hamt(Value, Value, HashCtx, KVContext.get());

    pub fn init(gpa: std.mem.Allocator, values: []const Value) !*PHashMap {
        const phash_map = try gpa.create(PHashMap);

        var hm = HashMapT.init();
        for (0..values.len / 2) |idx| {
            const i = 2 * idx;
            try hm.assocMut(gpa, values[i], values[i + 1]);
        }

        phash_map.* = PHashMap{
            .obj = Obj.init(.hash_map),
            .hash_map = hm,
        };

        return phash_map;
    }

    pub fn initFrom(gpa: std.mem.Allocator, hm: HashMapT) !*PHashMap {
        const phash_map = try gpa.create(PHashMap);

        phash_map.* = PHashMap{
            .obj = Obj.init(.hash_map),
            .hash_map = hm,
        };

        return phash_map;
    }

    pub fn deinit(self: *PHashMap, gpa: std.mem.Allocator) void {
        self.hash_map.deinit(gpa);
        gpa.destroy(self);
    }

    pub fn toString(self: PHashMap, gpa: std.mem.Allocator) ![]const u8 {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(gpa);

        try buffer.append(gpa, '{');
        var writer = buffer.writer(gpa);

        var iter = self.hash_map.iterator();
        while (iter.next()) |kv| {
            const key_str = try kv.key.toString(gpa);
            defer gpa.free(key_str);

            const val_str = try kv.value.toString(gpa);
            defer gpa.free(val_str);

            try writer.print("{s}: {s}, ", .{ key_str, val_str });
        }
        try buffer.append(gpa, '}');
        const owned_str = try gpa.dupe(u8, buffer.items);

        return owned_str;
    }

    const HashCtx = pstructs.HashContext(Value){
        .eql = Value.eql,
        .hash = Value.hash,
    };

    const KV = pstructs.KV(Value, Value);

    const KVContext = struct {
        fn init(_: std.mem.Allocator, v: Value, k: Value) !KV {
            return .{ .key = v.borrow(), .value = k.borrow() };
        }

        fn deinit(gpa: std.mem.Allocator, kv: *KV) void {
            kv.key.deinit(gpa);
            kv.value.deinit(gpa);
        }

        fn clone(gpa: std.mem.Allocator, kv: *KV) !KV {
            return KVContext.init(gpa, kv.key, kv.value);
        }

        fn get() pstructs.KVContext(Value, Value) {
            return .{
                .init = KVContext.init,
                .deinit = KVContext.deinit,
                .clone = KVContext.clone,
            };
        }
    };
};
