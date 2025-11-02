const std = @import("std");
const errors = @import("errors.zig");
const Value = @import("value.zig").Value;

pub const ParserError = error{
    EOFCollectionReadError,
    EOFStringReadError,
    UnhashableKey,
    OutOfMemory,
    NotImplemented,
};

pub const TokenData = struct {
    str: []const u8,
    line: usize,
};

pub const Token = struct {
    value: Value,
    line: usize,
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
    atom_token: TokenData,
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

            err_ctx.setMsg(allocator, "Error reading string on line {}", .{atom_token.line}) catch unreachable;
            return ParserError.NotImplemented;
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
                .value = .{ .symbol = try Value.String.init(allocator, atom) },
            };
        },
    }
}

pub fn readForm(allocator: std.mem.Allocator, reader: *Reader) !Token {
    const maybe_token = reader.next();
    if (maybe_token == null) {
        return .nil;
    }

    const token = maybe_token.?;
    if (token.len == 0) {
        return .nil;
    }

    return readAtom(allocator, token);
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
