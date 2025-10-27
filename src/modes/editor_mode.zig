const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zgui = @import("zgui");

const StreamingTexture = @import("../streaming_texture.zig").StreamingTexture;
const Map = @import("../map.zig").Map;
const Tile = @import("../map.zig").Tile;
const MapResult = @import("../map.zig").MapResult;
const color = @import("../color.zig");

pub const MapUi = struct {
    const Self = @This();

    const Tool = enum {
        select,
        paint,
        erase,
    };

    gctx: *zgpu.GraphicsContext,
    screen: StreamingTexture,
    grid_size: f32 = 16,
    scroll_x: i32 = 0,
    scroll_y: i32 = 0,
    current_texture: u8 = 0,
    current_tile_kind: Tile.Kind = .Wall,
    select_x: i32 = -1,
    select_y: i32 = -1,
    hover_x: i32 = -1,
    hover_y: i32 = -1,
    thumbs: std.ArrayList([16 * 16]u32),
    thumb_textures: std.ArrayList(zgpu.TextureHandle),
    thumb_views: std.ArrayList(zgpu.TextureViewHandle),
    map: *Map,
    pan_start_x: f32 = 0,
    pan_start_y: f32 = 0,
    is_panning: bool = false,
    current_tool: Tool = .select,
    selection_start_x: i32 = -1,
    selection_start_y: i32 = -1,
    selection_end_x: i32 = -1,
    selection_end_y: i32 = -1,
    is_selecting: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        bind_group_layout: zgpu.BindGroupLayoutHandle,
        uniforms_buffer: zgpu.BufferHandle,
        map: *Map,
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

        var thumbs = std.ArrayList([16 * 16]u32).init(allocator);
        var thumb_textures = std.ArrayList(zgpu.TextureHandle).init(allocator);
        var thumb_views = std.ArrayList(zgpu.TextureViewHandle).init(allocator);
        
        for (map.textures.items) |texture| {
            const thumb_data = makeThumb64to16(texture.data);
            try thumbs.append(thumb_data);
            
            // Create GPU texture for this thumbnail
            const thumb_texture = gctx.createTexture(.{
                .usage = .{ .texture_binding = true, .copy_dst = true },
                .size = .{ .width = 16, .height = 16, .depth_or_array_layers = 1 },
                .format = .rgba8_unorm,
                .mip_level_count = 1,
            });
            
            const thumb_view = gctx.createTextureView(thumb_texture, .{});
            
            // Upload thumbnail data
            gctx.queue.writeTexture(
                .{ .texture = gctx.lookupResource(thumb_texture).? },
                .{ .bytes_per_row = 16 * 4, .rows_per_image = 16 },
                .{ .width = 16, .height = 16 },
                u32,
                thumb_data[0..],
            );
            
            try thumb_textures.append(thumb_texture);
            try thumb_views.append(thumb_view);
        }

        return .{
            .gctx = gctx,
            .screen = screen,
            .map = map,
            .thumbs = thumbs,
            .thumb_textures = thumb_textures,
            .thumb_views = thumb_views,
        };
    }

    pub fn render(self: *Self) !void {
        self.screen.texture_buffer.clear(color.getColor(.Black));

        try self.drawGrid();
        try self.drawMap();

        self.screen.upload();

        // Mode selector window
        zgui.setNextWindowPos(.{ .x = 20.0 + 20.0 + 600.0, .y = 20, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = 160.0, .h = 120.0, .cond = .first_use_ever });
        if (zgui.begin("Mode", .{ .flags = .{ .no_resize = true, .no_collapse = true } })) {
            zgui.text("Shortcuts: Z/X/C", .{});
            zgui.separator();
            
            // Handle mode shortcuts
            if (zgui.isKeyPressed(.z, false)) self.current_tool = .select;
            if (zgui.isKeyPressed(.x, false)) self.current_tool = .paint;
            if (zgui.isKeyPressed(.c, false)) self.current_tool = .erase;
            
            if (zgui.selectable("Z: Select", .{ .selected = (self.current_tool == .select) })) {
                self.current_tool = .select;
            }
            if (zgui.selectable("X: Paint", .{ .selected = (self.current_tool == .paint) })) {
                self.current_tool = .paint;
            }
            if (zgui.selectable("C: Erase", .{ .selected = (self.current_tool == .erase) })) {
                self.current_tool = .erase;
            }
        }
        zgui.end();

        // Tile Type Window
        zgui.setNextWindowPos(.{ .x = 20.0 + 20.0 + 600.0, .y = 20 + 120 + 10, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = 160.0, .h = 230.0, .cond = .first_use_ever });
        if (zgui.begin("Tile Type", .{ .flags = .{ .no_resize = true, .no_collapse = true } })) {
            zgui.text("Shortcuts: F1-F3", .{});
            zgui.separator();
            
            // Handle keyboard shortcuts
            if (zgui.isKeyPressed(.f1, false)) self.current_tile_kind = .Empty;
            if (zgui.isKeyPressed(.f2, false)) self.current_tile_kind = .Wall;
            if (zgui.isKeyPressed(.f3, false)) self.current_tile_kind = .Lava;
            
            if (zgui.selectable("F1: Empty", .{ .selected = (self.current_tile_kind == .Empty) })) {
                self.current_tile_kind = .Empty;
            }
            if (zgui.selectable("F2: Wall", .{ .selected = (self.current_tile_kind == .Wall) })) {
                self.current_tile_kind = .Wall;
            }
            if (zgui.selectable("F3: Lava", .{ .selected = (self.current_tile_kind == .Lava) })) {
                self.current_tile_kind = .Lava;
            }

            zgui.separator();

            // Show selection info or apply button
            const has_selection = self.selection_start_x >= 0 and self.selection_end_x >= 0;
            if (has_selection) {
                const min_x = @min(self.selection_start_x, self.selection_end_x);
                const max_x = @max(self.selection_start_x, self.selection_end_x);
                const min_y = @min(self.selection_start_y, self.selection_end_y);
                const max_y = @max(self.selection_start_y, self.selection_end_y);
                const count = (max_x - min_x + 1) * (max_y - min_y + 1);
                
                zgui.text("Selected: {} tiles", .{count});
                zgui.separator();
                
                if (zgui.button("Apply Type", .{ .w = -1, .h = 0 })) {
                    var y: i32 = min_y;
                    while (y <= max_y) : (y += 1) {
                        var x: i32 = min_x;
                        while (x <= max_x) : (x += 1) {
                            const tile = self.map.getTile(x, y);
                            var new_tile = tile;
                            new_tile.kind = self.current_tile_kind;
                            // Keep existing texture when changing type
                            self.map.updateTile(x, y, new_tile);
                        }
                    }
                }
                
                if (zgui.button("Apply Texture", .{ .w = -1, .h = 0 })) {
                    var y: i32 = min_y;
                    while (y <= max_y) : (y += 1) {
                        var x: i32 = min_x;
                        while (x <= max_x) : (x += 1) {
                            const tile = self.map.getTile(x, y);
                            if (tile.kind != .Empty) {
                                var new_tile = tile;
                                new_tile.texture = self.current_texture;
                                self.map.updateTile(x, y, new_tile);
                            }
                        }
                    }
                }
                
                if (zgui.button("Clear Selection", .{ .w = -1, .h = 0 })) {
                    self.selection_start_x = -1;
                    self.selection_start_y = -1;
                    self.selection_end_x = -1;
                    self.selection_end_y = -1;
                }
            } else if (self.select_x >= 0 and self.select_y >= 0) {
                const tile = self.map.getTile(self.select_x, self.select_y);
                zgui.text("Selected: ({}, {})", .{self.select_x, self.select_y});
                zgui.text("Type: {s}", .{@tagName(tile.kind)});
                if (tile.kind != .Empty) {
                    zgui.text("Texture: {}", .{tile.texture});
                }
                zgui.separator();
                
                if (zgui.button("Apply to selected", .{ .w = -1, .h = 0 })) {
                    var new_tile = tile;
                    new_tile.kind = self.current_tile_kind;
                    if (new_tile.kind != .Empty) {
                        new_tile.texture = self.current_texture;
                    }
                    self.map.updateTile(self.select_x, self.select_y, new_tile);
                }
            } else {
                zgui.textDisabled("No tile selected", .{});
            }
        }
        zgui.end();

        // Texture Window - compact with image previews
        zgui.setNextWindowPos(.{ .x = 20.0 + 20.0 + 600.0, .y = 20 + 120 + 10 + 230 + 10, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = 160.0, .h = 220.0, .cond = .first_use_ever });
        if (zgui.begin("Texture", .{ .flags = .{ .no_resize = true, .no_collapse = true } })) {
            zgui.text("Q/W | Current: {}", .{self.current_texture});
            zgui.separator();

            // Handle Q/W keys for cycling textures
            if (zgui.isKeyPressed(.q, false)) {
                if (self.current_texture > 0) {
                    self.current_texture -= 1;
                } else {
                    self.current_texture = 15;
                }
            }
            if (zgui.isKeyPressed(.w, false)) {
                self.current_texture = (self.current_texture + 1) % 16;
            }

            // Show 4 textures per row with images
            const textures_to_show = @min(self.thumb_views.items.len, 16);
            var i: usize = 0;
            while (i < textures_to_show) : (i += 1) {
                const thumb_view = self.thumb_views.items[i];
                const texture_id = self.gctx.lookupResource(thumb_view).?;
                
                const is_selected = (self.current_texture == i);
                
                // Use darker background for texture preview
                if (is_selected) {
                    zgui.pushStyleColor4f(.{ .idx = .button, .c = .{ 0.3, 0.6, 1.0, 0.4 } });
                } else {
                    zgui.pushStyleColor4f(.{ .idx = .button, .c = .{ 0.15, 0.15, 0.15, 1.0 } });
                }
                zgui.pushStyleColor4f(.{ .idx = .button_hovered, .c = .{ 0.25, 0.25, 0.25, 1.0 } });
                
                var buf: [8]u8 = undefined;
                const label = try std.fmt.bufPrintZ(&buf, "##{}", .{i});
                
                if (zgui.imageButton(label, texture_id, .{ .w = 32, .h = 32 })) {
                    self.current_texture = @intCast(i);
                }
                
                zgui.popStyleColor(.{ .count = 2 });
                
                // 4 per row
                if (@mod(i + 1, 4) != 0) {
                    zgui.sameLine(.{});
                }
            }
        }
        zgui.end();

        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = 600.0, .h = 380.0, .cond = .first_use_ever });

        if (zgui.begin("Editor", .{ .flags = .{ .no_resize = true, .no_collapse = true, .no_move = true } })) {
            // Status bar at top
            zgui.text("Mode: {s}", .{@tagName(self.current_tool)});
            zgui.sameLine(.{});
            if (self.hover_x >= 0 and self.hover_y >= 0) {
                const tile = self.map.getTile(self.hover_x, self.hover_y);
                zgui.text(" | Pos: ({}, {}) | Type: {s} | Tex: {}", .{
                    self.hover_x, self.hover_y, @tagName(tile.kind), tile.texture
                });
            } else {
                zgui.text(" | Hover over map", .{});
            }
            
            zgui.separator();
            
            switch (self.current_tool) {
                .select => zgui.text("Drag to select multiple tiles | Shift: Add to selection", .{}),
                .paint => zgui.text("Click/Drag to paint | Alt: Pick tile", .{}),
                .erase => zgui.text("Click/Drag to erase tiles", .{}),
            }
            
            zgui.separator();

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
                const tile_y = @as(i32, @intCast(self.map.height)) - 1 - @as(i32, @intFromFloat((local_y + @as(f32, @floatFromInt(self.scroll_y))) / self.grid_size));

                if (tile_x >= 0 and tile_x < @as(i32, @intCast(self.map.width)) and
                    tile_y >= 0 and tile_y < @as(i32, @intCast(self.map.height)))
                {
                    self.hover_x = tile_x;
                    self.hover_y = tile_y;
                } else {
                    self.hover_x = -1;
                    self.hover_y = -1;
                }

                // Middle mouse button panning
                if (zgui.isMouseClicked(.middle)) {
                    self.is_panning = true;
                    self.pan_start_x = mp[0];
                    self.pan_start_y = mp[1];
                }
                
                if (self.is_panning) {
                    const dx = mp[0] - self.pan_start_x;
                    const dy = mp[1] - self.pan_start_y;
                    self.scroll_x += @intFromFloat(dx);
                    self.scroll_y += @intFromFloat(dy);
                    self.pan_start_x = mp[0];
                    self.pan_start_y = mp[1];
                }

                if (zgui.isMouseClicked(.left)) {
                    switch (self.current_tool) {
                        .select => {
                            // Start new selection (shift adds to selection by not clearing)
                            if (!zgui.isKeyDown(.left_shift)) {
                                // Start fresh selection if not holding shift
                                self.selection_start_x = tile_x;
                                self.selection_start_y = tile_y;
                                self.selection_end_x = tile_x;
                                self.selection_end_y = tile_y;
                            } else {
                                // Extend existing selection to include clicked tile
                                if (self.selection_start_x < 0) {
                                    // No existing selection, start new
                                    self.selection_start_x = tile_x;
                                    self.selection_start_y = tile_y;
                                    self.selection_end_x = tile_x;
                                    self.selection_end_y = tile_y;
                                } else {
                                    // Extend to include clicked point
                                    self.selection_start_x = @min(self.selection_start_x, tile_x);
                                    self.selection_start_y = @min(self.selection_start_y, tile_y);
                                    self.selection_end_x = @max(self.selection_end_x, tile_x);
                                    self.selection_end_y = @max(self.selection_end_y, tile_y);
                                }
                            }
                            self.is_selecting = true;
                            self.select_x = tile_x;
                            self.select_y = tile_y;
                        },
                        .paint => {
                            if (zgui.isKeyDown(.left_alt)) {
                                // Pick mode
                                const tile = self.map.getTile(tile_x, tile_y);
                                if (tile.kind != .Empty) {
                                    self.current_texture = tile.texture;
                                    self.current_tile_kind = tile.kind;
                                }
                            } else {
                                // Paint
                                var tile = self.map.getTile(tile_x, tile_y);
                                tile.kind = self.current_tile_kind;
                                if (tile.kind != .Empty) {
                                    tile.texture = self.current_texture;
                                }
                                self.map.updateTile(tile_x, tile_y, tile);
                            }
                        },
                        .erase => {
                            self.map.updateTile(tile_x, tile_y, Tile.initEmpty());
                        },
                    }
                }

                // Handle drag operations
                if (zgui.isMouseDown(.left)) {
                    switch (self.current_tool) {
                        .select => {
                            if (self.is_selecting) {
                                self.selection_end_x = tile_x;
                                self.selection_end_y = tile_y;
                            }
                        },
                        .paint => {
                            if (!zgui.isKeyDown(.left_alt)) {
                                var tile = self.map.getTile(tile_x, tile_y);
                                tile.kind = self.current_tile_kind;
                                if (tile.kind != .Empty) {
                                    tile.texture = self.current_texture;
                                }
                                self.map.updateTile(tile_x, tile_y, tile);
                            }
                        },
                        .erase => {
                            self.map.updateTile(tile_x, tile_y, Tile.initEmpty());
                        },
                    }
                }

                // Stop selecting on mouse release
                if (zgui.isMouseReleased(.left)) {
                    self.is_selecting = false;
                }
            } else {
                self.hover_x = -1;
                self.hover_y = -1;
            }
            
            // Stop panning when mouse released
            if (zgui.isMouseReleased(.middle)) {
                self.is_panning = false;
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

    fn drawMap(self: *Self) !void {
        var tb = self.screen.texture_buffer;
        const grid_size: i32 = @intFromFloat(self.grid_size);

        for (0..self.map.height) |y| {
            for (0..self.map.width) |x| {
                const x_i32: i32 = @intCast(x);
                const y_i32: i32 = @intCast(y);

                const tile = self.map.getTile(x_i32, y_i32);

                const screen_x = self.scroll_x + x_i32 * grid_size;
                const screen_y = self.scroll_y + (@as(i32, @intCast(self.map.height)) - 1 - y_i32) * grid_size;

                switch (tile.kind) {
                    .Empty => {},
                    .Wall => {
                        self.screen.texture_buffer.blit16x16(screen_x, screen_y, &self.thumbs.items[tile.texture]);
                    },
                    .Lava => {
                        // Draw texture first, then orange overlay
                        self.screen.texture_buffer.blit16x16(screen_x, screen_y, &self.thumbs.items[tile.texture]);
                        tb.drawFillRect(
                            screen_x,
                            screen_y,
                            grid_size,
                            grid_size,
                            .{ .r = 1.0, .g = 0.3, .b = 0.0, .a = 0.5 },
                        );
                        tb.drawRect(
                            screen_x,
                            screen_y,
                            grid_size,
                            grid_size,
                            .{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0 },
                        );
                    },
                }
            }
        }

        if (self.hover_x >= 0 and self.hover_y >= 0) {
            const screen_x = self.scroll_x + self.hover_x * grid_size;
            const screen_y = self.scroll_y + (@as(i32, @intCast(self.map.height)) - 1 - self.hover_y) * grid_size;

            // Show paint preview in paint mode
            if (self.current_tool == .paint) {
                switch (self.current_tile_kind) {
                    .Empty => {
                        tb.drawFillRect(
                            screen_x,
                            screen_y,
                            grid_size,
                            grid_size,
                            .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 0.5 },
                        );
                    },
                    .Wall => {
                        tb.drawFillRect(
                            screen_x,
                            screen_y,
                            grid_size,
                            grid_size,
                            .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 0.3 },
                        );
                    },
                    .Lava => {
                        tb.drawFillRect(
                            screen_x,
                            screen_y,
                            grid_size,
                            grid_size,
                            .{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 0.5 },
                        );
                    },
                }
            }

            tb.drawRect(
                screen_x,
                screen_y,
                grid_size,
                grid_size,
                color.getColor(.PrimaryHover),
            );
        }

        // Draw selection rectangle
        if (self.selection_start_x >= 0 and self.selection_end_x >= 0) {
            const min_x = @min(self.selection_start_x, self.selection_end_x);
            const max_x = @max(self.selection_start_x, self.selection_end_x);
            const min_y = @min(self.selection_start_y, self.selection_end_y);
            const max_y = @max(self.selection_start_y, self.selection_end_y);
            
            const sel_start_x = self.scroll_x + min_x * grid_size;
            const sel_start_y = self.scroll_y + (@as(i32, @intCast(self.map.height)) - 1 - max_y) * grid_size;
            const sel_width = (max_x - min_x + 1) * grid_size;
            const sel_height = (max_y - min_y + 1) * grid_size;
            
            // Draw selection overlay
            tb.drawFillRect(
                sel_start_x,
                sel_start_y,
                sel_width,
                sel_height,
                .{ .r = 0.3, .g = 0.6, .b = 1.0, .a = 0.15 },
            );
            
            // Draw selection border
            tb.drawRect(sel_start_x, sel_start_y, sel_width, sel_height, .{ .r = 0.3, .g = 0.6, .b = 1.0, .a = 1.0 });
            tb.drawRect(sel_start_x + 1, sel_start_y + 1, sel_width - 2, sel_height - 2, .{ .r = 0.3, .g = 0.6, .b = 1.0, .a = 1.0 });
        }

        if (self.select_x >= 0 and self.select_y >= 0) {
            const sx = self.scroll_x + self.select_x * grid_size;
            const sy = self.scroll_y + (@as(i32, @intCast(self.map.height)) - 1 - self.select_y) * grid_size;

            tb.drawRect(sx, sy, grid_size, grid_size, color.getColor(.PrimarySelected));
            tb.drawRect(sx + 1, sy + 1, grid_size - 2, grid_size - 2, color.getColor(.PrimarySelected));

            tb.drawFillRect(
                sx + 2,
                sy + 2,
                grid_size - 4,
                grid_size - 4,
                .{ .r = 0.30, .g = 0.65, .b = 1.00, .a = 0.10 },
            );
        }
    }

    fn makeThumb64to16(src: []const u8) [16 * 16]u32 {
        var out: [16 * 16]u32 = undefined;
        const src_w: usize = 64;
        const bpp: usize = 4;

        var y: usize = 0;
        while (y < 16) : (y += 1) {
            const sy = y * 4;
            var x: usize = 0;
            while (x < 16) : (x += 1) {
                const sx = x * 4;

                const i = (sy * src_w + sx) * bpp;
                const r: u32 = src[i + 0];
                const g: u32 = src[i + 1];
                const b: u32 = src[i + 2];
                const a: u32 = src[i + 3];

                out[y * 16 + x] = (r << 24) | (g << 16) | (b << 8) | a;
            }
        }
        return out;
    }
};

