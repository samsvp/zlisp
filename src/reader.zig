const std = @import("std");
const ZType = @import("types.zig").ZType;

const pcre = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

const PCRE2_ZERO_TERMINATED = ~@as(pcre.PCRE2_SIZE, 0);

var g_regex: ?*pcre.pcre2_code_8 = null;

pub const ParserError = error{
    EOFCollectionReadError,
    EOFStringReadError,
    UnhashableKey,
    OutOfMemory,
};

/// Wrapper that holds the raw tokens (strings) of a Lisp expression (which may not be valid).
const TokenList = struct {
    tokens: std.ArrayListUnmanaged([]const u8),

    pub fn init() TokenList {
        const tokens: std.ArrayListUnmanaged([]const u8) = .empty;
        return .{ .tokens = tokens };
    }

    pub fn append(self: *TokenList, allocator: std.mem.Allocator, token: []const u8) !void {
        try self.tokens.append(allocator, token);
    }

    pub fn deinit(self: *TokenList, allocator: std.mem.Allocator) void {
        self.tokens.deinit(allocator);
    }
};

/// A helper token reader.
pub const Reader = struct {
    token_list: TokenList,
    current: usize,

    pub fn next(self: *Reader) ?[]const u8 {
        if (self.token_list.tokens.items.len <= self.current) {
            return null;
        }
        self.current += 1;
        return self.token_list.tokens.items[self.current - 1];
    }

    pub fn peek(self: Reader) ?[]const u8 {
        if (self.token_list.tokens.items.len <= self.current) {
            return null;
        }
        return self.token_list.tokens.items[self.current];
    }
};

fn compile_regex() *pcre.pcre2_code_8 {
    if (g_regex) |r| {
        return r;
    }

    const pattern: [*]const u8 =
        \\[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)
    ;
    var errornumber: i32 = undefined;
    var erroroffset: usize = undefined;
    const regex = pcre.pcre2_compile_8(
        pattern,
        PCRE2_ZERO_TERMINATED,
        0,
        &errornumber,
        &erroroffset,
        null,
    );

    if (regex) |r| {
        g_regex = r;
        return r;
    }

    @panic("Failed to build regex!");
}

fn tokenize(
    subject: []const u8,
    allocator: std.mem.Allocator,
) !TokenList {
    const regex = compile_regex();

    const match_data = pcre.pcre2_match_data_create_from_pattern_8(regex, null);
    defer pcre.pcre2_match_data_free_8(match_data);

    var offset: usize = 0;
    var list: TokenList = .init();

    while (true) {
        const rc = pcre.pcre2_match_8(
            regex,
            subject.ptr,
            subject.len,
            offset,
            0,
            match_data,
            null,
        );

        if (rc <= 0) {
            if (rc == pcre.PCRE2_ERROR_NOMATCH) {
                break;
            } else {
                // finished
                return list;
            }
        }

        const ovector = pcre.pcre2_get_ovector_pointer_8(match_data);
        const start = ovector[0];
        const end = ovector[1];

        if (start == end) {
            // Zero-length match — avoid infinite loop
            offset += 1;
            continue;
        }

        if (rc >= 2) {
            // Group 0 is the entire match
            // Group 1 is the first capturing group (what we want)
            const group_start = ovector[2];
            const group_end = ovector[3];

            if (group_start != group_end) {
                try list.append(allocator, subject[group_start..group_end]);
            }
        }

        offset = end;
    }

    return list;
}

fn readAtom(
    allocator: std.mem.Allocator,
    reader: *Reader,
) ParserError!ZType {
    const atom = reader.next().?;
    if (atom.len == 0) {
        return .nil;
    }

    switch (atom[0]) {
        ':' => {
            return ZType.String.initKeyword(allocator, atom);
        },
        '"' => {
            if (atom.len < 2 or atom[atom.len - 1] != '"') {
                return ParserError.EOFStringReadError;
            }

            var backslash_amount: usize = 0;
            var i: usize = atom.len - 2;
            while (i != 0 and atom[i] == '\\') {
                i -= 1;
                backslash_amount += 1;
            }
            if (backslash_amount % 2 != 0) {
                return ParserError.EOFStringReadError;
            }
            return ZType.String.initString(allocator, atom[1 .. atom.len - 1]);
        },
        else => {
            const maybe_num = std.fmt.parseInt(i32, atom, 10) catch null;
            if (maybe_num) |num| {
                return .{ .int = num };
            }
            const maybe_float = std.fmt.parseFloat(f32, atom) catch null;
            if (maybe_float) |float| {
                return .{ .float = float };
            }

            if (std.mem.eql(u8, atom, "nil")) {
                return .nil;
            }

            if (std.mem.eql(u8, atom, "true")) {
                return .{ .boolean = true };
            } else if (std.mem.eql(u8, atom, "false")) {
                return .{ .boolean = false };
            }

            return ZType.String.initSymbol(allocator, atom);
        },
    }
}

