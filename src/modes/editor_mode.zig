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
    current_texture: u8 = 0,
    select_x: i32 = -1,
    select_y: i32 = -1,
    hover_x: i32 = -1,
    hover_y: i32 = -1,

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

        self.screen.upload();

        zgui.setNextWindowPos(.{ .x = 20.0 + 20.0 + 600.0, .y = 20, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = 160.0, .h = 400.0, .cond = .first_use_ever });
        if (zgui.begin("Texture", .{ .flags = .{ .no_resize = true, .no_collapse = true } })) {
            zgui.text("Current: {}", .{self.current_texture});

            // TODO: replace 0..num_textures with your real list
            // Replace your loop with this:
            for (0..16) |i| {
                var buf: [32]u8 = undefined;
                const label = try std.fmt.bufPrintZ(&buf, "Texture {}", .{i});
                if (zgui.selectable(label, .{ .selected = (self.current_texture == i) })) {
                    self.current_texture = @intCast(i);
                }
            }

            if (self.select_x >= 0 and self.select_y >= 0) {
                if (zgui.button("Apply to selected", .{ .w = 0, .h = 0 })) {
                    var tile = map.getTile(self.select_x, self.select_y);
                    if (tile.kind == .Empty) tile.kind = .Wall;
                    tile.texture = self.current_texture;
                    map.updateTile(self.select_x, self.select_y, tile);
                }
            } else {
                zgui.textDisabled("Select a tile to apply", .{});
            }
        }
        zgui.end();

        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = 600.0, .h = 400.0, .cond = .first_use_ever });

        if (zgui.begin("Editor", .{ .flags = .{ .no_resize = true, .no_collapse = true, .no_move = true } })) {
            const texture_id = self.gctx.lookupResource(self.screen.texture_view).?;
            zgui.image(texture_id, .{
                .w = @floatFromInt(self.screen.texture_buffer.width),
                .h = @floatFromInt(self.screen.texture_buffer.height),
            });

            if (zgui.isItemHovered(.{})) {
                const img_min = zgui.getItemRectMin();
                const mp = zgui.getMousePos();
                const local_x = mp[0] - img_min[0];
                const local_y = mp[1] - img_min[1];

                const tile_x = @as(i32, @intFromFloat((local_x + @as(f32, @floatFromInt(self.scroll_x))) / self.grid_size));
                const tile_y = @as(i32, @intCast(map.height)) - 1 - @as(i32, @intFromFloat((local_y + @as(f32, @floatFromInt(self.scroll_y))) / self.grid_size));

                if (tile_x >= 0 and tile_x < @as(i32, @intCast(map.width)) and
                    tile_y >= 0 and tile_y < @as(i32, @intCast(map.height)))
                {
                    self.hover_x = tile_x;
                    self.hover_y = tile_y;
                } else {
                    self.hover_x = -1;
                    self.hover_y = -1;
                }

                if (zgui.isMouseClicked(.left)) {
                    var tile = map.getTile(tile_x, tile_y);

                    if (zgui.isKeyDown(.left_shift)) {
                        tile.kind = .Wall;
                        tile.texture = self.current_texture;

                        map.updateTile(tile_x, tile_y, tile);
                    } else if (zgui.isKeyDown(.left_alt)) {
                        if (tile.kind != .Empty) {
                            self.current_texture = tile.texture.?;
                        }
                    } else {
                        if (tile.kind != .Empty) {
                            self.select_x = tile_x;
                            self.select_y = tile_y;
                        }
                    }
                }

                if (zgui.isMouseDown(.left) and zgui.isKeyDown(.left_shift)) {
                    var tile = map.getTile(tile_x, tile_y);
                    tile.kind = .Wall;
                    tile.texture = self.current_texture;

                    map.updateTile(tile_x, tile_y, tile);
                }

                if (zgui.isMouseDown(.right)) {
                    map.updateTile(tile_x, tile_y, Tile.initEmpty());
                }
            } else {
                self.hover_x = -1;
                self.hover_y = -1;
            }
        }

        zgui.end();
    }

    fn drawGrid(self: *Self) !void {
        var tb = self.screen.texture_buffer;
        const grid: i32 = @intFromFloat(self.grid_size);

        var y: i32 = 0;
        var row: i32 = 0;
        while (y <= tb.height) : (y += grid) {
            const major = (@mod(row, 4) == 0);
            const c: zgpu.wgpu.Color = if (major)
                .{ .r = 0.45, .g = 0.45, .b = 0.52, .a = 0.35 }
            else
                .{ .r = 0.35, .g = 0.35, .b = 0.40, .a = 0.20 };
            tb.drawHorizontalLine(y, .Dotted, c);
            row += 1;
        }

        var x: i32 = 0;
        var col: i32 = 0;
        while (x <= tb.width) : (x += grid) {
            const major = (@mod(col, 4) == 0);
            const c: zgpu.wgpu.Color = if (major)
                .{ .r = 0.45, .g = 0.45, .b = 0.52, .a = 0.35 }
            else
                .{ .r = 0.35, .g = 0.35, .b = 0.40, .a = 0.20 };
            tb.drawVerticalLine(x, .Dotted, c);
            col += 1;
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

                const screen_x = self.scroll_x + x_i32 * grid_size;
                const screen_y = self.scroll_y + (@as(i32, @intCast(map.height)) - 1 - y_i32) * grid_size;

                switch (tile.kind) {
                    .Empty => {},
                    .Wall => {
                        tb.drawFillRect(
                            screen_x,
                            screen_y,
                            grid_size,
                            grid_size,
                            color.getColor(.Surface),
                        );

                        tb.drawRect(
                            screen_x,
                            screen_y,
                            grid_size,
                            grid_size,
                            color.getColor(.PrimaryActive),
                        );
                    },
                }
            }
        }

        if (self.hover_x >= 0 and self.hover_y >= 0) {
            const screen_x = self.scroll_x + self.hover_x * grid_size;
            const screen_y = self.scroll_y + (@as(i32, @intCast(map.height)) - 1 - self.hover_y) * grid_size;

            tb.drawRect(
                screen_x,
                screen_y,
                grid_size,
                grid_size,
                color.getColor(.PrimaryHover),
            );
        }

        if (self.select_x >= 0 and self.select_y >= 0) {
            const sx = self.scroll_x + self.select_x * grid_size;
            const sy = self.scroll_y + (@as(i32, @intCast(map.height)) - 1 - self.select_y) * grid_size;

            // outer border
            tb.drawRect(sx, sy, grid_size, grid_size, color.getColor(.PrimarySelected));
            // "2px" look by insetting 1px and drawing again
            tb.drawRect(sx + 1, sy + 1, grid_size - 2, grid_size - 2, color.getColor(.PrimarySelected));

            // subtle inner overlay to differentiate selected from hover
            tb.drawFillRect(
                sx + 2,
                sy + 2,
                grid_size - 4,
                grid_size - 4,
                .{ .r = 0.30, .g = 0.65, .b = 1.00, .a = 0.10 }, // translucent accent
            );
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

    pub fn render(self: *Self, pass: zgpu.wgpu.RenderPassEncoder) !void {
        zgui.backend.newFrame(self.width, self.height);

        try self.map_ui.render(self.map);

        zgui.backend.draw(pass);
    }
};
