const Vec3 = @import("vec3.zig").Vec3;

pub const QuadraticAttenuation = struct {
    linear: f32,
    quadratic: f32,
};

pub const RadiusAttenuation = struct {
    radius: f32,
};

pub const PointLight = struct {
    const Self = @This();

    position: Vec3,
    color: [3]f32,
    intensity: f32,
    quadratic_attenuation: ?QuadraticAttenuation = null,
    radius_attenuation: ?RadiusAttenuation = null,
    cast_shadows: bool,
    enabled: bool,

    pub fn init(
        position: Vec3,
        color: [3]f32,
        intensity: f32,
        quadratic_attenuation: ?QuadraticAttenuation,
        radius_attenuation: ?RadiusAttenuation,
        casts_shadows: bool,
        enabled: bool,
    ) Self {
        return .{
            .position = position,
            .color = color,
            .intensity = intensity,
            .quadratic_attenuation = quadratic_attenuation,
            .radius_attenuation = radius_attenuation,
            .casts_shadows = casts_shadows,
            .enabled = enabled,
        };
    }
};
