const std = @import("std");
const zmath = @import("thirdparty/zmath/build.zig");
const stb = @import("thirdparty/stb/build.zig");
const opengl = @import("thirdparty/zig-opengl/build.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("defense", "src/main.zig");
    linkSDL2(exe);
    stb.link(exe);
    exe.addPackage(stb.stb_image_pkg);
    exe.addPackage(stb.stb_vorbis_pkg);
    exe.addPackage(zmath.pkg);
    exe.addPackage(opengl.gl33_pkg);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    installAssets(b);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn linkSDL2(exe: *std.build.LibExeObjStep) void {
    exe.addObjectFile("thirdparty/SDL2-2.24.1/x86_64-w64-mingw32/lib/libSDL2.a");
    exe.linkLibC();
    // Windows SDL dependencies
    exe.linkSystemLibrary("setupapi");
    exe.linkSystemLibrary("winmm");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("imm32");
    exe.linkSystemLibrary("version");
    exe.linkSystemLibrary("oleaut32");
    exe.linkSystemLibrary("ole32");
}

const maps = [_][]const u8{
    "assets/maps/level_select.tmj",
    "assets/maps/map01.tmj",
    "assets/maps/map02.tmj",
    "assets/maps/map03.tmj",
};
const music = [_][]const u8{
    "assets/music/Daybreak.ogg",
    "assets/music/Flight of the Fox.ogg",
    "assets/music/The Demon's Serenade.ogg",
    "assets/music/Opposing Tribes.ogg",
};
const sounds = [_][]const u8{
    "assets/sounds/blip.ogg",
    "assets/sounds/bow.ogg",
    "assets/sounds/build.ogg",
    "assets/sounds/burn.ogg",
    "assets/sounds/click.ogg",
    "assets/sounds/coindrop.ogg",
    "assets/sounds/flame.ogg",
    "assets/sounds/frost.ogg",
    "assets/sounds/gun.ogg",
    "assets/sounds/hit.ogg",
    "assets/sounds/shotgun.ogg",
    "assets/sounds/slash_hit.ogg",
    "assets/sounds/slash.ogg",
    "assets/sounds/spawn.ogg",
    "assets/sounds/stab.ogg",
    "assets/sounds/warp.ogg",
};
const textures = [_][]const u8{
    "assets/textures/button_badges.png",
    "assets/textures/button_base.png",
    "assets/textures/characters.png",
    "assets/textures/CommonCase.png",
    "assets/textures/finger.png",
    "assets/textures/floating_text.png",
    "assets/textures/level_select_button.png",
    "assets/textures/menu_button.png",
    "assets/textures/special.png",
    "assets/textures/terrain.png",
    "assets/textures/ui_panel.png",
    "assets/textures/water_foam.png",
    "assets/textures/water.png",
};
const tables = [_][]const u8{
    "assets/tables/CommonCase.json",
    "assets/tables/floating_text.json",
    "assets/tables/map01_waves.json",
    "assets/tables/map02_waves.json",
    "assets/tables/map03_waves.json",
};
const extra = [_][]const u8{
    "attribution.txt",
    "readme.txt",
};
const all_assets = maps ++ music ++ sounds ++ textures ++ tables ++ extra;

fn installAssets(b: *std.build.Builder) void {
    for (all_assets) |path| {
        b.installFile(path, path);
    }
}
