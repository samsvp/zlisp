const std = @import("std");
const errors = @import("../errors.zig");
const Obj = @import("../value.zig").Obj;
const Value = @import("../value.zig").Value;

pub const ParserError = error{
    EOFCollectionReadError,
    EOFStringReadError,
    UnhashableKey,
    OutOfMemory,
    NotImplemented,
    InvalidToken,
};

pub const TokenString = struct {
    str: []const u8,
    line: usize,
};

pub const Token = struct {
    value: Value,
    line: usize,
};

pub const TokenList = std.ArrayList(Token);
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
) !TokenDataList {
    var text = text_;

    var line: usize = 1;
    var token_list: TokenDataList = .empty;
    errdefer token_list.deinit(allocator);

    while (text.len > 0) {
        const offset = switch (text[0]) {
            '(', ')', '[', ']', '{', '}', '\'', '`', '^', '@' => paren: {
                try token_list.append(allocator, .{ .line = line, .str = text[0..1] });
                break :paren 1;
            },
            '~' => tilde: {
                const offset: usize = if (text.len > 1 and text[1] == '@') 2 else 1;
                try token_list.append(allocator, .{ .line = line, .str = text[0..offset] });
                break :tilde offset;
            },
            '"' => string: {
                var offset: usize = 1;
                var escaped = false;
                while (offset < text.len and (escaped or text[offset] != '"')) : (offset += 1) {
                    const char = text[offset];

                    switch (char) {
                        '\\' => escaped = !escaped,
                        '"' => if (escaped) {
                            escaped = false;
                        },
                        else => escaped = false,
                    }
                }

                if (offset == text.len) {
                    try err_ctx.setMsg(allocator, "Unclosed string on line {}", .{line});
                    return ParserError.EOFStringReadError;
                }

                offset += 1;
                try token_list.append(allocator, .{ .line = line, .str = text[0..offset] });
                break :string offset;
            },
            ';' => comment: {
                var offset: usize = 1;
                while (offset < text.len and text[offset] != '\n') : (offset += 1) {}
                break :comment offset;
            },
            ' ', ',', '\t' => 1,
            '\n' => new_line: {
                line += 1;
                break :new_line 1;
            },
            else => chars: {
                var offset: usize = 0;

                while (offset < text.len) : (offset += 1) {
                    const char = text[offset];
                    switch (char) {
                        '(', ')', '[', ']', '{', '}', ',', ' ', '\n', '\t' => break,
                        else => {},
                    }
                }
                try token_list.append(allocator, .{ .line = line, .str = text[0..offset] });
                break :chars offset;
            },
        };
        text = text[offset..];
    }

    return token_list;
}

pub fn readAtom(
    allocator: std.mem.Allocator,
    atom_token: TokenString,
    err_ctx: *errors.Ctx,
) ParserError!Token {
    const atom = atom_token.str;
    if (atom.len == 0) {
        return Token{ .line = atom_token.line, .value = .nil };
    }

    switch (atom[0]) {
        ':' => {
            err_ctx.setMsg(allocator, "Error reading keyword on line {}", .{atom_token.line}) catch unreachable;
            return ParserError.NotImplemented;
        },
        '"' => {
            if (atom.len < 2 or atom[atom.len - 1] != '"') {
                return ParserError.EOFStringReadError;
            }

            const str = try Obj.String.init(allocator, atom[1 .. atom.len - 1]);

            return Token{
                .line = atom_token.line,
                .value = .{ .obj = &str.obj },
            };
        },
        else => {
            const maybe_num = std.fmt.parseInt(i32, atom, 10) catch null;
            if (maybe_num) |int| {
                return Token{
                    .line = atom_token.line,
                    .value = .{ .int = int },
                };
            }
            const maybe_float = std.fmt.parseFloat(f32, atom) catch null;
            if (maybe_float) |float| {
                return Token{
                    .line = atom_token.line,
                    .value = .{ .float = float },
                };
            }

            if (std.mem.eql(u8, atom, "nil")) {
                return Token{
                    .line = atom_token.line,
                    .value = .nil,
                };
            }

            if (std.mem.eql(u8, atom, "true")) {
                return Token{
                    .line = atom_token.line,
                    .value = .{ .boolean = true },
                };
            } else if (std.mem.eql(u8, atom, "false")) {
                return Token{
                    .line = atom_token.line,
                    .value = .{ .boolean = false },
                };
            }

            return Token{
                .line = atom_token.line,
                // this should own the memory
                .value = .{ .symbol = atom },
            };
        },
    }
}

fn _readCollection(
    allocator: std.mem.Allocator,
    reader: *Reader,
    list_acc: *TokenList,
    acc: *TokenList,
    err_ctx: *errors.Ctx,
) ParserError!void {
    const token_data = reader.peek() orelse return ParserError.EOFCollectionReadError;

    if (token_data.str.len == 1 and token_data.str[0] == '(') {
        _ = reader.next(); // consume ')'
        defer list_acc.deinit(allocator);

        try acc.appendSlice(allocator, list_acc.items);
        return;
    }

    readForm(allocator, reader, list_acc, err_ctx) catch return ParserError.EOFCollectionReadError;
    return _readCollection(allocator, reader, list_acc, acc, err_ctx);
}

fn readCollection(
    allocator: std.mem.Allocator,
    reader: *Reader,
    acc: *TokenList,
    err_ctx: *errors.Ctx,
) ParserError!void {
    var list_acc: std.ArrayList(Token) = .empty;
    _readCollection(allocator, reader, &list_acc, acc, err_ctx) catch |err| {
        for (list_acc.items) |*atom| {
            atom.value.deinit(allocator);
        }
        list_acc.deinit(allocator);
        return err;
    };
}

pub fn readForm(
    allocator: std.mem.Allocator,
    reader: *Reader,
    acc: *TokenList,
    err_ctx: *errors.Ctx,
) !void {
    const token_data = reader.next() orelse return ParserError.InvalidToken;

    switch (token_data.str[0]) {
        ')' => try readCollection(allocator, reader, acc, err_ctx),
        else => {
            const token = try readAtom(allocator, token_data, err_ctx);
            try acc.append(allocator, token);
        },
    }
}

/// Transforms a string into a lisp expression.
pub fn readStr(
    allocator: std.mem.Allocator,
    subject: []const u8,
    err_ctx: *errors.Ctx,
) !TokenList {
    var token_list = try tokenize(allocator, subject, err_ctx);
    defer token_list.deinit(allocator);

    var reader = Reader{
        .token_list = token_list,
        .current = 0,
    };

    var acc: std.ArrayList(Token) = .empty;
    while (reader.peek()) |_| {
        try readForm(allocator, &reader, &acc, err_ctx);
    }

    return acc;
}
