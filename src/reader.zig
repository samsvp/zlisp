const std = @import("std");
const errors = @import("errors.zig");

const types = @import("lisp_types/value.zig");
const Obj = types.Obj;
const AST = types.AST;
const Value = types.Value;
const NameSet = types.NameSet;
const MetaData = types.MetaData;

pub const ParserError = error{
    EOFCollectionReadError,
    EOFStringReadError,
    UnhashableKey,
    OutOfMemory,
    NotImplemented,
    InvalidToken,
};

pub const ParserErrorCtx = struct {
    pub fn stringRead(
        err_ctx: *errors.Ctx,
        meta: MetaData,
    ) ParserError {
        err_ctx.setMessage("{s}: Unclosed string.", .{@errorName(ParserError.EOFStringReadError)}, meta) catch {};
        return ParserError.EOFStringReadError;
    }

    pub fn collectionRead(
        err_ctx: *errors.Ctx,
        meta: MetaData,
        symbol: u8,
    ) ParserError {
        err_ctx.setMessage("{s}: Unclosed {c}.", .{ @errorName(ParserError.EOFStringReadError), symbol }, meta) catch {};
        return ParserError.EOFStringReadError;
    }
};

pub const TokenString = struct {
    str: []const u8,
    meta: MetaData,
};

pub const TokenDataList = std.ArrayList(TokenString);

/// A helper token reader.
pub const Reader = struct {
    token_list: TokenDataList,
    current: usize,

    const Self = @This();

    pub fn next(self: *Self) ?TokenString {
        if (self.token_list.items.len <= self.current) {
            return null;
        }
        self.current += 1;
        return self.token_list.items[self.current - 1];
    }

    pub fn peek(self: Self) ?TokenString {
        if (self.token_list.items.len <= self.current) {
            return null;
        }
        return self.token_list.items[self.current];
    }
};

pub fn tokenize(
    allocator: std.mem.Allocator,
    text_: []const u8,
    err_ctx: *errors.Ctx,
    file_id: usize,
) !TokenDataList {
    var text = text_;

    var line: usize = 1;
    var token_list: TokenDataList = .empty;
    errdefer token_list.deinit(allocator);

    var total_offset: usize = 0;
    while (text.len > 0) {
        const offset = switch (text[0]) {
            '(', ')', '[', ']', '{', '}', '\'', '`', '^', '@' => paren: {
                try token_list.append(allocator, .{ .meta = .{
                    .file_id = file_id,
                    .line = line,
                    .col = total_offset,
                }, .str = text[0..1] });
                break :paren 1;
            },
            '"' => string: {
                var str_offset: usize = 1;
                var escaped = false;
                while (str_offset < text.len and (escaped or text[str_offset] != '"')) : (str_offset += 1) {
                    const char = text[str_offset];

                    switch (char) {
                        '\\' => escaped = !escaped,
                        '"' => if (escaped) {
                            escaped = false;
                        },
                        else => escaped = false,
                    }
                }

                if (str_offset == text.len) {
                    return ParserErrorCtx.stringRead(
                        err_ctx,
                        .{ .col = total_offset, .line = line, .file_id = file_id },
                    );
                }

                str_offset += 1;
                try token_list.append(allocator, .{
                    .meta = .{
                        .file_id = file_id,
                        .line = line,
                        .col = total_offset,
                    },
                    .str = text[0..str_offset],
                });
                break :string str_offset;
            },
            ';' => comment: {
                var comment_offset: usize = 1;
                while (comment_offset < text.len and text[comment_offset] != '\n') : (comment_offset += 1) {}
                break :comment comment_offset;
            },
            ' ', ',', '\t' => 1,
            '\n' => new_line: {
                line += 1;
                break :new_line 1;
            },
            else => chars: {
                var chars_offset: usize = 0;

                while (chars_offset < text.len) : (chars_offset += 1) {
                    const char = text[chars_offset];
                    switch (char) {
                        '(', ')', '[', ']', '{', '}', ',', ' ', '\n', '\t' => break,
                        else => {},
                    }
                }
                try token_list.append(allocator, .{ .meta = .{
                    .file_id = file_id,
                    .line = line,
                    .col = total_offset,
                }, .str = text[0..chars_offset] });
                break :chars chars_offset;
            },
        };
        total_offset += offset;
        text = text[offset..];
    }

    return token_list;
}

