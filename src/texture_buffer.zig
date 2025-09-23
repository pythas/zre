const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

pub const DrawError = error{
    OutOfBounds,
    InvalidCoordinates,
};

pub const LineMode = enum {
    Filled,
    Dotted,
};

pub const TextureBuffer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    bit_depth: u32,
    data: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        width: usize,
        height: usize,
        bit_depth: usize,
    ) !Self {
        const size = width * height * bit_depth;
        const data = try allocator.alloc(u8, size);
        @memset(data, 0);

        return .{
            .width = @intCast(width),
            .height = @intCast(height),
            .bit_depth = @intCast(bit_depth),
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data);
    }

    pub fn drawPixel(self: *Self, x: i32, y: i32, color: wgpu.Color) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) {
            return;
        }

        const offset = @as(usize, @intCast((y * @as(i32, @intCast(self.width)) + x) * @as(i32, @intCast(self.bit_depth))));

        self.data[offset] = @intFromFloat(@trunc(color.r * 255));
        self.data[offset + 1] = @intFromFloat(@trunc(color.g * 255));
        self.data[offset + 2] = @intFromFloat(@trunc(color.b * 255));
        self.data[offset + 3] = @intFromFloat(@trunc(color.a * 255));
    }

    pub fn drawPoint(self: *Self, x: i32, y: i32, size: i32, color: wgpu.Color) void {
        const halfSize = @divFloor(size, 2);
        var dy = -halfSize;

        while (dy <= halfSize) {
            var dx = -halfSize;

            while (dx <= halfSize) {
                self.drawPixel(x + dx, y + dy, color);
                dx += 1;
            }

            dy += 1;
        }
    }

    pub fn drawVerticalLineSegment(self: *Self, x: i32, y0: i32, y1: i32, color: wgpu.Color) void {
        if (x < 0 or x > self.width) {
            return;
        }

        const y_start = @max(0, @min(y0, @as(i32, @intCast(self.height)) - 1));
        const y_end = @max(0, @min(y1, @as(i32, @intCast(self.height)) - 1));

        if (y_start > y_end) {
            return;
        }

        for (y_start..y_end) |y| {
            drawPixel(self, x, @intCast(y), color);
        }
    }

    pub fn drawHorizontalLine(self: *Self, y: i32, line_mode: LineMode, color: wgpu.Color) void {
        var x: i32 = 0;

        while (x < self.width) {
            self.drawPixel(x, y, color);

            if (line_mode == .Filled) {
                x += 1;
            } else if (line_mode == .Dotted) {
                x += 4;
            }
        }
    }

    pub fn drawVerticalLine(self: *Self, x: i32, line_mode: LineMode, color: wgpu.Color) void {
        var y: i32 = 0;

        while (y < self.width) {
            self.drawPixel(x, y, color);

            if (line_mode == .Filled) {
                y += 1;
            } else if (line_mode == .Dotted) {
                y += 4;
            }
        }
    }

    pub fn drawLine(self: *Self, x0: i32, y0: i32, x1: i32, y1: i32, color: wgpu.Color) void {
        if (@abs(y1 - y0) < @abs(x1 - x0)) {
            if (x0 > x1) {
                self.drawLineLow(x1, y1, x0, y0, color);
            } else {
                self.drawLineLow(x0, y0, x1, y1, color);
            }
        } else {
            if (y0 > y1) {
                self.drawLineHigh(x1, y1, x0, y0, color);
            } else {
                self.drawLineHigh(x0, y0, x1, y1, color);
            }
        }
    }

    fn drawLineLow(self: *Self, x0: i32, y0: i32, x1: i32, y1: i32, color: wgpu.Color) void {
        const dx = x1 - x0;
        var dy = y1 - y0;
        var yi: i32 = 1;

        if (dy < 0) {
            yi = -1;
            dy = -dy;
        }

        var d: i64 = (2 * dy) - dx;
        var y = y0;
        var x = x0;

        while (x < x1) {
            self.drawPixel(@intCast(x), y, color);

            if (d > 0) {
                y = y + yi;
                d = d + 2 * (dy - dx);
            } else {
                d = d + 2 * dy;
            }

            x = x + 1;
        }
    }

    fn drawLineHigh(self: *Self, x0: i32, y0: i32, x1: i32, y1: i32, color: wgpu.Color) void {
        var dx = x1 - x0;
        const dy = y1 - y0;
        var xi: i32 = 1;

        if (dx < 0) {
            xi = -1;
            dx = -dx;
        }

        var d: i64 = 2 * dx - dy;
        var x = x0;
        var y = y0;

        while (y < y1) {
            self.drawPixel(x, @intCast(y), color);

            if (d > 0) {
                x = x + xi;
                d = d + 2 * (dx - dy);
            } else {
                d = d + 2 * dx;
            }

            y = y + 1;
        }
    }

    pub fn clear(self: *Self, color: wgpu.Color) !void {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                drawPixel(self, @intCast(x), @intCast(y), color);
            }
        }
    }
};
