const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

pub const Color = enum {
    Black,
    White,
};

pub fn getColor(color: Color) wgpu.Color {
    return switch (color) {
        .Black => .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 },
        .White => .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    };
}