const CollectionType = enum {
    list,
    vector,
};

fn readCollection(
    allocator: std.mem.Allocator,
    reader: *Reader,
    collection_type: CollectionType,
) ParserError!ZType {
    var list: std.ArrayListUnmanaged(ZType) = .empty;
    errdefer {
        for (list.items) |*item| {
            item.deinit(allocator);
        }
        list.deinit(allocator);
    }

    const close_bracket = switch (collection_type) {
        .list => ")",
        .vector => "]",
    };
    _ = reader.next();
    while (reader.peek()) |token| {
        if (std.mem.eql(u8, token, close_bracket)) {
            _ = reader.next();
            return switch (collection_type) {
                .list => .{ .list = .{ .array = list, .array_type = .list } },
                .vector => .{ .vector = .{ .array = list, .array_type = .vector } },
            };
        }
        const val = try readForm(allocator, reader);
        list.append(allocator, val) catch {
            return ParserError.OutOfMemory;
        };
    }
    return ParserError.EOFCollectionReadError;
}

fn readDict(allocator: std.mem.Allocator, reader: *Reader) ParserError!ZType {
    var dict = ZType.Dict.Map.empty;
    errdefer {
        var iter = dict.iterator();
        while (iter.next()) |entry| {
            entry.key_ptr.deinit(allocator);
            entry.value_ptr.deinit(allocator);
        }
        dict.deinit(allocator);
    }

    var maybe_key: ?ZType = null;
    _ = reader.next();
    while (reader.peek()) |token| {
        if (std.mem.eql(u8, token, "}")) {
            _ = reader.next();
            if (maybe_key) |*key| {
                key.deinit(allocator);
                return ParserError.EOFCollectionReadError;
            }
            return .{ .dict = .{ .map = dict } };
        }
        var val = try readForm(allocator, reader);
        if (maybe_key) |*key| {
            errdefer {
                key.deinit(allocator);
                val.deinit(allocator);
            }

            dict.put(allocator, key.*, val) catch {
                return ParserError.OutOfMemory;
            };
            maybe_key = null;
        } else maybe_key = val;
    }
    return ParserError.EOFCollectionReadError;
}

// we have a leak here
//fn translate(allocator: std.mem.Allocator, reader: *Reader, name: []const u8) ParserError!ZType {
//    var deref = try ZType.String.initSymbol(allocator, name);
//    defer deref.deinit(allocator) catch unreachable;
//
//    _ = reader.next();
//    var next = try readForm(allocator, reader);
//    defer next.deinit(allocator) catch unreachable;
//
//    var lst = [_]ZType{ deref, next };
//    return ZType.Array.initList(allocator, &lst);
//}

fn readForm(allocator: std.mem.Allocator, reader: *Reader) !ZType {
    const maybe_token = reader.peek();
    if (maybe_token == null) {
        return .nil;
    }

    const token = maybe_token.?;
    if (token.len == 0) {
        return .nil;
    }

    return switch (token[0]) {
        '(' => try readCollection(allocator, reader, .list),
        '[' => try readCollection(allocator, reader, .vector),
        '{' => try readDict(allocator, reader),
        //        '@' => try translate(allocator, reader, "deref"),
        //        '\'' => try translate(allocator, reader, "quote"),
        //        '`' => try translate(allocator, reader, "quasiquote"),
        //        '~' => blk: {
        //            if (token.len == 1)
        //                break :blk translate(allocator, reader, "unquote");
        //            if (token.len == 2 and token[1] == '@')
        //                break :blk translate(allocator, reader, "splice-unquote");
        //            break :blk try readAtom(allocator, reader);
        //        },
        else => try readAtom(allocator, reader),
    };
}

/// Transforms a string into a lisp expression.
pub fn readStr(
    allocator: std.mem.Allocator,
    subject: []const u8,
) !ZType {
    var token_list = try tokenize(subject, allocator);
    defer token_list.deinit(allocator);

    var reader = Reader{
        .token_list = token_list,
        .current = 0,
    };

    return readForm(allocator, &reader);
}
