const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zgui = @import("zgui");

const StreamingTexture = @import("../streaming_texture.zig").StreamingTexture;
const Map = @import("../map.zig").Map;
const Tile = @import("../map.zig").Tile;
const color = @import("../color.zig");

pub const MapUi = struct {
    const Self = @This();

    gctx: *zgpu.GraphicsContext,
    screen: StreamingTexture,
    grid_size: f32 = 16,
    scroll_x: i32 = 0,
    scroll_y: i32 = 0,
    dirty: bool = true,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        bind_group_layout: zgpu.BindGroupLayoutHandle,
        uniforms_buffer: zgpu.BufferHandle,
        width: u32,
        height: u32,
    ) !Self {
        const screen = try StreamingTexture.init(
            allocator,
            gctx,
            bind_group_layout,
            uniforms_buffer,
            width,
            height,
        );

        return .{
            .gctx = gctx,
            .screen = screen,
        };
    }

    pub fn render(self: *Self, map: *Map) !void {
        self.screen.texture_buffer.clear(color.getColor(.Black));

        try self.drawGrid();
        try self.drawMap(map);

        if (self.dirty) {
            self.screen.upload();
            self.dirty = false;
        }

        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = 600.0, .h = 400.0, .cond = .first_use_ever });

        if (zgui.begin("Editor", .{ .flags = .{ .no_resize = true, .no_collapse = true } })) {
            const texture_id = self.gctx.lookupResource(self.screen.texture_view).?;
            zgui.image(texture_id, .{
                .w = @floatFromInt(self.screen.texture_buffer.width),
                .h = @floatFromInt(self.screen.texture_buffer.height),
            });

            if (zgui.isItemHovered(.{}) and zgui.isMouseClicked(.right)) {
                const img_min = zgui.getItemRectMin();
                const mp = zgui.getMousePos();
                const local_x = mp[0] - img_min[0];
                const local_y = mp[1] - img_min[1];

                const tile_x = @as(i32, @intFromFloat((local_x + @as(f32, @floatFromInt(self.scroll_x))) / self.grid_size));
                const tile_y = @as(i32, @intFromFloat((local_y + @as(f32, @floatFromInt(self.scroll_y))) / self.grid_size));

                map.updateTile(tile_x, tile_y, Tile.initEmpty());
                self.dirty = true;
            }
        }

        zgui.end();
    }

    fn drawGrid(self: *Self) !void {
        var texture_buffer = self.screen.texture_buffer;

        const grid_size: i32 = @intFromFloat(self.grid_size);
        var x: i32 = grid_size;
        var y: i32 = grid_size;

        var i: usize = 0;
        while (y < texture_buffer.height) {
            if (i % 2 == 0) {
                texture_buffer.drawHorizontalLine(y, .Dotted, .{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 0.5 });
            } else {
                texture_buffer.drawHorizontalLine(y, .Dotted, .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 0.5 });
            }

            y += grid_size;
            i += 1;
        }

        i = 0;
        while (x < texture_buffer.width) {
            if (i % 2 == 0) {
                texture_buffer.drawVerticalLine(x, .Dotted, .{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 0.5 });
            } else {
                texture_buffer.drawVerticalLine(x, .Dotted, .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 0.5 });
            }

            x += grid_size;
            i += 1;
        }
    }

    fn drawMap(self: *Self, map: *Map) !void {
        var tb = self.screen.texture_buffer;
        const grid_size: i32 = @intFromFloat(self.grid_size);

        for (0..map.height) |y| {
            for (0..map.width) |x| {
                const x_i32: i32 = @intCast(x);
                const y_i32: i32 = @intCast(y);

                const tile = map.getTile(x_i32, y_i32);

                const color_optional: ?zgpu.wgpu.Color = switch (tile.kind) {
                    .Empty => null,
                    .Wall => color.getColor(.White),
                };

                if (color_optional) |col| {
                    tb.drawFillRect(
                        self.scroll_x + x_i32 * grid_size,
                        self.scroll_y + y_i32 * grid_size,
                        grid_size,
                        grid_size,
                        col,
                    );
                }
            }
        }
    }
};

pub const EditorMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    width: u32,
    height: u32,
    map_ui: MapUi,
    map: *Map,

    pub const Config = struct {
        map: *Map,
        bind_group_layout: zgpu.BindGroupLayoutHandle,
        uniforms_buffer: zgpu.BufferHandle,
        window: *zglfw.Window,
    };

    pub fn init(allocator: std.mem.Allocator, gctx: *zgpu.GraphicsContext, config: Config) !Self {
        const width = gctx.swapchain_descriptor.width;
        const height = gctx.swapchain_descriptor.height;

        zgui.init(allocator);
        zgui.backend.init(
            config.window,
            gctx.device,
            @intFromEnum(zgpu.GraphicsContext.swapchain_format),
            @intFromEnum(zgpu.wgpu.TextureFormat.undef),
        );
        return .{
            .allocator = allocator,
            .gctx = gctx,
            .width = width,
            .height = height,
            .map_ui = try MapUi.init(
                allocator,
                gctx,
                config.bind_group_layout,
                config.uniforms_buffer,
                600,
                400,
            ),
            .map = config.map,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;

        zgui.backend.deinit();
        zgui.deinit();
    }

    pub fn update(self: *Self, dt: f32) !void {
        _ = self;
        _ = dt;
    }

    pub fn render(self: *Self, pass: zgpu.wgpu.RenderPassEncoder) void {
        zgui.backend.newFrame(self.width, self.height);

        try self.map_ui.render(self.map);

        zgui.backend.draw(pass);
    }
};
