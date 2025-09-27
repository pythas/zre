const Vec3 = @import("vec3.zig").Vec3;

pub const Light = union(enum) {
    point: PointLight,
    directional: DirectionalLight,

    pub const PointLight = struct {
        const Self = @This();

        position: Vec3,
        color: [3]f32,
        intensity: f32,
        attenuation: Attenuation,
        casts_shadows: bool,
        enabled: bool,

        pub fn init(
            position: Vec3,
            color: [3]f32,
            intensity: f32,
            attenuation: Attenuation,
            casts_shadows: bool,
            enabled: bool,
        ) Self {
            return .{
                .position = position,
                .color = color,
                .intensity = intensity,
                .attenuation = attenuation,
                .casts_shadows = casts_shadows,
                .enabled = enabled,
            };
        }
    };

    pub const DirectionalLight = struct {
        const Self = @This();

        direction: Vec3,
        color: [3]f32,
        intensity: f32,
        casts_shadows: bool,
        enabled: bool,

        pub fn init(
            direction: Vec3,
            color: [3]f32,
            intensity: f32,
            casts_shadows: bool,
            enabled: bool,
        ) Self {
            return .{
                .direction = direction,
                .color = color,
                .intensity = intensity,
                .casts_shadows = casts_shadows,
                .enabled = enabled,
            };
        }
    };

    pub const Attenuation = union(enum) {
        quadratic: QuadraticAttenuation,
        radial: RadialAttenuation,
    };

    pub const QuadraticAttenuation = struct {
        linear: f32,
        quadratic: f32,
    };

    pub const RadialAttenuation = struct {
        radius: f32,
    };
};
