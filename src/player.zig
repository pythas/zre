const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const AttackType = @import("viewmodel.zig").AttackType;

pub const MoveAnimation = struct {
    start_pos: Vec2,
    target_pos: Vec2,
    progress: f32,
    duration: f32,

    pub fn isActive(self: MoveAnimation) bool {
        return self.progress < self.duration;
    }

    pub fn getCurrentPos(self: MoveAnimation) Vec2 {
        const t = @min(self.progress / self.duration, 1.0);
        return self.start_pos.lerp(self.target_pos, t);
    }
};

pub const TurnAnimation = struct {
    start_dir: Vec2,
    target_dir: Vec2,
    start_plane: Vec2,
    target_plane: Vec2,
    progress: f32,
    duration: f32,

    pub fn isActive(self: TurnAnimation) bool {
        return self.progress < self.duration;
    }

    pub fn getCurrentDir(self: TurnAnimation) Vec2 {
        const t = @min(self.progress / self.duration, 1.0);
        return self.start_dir.lerp(self.target_dir, t).normalize();
    }

    pub fn getCurrentPlane(self: TurnAnimation) Vec2 {
        const t = @min(self.progress / self.duration, 1.0);
        return self.start_plane.lerp(self.target_plane, t);
    }
};

pub const AttackAnimation = struct {
    const Self = @This();

    attack_type: AttackType,
    progress: f32,
    duration: f32,
    hit_registered: bool,

    pub fn isActive(self: Self) bool {
        return self.progress < self.duration;
    }

    pub fn getProgress(self: Self) f32 {
        return @min(self.progress / self.duration, 1.0);
    }
};

pub const Player = struct {
    const Self = @This();

    pub const move_duration: f32 = 0.15;
    pub const turn_duration: f32 = 0.08;
    pub const attack_duration: f32 = 1.0;

    position: Vec2,
    direction: Vec2,
    move_anim: ?MoveAnimation,
    turn_anim: ?TurnAnimation,
    attack_anim: ?AttackAnimation,

    pub fn init(position: Vec2, direction: Vec2) !Self {
        return .{
            .position = position,
            .direction = direction,
            .move_anim = null,
            .turn_anim = null,
            .attack_anim = null,
        };
    }

    pub fn isAnimating(self: Self) bool {
        return (self.move_anim != null and self.move_anim.?.isActive()) or
            (self.turn_anim != null and self.turn_anim.?.isActive());
    }

    pub fn update(self: *Self, dt: f32, plane: *Vec2) void {
        if (self.move_anim) |*anim| {
            anim.progress += dt;
            self.position = anim.getCurrentPos();

            if (!anim.isActive()) {
                self.position = anim.target_pos;
                self.move_anim = null;
            }
        }

        if (self.turn_anim) |*anim| {
            anim.progress += dt;
            self.direction = anim.getCurrentDir();
            plane.* = anim.getCurrentPlane();

            if (!anim.isActive()) {
                self.direction = anim.target_dir.normalize();
                plane.* = anim.target_plane;
                self.turn_anim = null;
            }
        }

        self.updateCombat(dt);
    }

    pub fn updateCombat(self: *Self, dt: f32) void {
        if (self.attack_anim) |*anim| {
            anim.progress += dt;

            if (!anim.isActive()) {
                self.attack_anim = null;
            }
        }

        // TODO: Stamina regeneration
    }

    pub fn startMove(self: *Self, target_pos: Vec2) void {
        self.move_anim = MoveAnimation{
            .start_pos = self.position,
            .target_pos = target_pos,
            .progress = 0.0,
            .duration = move_duration,
        };
    }

    pub fn startTurn(self: *Self, angle_rad: f32, plane: Vec2) void {
        const target_dir = self.direction.rotated(angle_rad);
        const target_plane = plane.rotated(angle_rad);

        self.turn_anim = TurnAnimation{
            .start_dir = self.direction,
            .target_dir = target_dir,
            .start_plane = plane,
            .target_plane = target_plane,
            .progress = 0.0,
            .duration = turn_duration,
        };
    }

    pub fn startAttack(self: *Self, attack_type: AttackType) void {
        // TODO: Stamina check

        self.attack_anim = .{
            .attack_type = attack_type,
            .progress = 0.0,
            .duration = attack_duration, // TODO: Calculate this dynamically
            .hit_registered = false,
        };
    }
};
