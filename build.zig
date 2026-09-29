const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const libc_include = b.option(std.Build.LazyPath, "libc_include", "Build without libc against these headers; the consumer provides the symbols");
    const t = target.result;

    const opus = b.dependency("opus", .{ .target = target, .optimize = optimize, .libc_include = libc_include }).artifact("opus");

    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = libc_include == null });
    if (libc_include) |p| mod.addIncludePath(p); // -I: must win over the macOS SDK headers zig always adds
    // Without libc the Windows file code (windows.h, io.h, _wfopen) cannot build; the consumer's
    // libc has no files anyway, so take the POSIX paths (they call its failing stubs).
    const no_win32: []const []const u8 = if (libc_include != null and target.result.os.tag == .windows)
        &.{ "-U_WIN32", "-UWIN32", "-U__WIN32__", "-U__MINGW32__", "-U_WIN64", "-UWIN64" } // _WIN64: only unicode_support.c checks it
    else
        &.{};
    mod.addIncludePath(b.path("include"));
    mod.addIncludePath(b.path("src"));
    mod.linkLibrary(opus);
    mod.addCMacro("OPE_BUILD", "1");
    mod.addCMacro("OUTSIDE_SPEEX", "1");
    mod.addCMacro("RANDOM_PREFIX", "libopusenc");
    mod.addCMacro("RESAMPLE_FULL_SINC_TABLE", "1");
    mod.addCMacro("OP_HAVE_LRINTF", "1");
    mod.addCMacro("PACKAGE_NAME", "\"libopusenc\"");
    mod.addCMacro("PACKAGE_VERSION", "\"0.3\"");
    // without libc the consumer provides arc4random (random.c then needs nothing else)
    if (libc_include != null or t.os.tag.isDarwin() or t.os.tag.isBSD()) {
        mod.addCMacro("HAVE_ARC4RANDOM", "1");
    } else if (t.os.tag != .windows) {
        mod.addCMacro("HAVE_CLOCK_GETTIME", "1");
        mod.addCMacro("HAVE_SYS_RANDOM_H", "1");
        mod.addCMacro("HAVE_GETRANDOM", "1");
    }
    // resample.c picks its SSE path from __SSE__ (target CPU features); no NEON header ships upstream.
    mod.addCSourceFiles(.{ .root = b.path("src"), .files = &.{
        "ogg_packer.c", "opus_header.c", "opusenc.c",         "picture.c",
        "random.c",     "resample.c",    "unicode_support.c",
    }, .flags = no_win32 });

    const lib = b.addLibrary(.{ .name = "opusenc", .root_module = mod });
    lib.installHeader(b.path("include/opusenc.h"), "opusenc.h");
    lib.installLibraryHeaders(opus);
    b.installArtifact(lib);
}