pub fn readAtom(
    allocator: std.mem.Allocator,
    atom_token: TokenString,
    name_set: *NameSet,
    err_ctx: *errors.Ctx,
) ParserError!AST {
    const atom = atom_token.str;
    const meta = atom_token.meta;
    if (atom.len == 0) {
        return AST{
            .value = Value.Nil,
            .meta = atom_token.meta,
        };
    }

    const value = blk: switch (atom[0]) {
        ':' => {
            if (atom.len == 1) {
                return ParserError.InvalidToken;
            }

            break :blk try Value.initKeyword(allocator, name_set, atom);
        },
        '"' => {
            if (atom.len < 2 or atom[atom.len - 1] != '"') {
                return ParserErrorCtx.stringRead(err_ctx, meta);
            }

            const str = try Obj.String.init(allocator, atom[1 .. atom.len - 1]);

            break :blk try Value.initObj(allocator, &str.obj);
        },
        else => {
            const maybe_num = std.fmt.parseInt(i32, atom, 10) catch null;
            if (maybe_num) |int| {
                break :blk Value{ .int = int };
            }
            const maybe_float = std.fmt.parseFloat(f32, atom) catch null;
            if (maybe_float) |float| {
                break :blk Value{ .float = float };
            }

            if (std.mem.eql(u8, atom, "nil")) {
                break :blk Value.Nil;
            }

            if (std.mem.eql(u8, atom, "true")) {
                break :blk Value.True;
            } else if (std.mem.eql(u8, atom, "false")) {
                break :blk Value.False;
            }

            // this guy should own the symbol memory
            break :blk try Value.initSymbol(allocator, name_set, atom);
        },
    };
    return .{ .value = value, .meta = meta };
}

fn readCollection(
    allocator: std.mem.Allocator,
    reader: *Reader,
    name_set: *NameSet,
    close_char: u8,
    array_list: *std.ArrayList(AST),
    meta: MetaData,
    err_ctx: *errors.Ctx,
) anyerror!AST {
    defer array_list.deinit(allocator);
    errdefer for (array_list.items) |*ast| ast.value.deinit(allocator);

    while (reader.peek()) |token_str| {
        const str = token_str.str;
        if (str.len == 1 and str[0] == close_char) {
            _ = reader.next();
            break;
        }

        const ast = try readForm(allocator, reader, name_set, err_ctx);
        try array_list.append(allocator, ast);
    } else return ParserErrorCtx.collectionRead(err_ctx, meta, close_char);

    const list = try Obj.List.init(allocator, array_list.items);
    return .{ .meta = meta, .value = try Value.initObj(allocator, &list.obj) };
}

pub fn readForm(
    allocator: std.mem.Allocator,
    reader: *Reader,
    name_set: *NameSet,
    err_ctx: *errors.Ctx,
) anyerror!AST {
    const token_data = reader.next() orelse return ParserError.InvalidToken;
    const meta = token_data.meta;

    switch (token_data.str[0]) {
        '(' => {
            var list: std.ArrayList(AST) = .empty;
            return readCollection(allocator, reader, name_set, ')', &list, meta, err_ctx);
        },
        '[' => {
            var list: std.ArrayList(AST) = .empty;
            const vector_symbol: AST = .{
                .meta = meta,
                .value = try Value.initSymbol(allocator, name_set, "vector"),
            };
            try list.append(allocator, vector_symbol);
            return readCollection(allocator, reader, name_set, ']', &list, meta, err_ctx);
        },
        '{' => {
            var list: std.ArrayList(AST) = .empty;
            const hm_symbol: AST = .{
                .meta = meta,
                .value = try Value.initSymbol(allocator, name_set, "hash_map"),
            };
            try list.append(allocator, hm_symbol);
            return readCollection(allocator, reader, name_set, '}', &list, meta, err_ctx);
        },
        else => return readAtom(allocator, token_data, name_set, err_ctx),
    }
}

/// Transforms a string into a lisp expression.
pub fn readStr(
    allocator: std.mem.Allocator,
    subject: []const u8,
    name_set: *NameSet,
    err_ctx: *errors.Ctx,
    file_id: usize,
) !std.MultiArrayList(AST) {
    var token_list = try tokenize(allocator, subject, err_ctx, file_id);
    defer token_list.deinit(allocator);

    var reader = Reader{
        .token_list = token_list,
        .current = 0,
    };

    var acc: std.MultiArrayList(AST) = .empty;
    while (reader.peek()) |_| {
        const token = try readForm(allocator, &reader, name_set, err_ctx);
        try acc.append(allocator, token);
    }

    return acc;
}
