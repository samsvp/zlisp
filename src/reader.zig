const std = @import("std");
const Value = @import("value.zig").Value;

pub const ParserError = error{
    EOFCollectionReadError,
    EOFStringReadError,
    UnhashableKey,
    OutOfMemory,
};

pub const TokenData = struct {
    str: []const u8,
    line: usize,
};

pub const Token = struct {
    // TODO separate `data` into Value and line instead of using TokenData directly.
    data: TokenData,
    type: Type,

    pub const Type = enum {
        string,
        keyword,
        symbol,
        list,
        vector,
        dict,
        int,
        float,
        nil,
        boolean,
    };
};

pub const TokenList = std.ArrayList(Token);
pub const TokenDataList = std.ArrayList(TokenData);

/// A helper token reader.
pub const Reader = struct {
    token_list: TokenDataList,
    current: usize,

    const Self = @This();

    pub fn next(self: *Self) ?TokenData {
        if (self.token_list.items.len <= self.current) {
            return null;
        }
        self.current += 1;
        return self.token_list.items[self.current - 1];
    }

    pub fn peek(self: Self) ?TokenData {
        if (self.token_list.items.len <= self.current) {
            return null;
        }
        return self.token_list.items[self.current];
    }
};

pub fn tokenize(
    allocator: std.mem.Allocator,
    text_: []const u8,
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
                        'n' => if (escaped) {
                            escaped = false;
                            continue;
                        },
                        't' => if (escaped) {
                            escaped = false;
                            continue;
                        },
                        else => escaped = false,
                    }
                }

                if (offset == text.len) {
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

fn readAtom(
    allocator: std.mem.Allocator,
    reader: *Reader,
) ParserError!Token {
    _ = allocator;

    const atom_token = reader.next().?;
    const atom = atom_token.str;
    if (atom == 0) {
        return .nil;
    }

    switch (atom[0]) {
        ':' => {
            return Token{
                .data = atom,
                .type = .keyword,
            };
        },
        '"' => {
            if (atom.len < 2 or atom[atom.len - 1] != '"') {
                return ParserError.EOFStringReadError;
            }

            return Token{
                .data = atom,
                .type = .symbol,
            };
        },
        else => {
            const maybe_num = std.fmt.parseInt(i32, atom, 10) catch null;
            if (maybe_num) |_| {
                return Token{
                    .data = atom,
                    .type = .int,
                };
            }
            const maybe_float = std.fmt.parseFloat(f32, atom) catch null;
            if (maybe_float) |_| {
                return Token{
                    .data = atom,
                    .type = .float,
                };
            }

            if (std.mem.eql(u8, atom, "nil")) {
                return Token{
                    .data = atom,
                    .type = .nil,
                };
            }

            if (std.mem.eql(u8, atom, "true")) {
                return Token{
                    .data = atom,
                    .type = .boolean,
                };
            } else if (std.mem.eql(u8, atom, "false")) {
                return Token{
                    .data = atom,
                    .type = .boolean,
                };
            }

            return Token{
                .data = atom,
                .type = .symbol,
            };
        },
    }
}

fn readForm(allocator: std.mem.Allocator, reader: *Reader) !Token {
    const maybe_token = reader.peek();
    if (maybe_token == null) {
        return .nil;
    }

    const token = maybe_token.?;
    if (token.len == 0) {
        return .nil;
    }

    return readAtom(allocator, reader);
}

/// Transforms a string into a lisp expression.
pub fn readStr(
    allocator: std.mem.Allocator,
    subject: []const u8,
) !TokenList {
    var token_list = try tokenize(allocator, subject);
    defer token_list.deinit(allocator);

    var reader = Reader{
        .token_list = token_list,
        .current = 0,
    };

    return readForm(allocator, &reader);
}
