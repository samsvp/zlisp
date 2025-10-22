const std = @import("std");
const LispType = @import("types.zig").LispType;

pub const ParserError = error{
    EOFCollectionReadError,
    EOFStringReadError,
    UnhashableKey,
    OutOfMemory,
};

const TokenList = std.ArrayList([]const u8);

/// A helper token reader.
pub const Reader = struct {
    token_list: TokenList,
    current: usize,

    const Self = @This();

    pub fn next(self: *Self) ?[]const u8 {
        if (self.token_list.items.len <= self.current) {
            return null;
        }
        self.current += 1;
        return self.token_list.items[self.current - 1];
    }

    pub fn peek(self: Self) ?[]const u8 {
        if (self.token_list.items.len <= self.current) {
            return null;
        }
        return self.token_list.items[self.current];
    }
};

fn tokenize(
    text_: []const u8,
    allocator: std.mem.Allocator,
) !TokenList {
    var text = text_;

    var token_list: TokenList = .empty;
    while (text.len > 0) {
        const offset = switch (text[0]) {
            '(', ')', '[', ']', '{', '}', '\'', '`', '^', '@' => paren: {
                try token_list.append(allocator, text[0..1]);
                break :paren 1;
            },
            '~' => tilde: {
                const offset: usize = if (text.len > 1 and text[1] == '@') 2 else 1;
                try token_list.append(allocator, text[0..offset]);
                break :tilde offset;
            },
            '"' => string: {
                var str = std.ArrayList(u8).empty;

                var offset: usize = 1;
                try str.append(allocator, '"');
                var escaped = false;
                while (offset < text.len and (escaped or text[offset] != '"')) : (offset += 1) {
                    const char = text[offset];

                    switch (char) {
                        '\\' => escaped = !escaped,
                        '"' => if (escaped) {
                            escaped = false;
                        },
                        'n' => if (escaped) {
                            escaped = false;
                            try str.append(allocator, '\n');
                            continue;
                        },
                        't' => if (escaped) {
                            escaped = false;
                            try str.append(allocator, '\t');
                            continue;
                        },
                        else => escaped = false,
                    }

                    if (!escaped) try str.append(allocator, char);
                }

                if (offset < text.len) try str.append(allocator, text[offset]);
                try token_list.append(allocator, str.items);
                offset += 1;
                break :string offset;
            },
            ';' => comment: {
                var offset: usize = 1;
                while (offset < text.len and text[offset] != '\n') : (offset += 1) {}
                break :comment offset;
            },
            ' ', ',', '\t', '\n' => 1,
            else => chars: {
                var offset: usize = 0;

                while (offset < text.len) : (offset += 1) {
                    const char = text[offset];
                    switch (char) {
                        '(', ')', '[', ']', '{', '}', ',', ' ', '\n', '\t' => break,
                        else => {},
                    }
                }
                try token_list.append(allocator, text[0..offset]);
                break :chars offset;
            },
        };
        text = text[offset..];
    }

    return token_list;
}

fn readAtom(
    allocator: std.mem.Allocator,
    reader: *Reader,
) ParserError!LispType {
    const atom = reader.next().?;
    if (atom.len == 0) {
        return .nil;
    }

    switch (atom[0]) {
        ':' => {
            return LispType.String.initKeyword(allocator, atom);
        },
        '"' => {
            if (atom.len < 2 or atom[atom.len - 1] != '"') {
                return ParserError.EOFStringReadError;
            }

            return LispType.String.initString(allocator, atom[1 .. atom.len - 1]);
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

            return LispType.String.initSymbol(allocator, atom);
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
) ParserError!LispType {
    var list: std.ArrayList(LispType) = .empty;
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

fn readDict(allocator: std.mem.Allocator, reader: *Reader) ParserError!LispType {
    var dict = LispType.Dict.Map.empty;
    errdefer {
        var iter = dict.iterator();
        while (iter.next()) |entry| {
            entry.key_ptr.deinit(allocator);
            entry.value_ptr.deinit(allocator);
        }
        dict.deinit(allocator);
    }

    var maybe_key: ?LispType = null;
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

fn translate(allocator: std.mem.Allocator, reader: *Reader, name: []const u8) ParserError!LispType {
    var deref = LispType.String.initSymbol(allocator, name);
    defer deref.deinit(allocator);

    _ = reader.next();
    var next = try readForm(allocator, reader);
    defer next.deinit(allocator);

    var lst = [_]LispType{ deref, next };
    return LispType.Array.initList(allocator, &lst);
}

fn readForm(allocator: std.mem.Allocator, reader: *Reader) !LispType {
    const maybe_token = reader.peek();
    if (maybe_token == null) {
        return .nil;
    }

    const token = maybe_token.?;
    if (token.len == 0) {
        return .nil;
    }

    return switch (token[0]) {
        ';' => blk: {
            _ = reader.next();
            break :blk readForm(allocator, reader);
        },
        '(' => try readCollection(allocator, reader, .list),
        '[' => try readCollection(allocator, reader, .vector),
        '{' => try readDict(allocator, reader),
        '@' => try translate(allocator, reader, "deref"),
        '\'' => try translate(allocator, reader, "quote"),
        '`' => try translate(allocator, reader, "quasiquote"),
        '~' => blk: {
            if (token.len == 1)
                break :blk translate(allocator, reader, "unquote");
            if (token.len == 2 and token[1] == '@')
                break :blk translate(allocator, reader, "splice-unquote");
            break :blk try readAtom(allocator, reader);
        },
        else => try readAtom(allocator, reader),
    };
}

/// Transforms a string into a lisp expression.
pub fn readStr(
    allocator: std.mem.Allocator,
    subject: []const u8,
) !LispType {
    var token_list = try tokenize(subject, allocator);
    defer token_list.deinit(allocator);

    var reader = Reader{
        .token_list = token_list,
        .current = 0,
    };

    return readForm(allocator, &reader);
}
