const std = @import("std");
const Vec2 = @import("vec2.zig").Vec2;
const Light = @import("light.zig").Light;
const Map = @import("map.zig").Map;

pub const LightAccum = struct {
    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,

    pub fn addScaled(self: *LightAccum, color3: [3]f32, scale: f32) void {
        self.r += color3[0] * scale;
        self.g += color3[1] * scale;
        self.b += color3[2] * scale;
    }

    pub fn clamp01(self: *LightAccum) void {
        self.r = std.math.clamp(self.r, 0.0, 1.0);
        self.g = std.math.clamp(self.g, 0.0, 1.0);
        self.b = std.math.clamp(self.b, 0.0, 1.0);
    }
};

pub fn accumulatePlaneLights(
    lights: []const Light,
    plane_normal_z: f32, // +1 for floor, -1 for ceiling
    world_x: f32,
    world_y: f32,
    world_z: f32,
    diffuse_scale: f32,
) LightAccum {
    var acc: LightAccum = .{};

    for (lights) |light| {
        switch (light) {
            .point => |pl| {
                if (!pl.enabled) continue;
                const dx = pl.position.x - world_x;
                const dy = pl.position.y - world_y;
                const dz = pl.position.z - world_z;
                const d2: f32 = dx * dx + dy * dy + dz * dz;
                const d: f32 = @sqrt(d2) + 1e-4;
                const Lz: f32 = dz / d;
                const lambert: f32 = if (plane_normal_z > 0) @max(0.0, Lz) else @max(0.0, -Lz);
                if (lambert == 0.0) continue;
                var att: f32 = 1.0;
                switch (pl.attenuation) {
                    .quadratic => |qa| {
                        att = 1.0 / (1.0 + qa.linear * d + qa.quadratic * d2);
                    },
                    .radial => |ra| {
                        att = if (d > ra.radius) 0.0 else 1.0;
                    },
                }
                const scale = pl.intensity * lambert * att * diffuse_scale;
                acc.addScaled(pl.color, scale);
            },
            .directional => |dl| {
                if (!dl.enabled) continue;
                const n_dir = dl.direction.normalize().neg();
                const lambert: f32 = if (plane_normal_z > 0) @max(0.0, n_dir.z) else @max(0.0, -n_dir.z);
                if (lambert == 0.0) continue;
                const scale = dl.intensity * lambert * diffuse_scale;
                acc.addScaled(dl.color, scale);
            },
        }
    }

    return acc;
}

pub fn accumulateWallLights(
    lights: []const Light,
    n: Vec2,
    hit_point: Vec2,
    player_height: f32,
    light_height_bias: f32,
    diffuse_scale: f32,
) LightAccum {
    var acc: LightAccum = .{};
    for (lights) |light| {
        switch (light) {
            .point => |pl| {
                if (!pl.enabled) continue;
                const dx = pl.position.x - hit_point.x;
                const dy = pl.position.y - hit_point.y;
                const dz = player_height - light_height_bias; // vertical approximation
                const d2: f32 = dx * dx + dy * dy + dz * dz;
                const d: f32 = @sqrt(d2) + 1e-4;
                const Lx: f32 = dx / d;
                const Ly: f32 = dy / d;
                const Lz: f32 = dz / d;
                const lambert: f32 = @max(0.0, n.x * Lx + n.y * Ly + Lz);
                if (lambert == 0.0) continue;
                var att: f32 = 1.0;
                switch (pl.attenuation) {
                    .quadratic => |qa| {
                        att = 1.0 / (1.0 + qa.linear * d + qa.quadratic * d2);
                    },
                    .radial => |ra| {
                        att = if (d > ra.radius) 0.0 else 1.0;
                    },
                }
                const scale = pl.intensity * lambert * att * diffuse_scale;
                acc.addScaled(pl.color, scale);
            },
            .directional => |dl| {
                if (!dl.enabled) continue;
                const n_dir = dl.direction.normalize().neg();
                const lambert = @max(0.0, n.x * n_dir.x + n.y * n_dir.y);
                if (lambert == 0.0) continue;
                const scale = dl.intensity * lambert * diffuse_scale;
                acc.addScaled(dl.color, scale);
            },
        }
    }
    return acc;
}

pub fn getEmissiveIntensity(texture_index: u32, rs: Map.RenderSettings) f32 {
    for (rs.emissives) |e| if (e.index == texture_index) return e.intensity;
    return 0.0;
}

pub fn applyFog(enabled: bool, fog_color: [3]f32, density: f32, distance: f32, r: f32, g: f32, b: f32) [3]f32 {
    if (!enabled) return .{ r, g, b };
    const factor = std.math.exp(-density * distance);
    const fr = fog_color[0] * 255.0 + (r - fog_color[0] * 255.0) * factor;
    const fg = fog_color[1] * 255.0 + (g - fog_color[1] * 255.0) * factor;
    const fb = fog_color[2] * 255.0 + (b - fog_color[2] * 255.0) * factor;
    return .{ fr, fg, fb };
}
