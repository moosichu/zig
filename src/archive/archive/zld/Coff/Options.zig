const Options = @This();

const std = @import("std");
const builtin = @import("builtin");
const io = std.io;
const mem = std.mem;
const process = std.process;

const Allocator = mem.Allocator;
const CrossTarget = std.zig.CrossTarget;
const Coff = @import("../Coff.zig");
const Zld = @import("../Zld.zig");

const usage =
    \\Usage: {s} [files...]
    \\
    \\General Options:
    \\-l[name]                      Specify library to link against
    \\-L[path]                      Specify library search dir
    \\-o [path]                     Specify output path for the final artifact
    \\-h, --help                    Print this help and exit
    \\--debug-log [scope]           Turn on debugging logs for [scope] (requires zld compiled with -Dlog)
;

emit: Zld.Emit,
output_mode: Zld.OutputMode,
target: CrossTarget,
positionals: []const Zld.LinkObject,
libs: std.StringArrayHashMap(Zld.SystemLib),
lib_dirs: []const []const u8,

pub fn parseArgs(arena: Allocator, ctx: Zld.MainCtx) !Options {
    if (ctx.args.len == 0) {
        ctx.printSuccess(usage, .{ctx.cmd});
    }

    var positionals = std.ArrayList(Zld.LinkObject).init(arena);
    var libs = std.StringArrayHashMap(Zld.SystemLib).init(arena);
    var lib_dirs = std.ArrayList([]const u8).init(arena);
    var out_path: ?[]const u8 = null;

    const Iterator = struct {
        args: []const []const u8,
        i: usize = 0,
        fn next(it: *@This()) ?[]const u8 {
            if (it.i >= it.args.len) {
                return null;
            }
            defer it.i += 1;
            return it.args[it.i];
        }
    };
    var args_iter = Iterator{ .args = ctx.args };

    while (args_iter.next()) |arg| {
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            ctx.printSuccess(usage, .{ctx.cmd});
        } else if (mem.eql(u8, arg, "--debug-log")) {
            const scope = args_iter.next() orelse ctx.printFailure("Expected log scope after {s}", .{arg});
            try ctx.log_scopes.append(scope);
        } else if (mem.startsWith(u8, arg, "-l")) {
            try libs.put(arg[2..], .{});
        } else if (mem.startsWith(u8, arg, "-L")) {
            try lib_dirs.append(arg[2..]);
        } else if (mem.eql(u8, arg, "-o")) {
            out_path = args_iter.next() orelse
                ctx.printFailure("Expected output path after {s}", .{arg});
        } else {
            try positionals.append(.{
                .path = arg,
                .must_link = true,
            });
        }
    }

    if (positionals.items.len == 0) {
        ctx.printFailure("Expected at least one input .o file", .{});
    }

    return Options{
        .emit = .{
            .directory = std.fs.cwd(),
            .sub_path = out_path orelse "a.out",
        },
        .target = CrossTarget.fromTarget(builtin.target),
        .output_mode = .exe,
        .positionals = positionals.items,
        .libs = libs,
        .lib_dirs = lib_dirs.items,
    };
}
