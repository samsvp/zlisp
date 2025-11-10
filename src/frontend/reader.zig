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

pub const Token = union(enum) {
    atom: Atom,
    list: std.ArrayList(Token),

    pub const Atom = struct {
        value: Value,
        line: usize,
    };

    pub fn deinit(self: *Token, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .atom => |*a| a.value.deinit(allocator),
            .list => |*l| {
                for (l.items) |*a| {
                    a.deinit(allocator);
                }

                l.deinit(allocator);
            },
        }
    }

    pub fn print(self: Token, allocator: std.mem.Allocator) !void {
        switch (self) {
            .atom => |a| {
                const str = try a.value.toString(allocator);
                defer allocator.free(str);

                std.debug.print("{{value: {s}; line: {}}}", .{ str, a.line });
            },
            .list => |l| {
                std.debug.print("(", .{});
                for (l.items) |t| {
                    try t.print(allocator);
                    std.debug.print(", ", .{});
                }
                std.debug.print(")", .{});
            },
        }
    }
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
) !TokenDataList {
    var text = text_;

    var line: usize = 1;
    var token_list: TokenDataList = .empty;
    errdefer token_list.deinit(allocator);

    while (text.len > 0) {
        err_ctx.line = line;

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
                    try err_ctx.setMsg(allocator, "PARSER", "Unclosed string.", .{});
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
) ParserError!Token.Atom {
    const atom = atom_token.str;
    if (atom.len == 0) {
        return Token.Atom{ .line = atom_token.line, .value = .nil };
    }

    err_ctx.line = atom_token.line;
    switch (atom[0]) {
        ':' => {
            err_ctx.setMsg(allocator, "PARSER", "Error reading keyword - Not implemented", .{}) catch unreachable;
            return ParserError.NotImplemented;
        },
        '"' => {
            if (atom.len < 2 or atom[atom.len - 1] != '"') {
                return ParserError.EOFStringReadError;
            }

            const str = try Obj.String.init(allocator, atom[1 .. atom.len - 1]);

            return .{
                .line = atom_token.line,
                .value = .{ .obj = &str.obj },
            };
        },
        else => {
            const maybe_num = std.fmt.parseInt(i32, atom, 10) catch null;
            if (maybe_num) |int| {
                return .{
                    .line = atom_token.line,
                    .value = .{ .int = int },
                };
            }
            const maybe_float = std.fmt.parseFloat(f32, atom) catch null;
            if (maybe_float) |float| {
                return .{
                    .line = atom_token.line,
                    .value = .{ .float = float },
                };
            }

            if (std.mem.eql(u8, atom, "nil")) {
                return .{
                    .line = atom_token.line,
                    .value = .nil,
                };
            }

            if (std.mem.eql(u8, atom, "true")) {
                return .{
                    .line = atom_token.line,
                    .value = .{ .boolean = true },
                };
            } else if (std.mem.eql(u8, atom, "false")) {
                return .{
                    .line = atom_token.line,
                    .value = .{ .boolean = false },
                };
            }

            return .{
                .line = atom_token.line,
                // this should own the memory
                .value = .{ .symbol = atom },
            };
        },
    }
}

fn readCollection(
    allocator: std.mem.Allocator,
    reader: *Reader,
    err_ctx: *errors.Ctx,
) anyerror!Token {
    var list: std.ArrayList(Token) = .empty;
    errdefer {
        var token_list: Token = .{ .list = list };
        token_list.deinit(allocator);
    }

    while (reader.peek()) |token_str| {
        const str = token_str.str;
        if (str.len == 1 and str[0] == ')') {
            _ = reader.next();
            break;
        }

        const token = try readForm(allocator, reader, err_ctx);
        try list.append(allocator, token);
    }

    return .{ .list = list };
}

pub fn readForm(
    allocator: std.mem.Allocator,
    reader: *Reader,
    err_ctx: *errors.Ctx,
) anyerror!Token {
    const token_data = reader.next() orelse return ParserError.InvalidToken;

    return switch (token_data.str[0]) {
        '(' => try readCollection(allocator, reader, err_ctx),
        else => .{ .atom = try readAtom(allocator, token_data, err_ctx) },
    };
}

/// Transforms a string into a lisp expression.
pub fn readStr(
    allocator: std.mem.Allocator,
    subject: []const u8,
    err_ctx: *errors.Ctx,
) !std.ArrayList(Token) {
    var token_list = try tokenize(allocator, subject, err_ctx);
    defer token_list.deinit(allocator);

    var reader = Reader{
        .token_list = token_list,
        .current = 0,
    };

    var acc: std.ArrayList(Token) = .empty;
    while (reader.peek()) |_| {
        const token = try readForm(allocator, &reader, err_ctx);
        try acc.append(allocator, token);
    }

    return acc;
}
