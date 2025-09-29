const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

pub const Color = enum {
    Black,
    Background,
    Surface,
    Border,
    Text,
    TextMuted,
    Primary,
    PrimaryHover,
    PrimaryActive,
    PrimarySelected,
    Error,
    Warning,
    Success,
};

pub fn getColor(color: Color) wgpu.Color {
    return switch (color) {
        .Black => .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        .Background => .{ .r = 0.10, .g = 0.10, .b = 0.12, .a = 1.0 },
        .Surface => .{ .r = 0.18, .g = 0.18, .b = 0.20, .a = 1.0 },
        .Border => .{ .r = 0.30, .g = 0.30, .b = 0.35, .a = 1.0 },
        .Text => .{ .r = 0.90, .g = 0.90, .b = 0.92, .a = 1.0 },
        .TextMuted => .{ .r = 0.60, .g = 0.62, .b = 0.65, .a = 1.0 },
        .Primary => .{ .r = 0.26, .g = 0.52, .b = 0.96, .a = 1.0 }, // bright blue
        .PrimaryHover => .{ .r = 0.38, .g = 0.65, .b = 1.00, .a = 1.0 }, // lighter, more vibrant
        .PrimaryActive => .{ .r = 0.18, .g = 0.38, .b = 0.80, .a = 1.0 }, // darker, still vibrant
        .PrimarySelected => .{ .r = 0.46, .g = 0.72, .b = 1.00, .a = 1.0 }, // very bright highlight
        .Error => .{ .r = 0.90, .g = 0.20, .b = 0.25, .a = 1.0 },
        .Warning => .{ .r = 1.00, .g = 0.65, .b = 0.20, .a = 1.0 },
        .Success => .{ .r = 0.20, .g = 0.75, .b = 0.35, .a = 1.0 },
    };
}