pub const EditorMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    window: *zglfw.Window,
    bind_group_layout: zgpu.BindGroupLayoutHandle,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    pipeline: zgpu.RenderPipelineHandle,
    uniforms_buffer: zgpu.BufferHandle,
    map_ui: MapUi,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map_result: *MapResult,
    ) !Self {
        const bind_group_layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            zgpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d, false),
            zgpu.samplerEntry(2, .{ .fragment = true }, .filtering),
        });
        const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});

        const uniforms_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = 256,
        });

        const pipeline = try createEditorPipeline(gctx, pipeline_layout);

        zgui.init(allocator);
        zgui.backend.init(
            window,
            gctx.device,
            @intFromEnum(zgpu.GraphicsContext.swapchain_format),
            @intFromEnum(zgpu.wgpu.TextureFormat.undef),
        );
        return .{
            .allocator = allocator,
            .gctx = gctx,
            .window = window,
            .bind_group_layout = bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .uniforms_buffer = uniforms_buffer,
            .map_ui = try MapUi.init(
                allocator,
                gctx,
                bind_group_layout,
                uniforms_buffer,
                &map_result.map,
                600,
                400,
            ),
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
        const fb_size = self.window.getFramebufferSize();
        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        try self.map_ui.render();

        zgui.backend.draw(pass);
    }
};

fn createEditorPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const wgpu = zgpu.wgpu;
    const vs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("../shaders/editor_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("../shaders/editor_fragment.wgsl"),
        "fs_main",
    );
    defer fs_module.release();

    const color_targets = [_]wgpu.ColorTargetState{
        .{ .format = gctx.swapchain_descriptor.format },
    };

    const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = 0,
            .buffers = null,
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .fragment = &wgpu.FragmentState{
            .module = fs_module,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
    };

    return gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
}
