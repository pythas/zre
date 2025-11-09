const std = @import("std");
const zmesh = @import("zmesh");

pub const AnimationChannel = struct {
    target_node: u32,
    path: AnimationPath,
    sampler_idx: u32,
};

pub const AnimationPath = enum {
    translation,
    rotation,
    scale,
};

pub const AnimationSampler = struct {
    input_times: []f32,
    output_data: []f32,
    interpolation: Interpolation,
};

pub const Interpolation = enum {
    linear,
    step,
    cubic_spline,
};

pub const Animation = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    channels: []AnimationChannel,
    samplers: []AnimationSampler,
    duration: f32,

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        for (self.samplers) |*sampler| {
            self.allocator.free(sampler.input_times);
            self.allocator.free(sampler.output_data);
        }
        self.allocator.free(self.samplers);
        self.allocator.free(self.channels);
    }

    pub fn sample(self: *const Self, time: f32, node_idx: u32, path: AnimationPath, output: []f32) bool {
        for (self.channels) |channel| {
            if (channel.target_node == node_idx and channel.path == path) {
                const sampler = self.samplers[channel.sampler_idx];
                sampleKeyframes(sampler, time, output);

                return true;
            }
        }

        return false;
    }

    fn sampleKeyframes(sampler: AnimationSampler, time: f32, output: []f32) void {
        const times = sampler.input_times;
        const values = sampler.output_data;

        const t = std.math.clamp(time, times[0], times[times.len - 1]);

        var idx: usize = 0;
        while (idx < times.len - 1 and times[idx + 1] < t) {
            idx += 1;
        }

        if (idx >= times.len - 1) {
            const components = output.len;
            const start = idx * components;
            @memcpy(output, values[start .. start + components]);
            return;
        }

        const t0 = times[idx];
        const t1 = times[idx + 1];
        const alpha = (t - t0) / (t1 - t0);

        const components = output.len;
        const start0 = idx * components;
        const start1 = (idx + 1) * components;

        switch (sampler.interpolation) {
            .linear => {
                for (0..components) |i| {
                    output[i] = std.math.lerp(values[start0 + i], values[start1 + i], alpha);
                }
            },
            .step => {
                @memcpy(output, values[start0 .. start0 + components]);
            },
            .cubic_spline => {
                for (0..components) |i| {
                    output[i] = std.math.lerp(values[start0 + i], values[start1 + i], alpha);
                }
            },
        }
    }
};

pub const AnimationState = struct {
    current_animation: ?*const Animation,
    current_time: f32,
    playback_speed: f32,
    looping: bool,
    is_playing: bool,

    pub fn init() AnimationState {
        return .{
            .current_animation = null,
            .current_time = 0.0,
            .playback_speed = 1.0,
            .looping = true,
            .is_playing = false,
        };
    }

    pub fn play(self: *AnimationState, animation: *const Animation, loop: bool) void {
        self.current_animation = animation;
        self.current_time = 0.0;
        self.looping = loop;
        self.is_playing = true;
    }

    pub fn stop(self: *AnimationState) void {
        self.is_playing = false;
        self.current_time = 0.0;
    }

    pub fn update(self: *AnimationState, dt: f32) void {
        if (!self.is_playing or self.current_animation == null) {
            return;
        }

        const anim = self.current_animation.?;
        self.current_time += dt * self.playback_speed;

        if (self.current_time >= anim.duration) {
            if (self.looping) {
                self.current_time = @mod(self.current_time, anim.duration);
            } else {
                self.current_time = anim.duration;
                self.is_playing = false;
            }
        }
    }
};

pub fn loadAnimationsFromGltf(
    allocator: std.mem.Allocator,
    data: *const zmesh.io.zcgltf.Data,
) ![]Animation {
    const anim_count = data.animations_count;
    if (anim_count == 0) {
        return &[_]Animation{};
    }

    var animations = try allocator.alloc(Animation, anim_count);
    errdefer allocator.free(animations);

    for (0..anim_count) |i| {
        const gltf_anim = data.animations.?[i];

        const sampler_count = gltf_anim.samplers_count;
        var samplers = try allocator.alloc(AnimationSampler, sampler_count);
        errdefer allocator.free(samplers);

        var max_time: f32 = 0.0;

        for (0..sampler_count) |j| {
            const gltf_sampler = gltf_anim.samplers[j];

            const input_accessor = gltf_sampler.input.*;
            const input_count = input_accessor.count;
            var input_times = try allocator.alloc(f32, input_count);
            errdefer allocator.free(input_times);

            const input_buffer_view = input_accessor.buffer_view.?.*;
            const input_data_ptr = @as([*]const u8, @ptrCast(input_buffer_view.buffer.data)) +
                input_accessor.offset + input_buffer_view.offset;
            const input_floats = @as([*]const f32, @ptrCast(@alignCast(input_data_ptr)));

            for (0..input_count) |k| {
                input_times[k] = input_floats[k];
                max_time = @max(max_time, input_times[k]);
            }

            const output_accessor = gltf_sampler.output.*;
            const output_count = output_accessor.count;
            const component_count: usize = switch (output_accessor.type) {
                .scalar => 1,
                .vec2 => 2,
                .vec3 => 3,
                .vec4 => 4,
                else => 1,
            };
            const total_floats = output_count * component_count;

            var output_data = try allocator.alloc(f32, total_floats);
            errdefer allocator.free(output_data);

            const output_buffer_view = output_accessor.buffer_view.?.*;
            const output_data_ptr = @as([*]const u8, @ptrCast(output_buffer_view.buffer.data)) +
                output_accessor.offset + output_buffer_view.offset;
            const output_floats = @as([*]const f32, @ptrCast(@alignCast(output_data_ptr)));

            for (0..total_floats) |k| {
                output_data[k] = output_floats[k];
            }

            const interp = switch (gltf_sampler.interpolation) {
                .linear => Interpolation.linear,
                .step => Interpolation.step,
                .cubic_spline => Interpolation.cubic_spline,
            };

            samplers[j] = AnimationSampler{
                .input_times = input_times,
                .output_data = output_data,
                .interpolation = interp,
            };
        }

        const channel_count = gltf_anim.channels_count;
        var channels = try allocator.alloc(AnimationChannel, channel_count);
        errdefer allocator.free(channels);

        for (0..channel_count) |j| {
            const gltf_channel = gltf_anim.channels[j];
            const target = gltf_channel.target_node.?;

            const node_idx = @intFromPtr(target) - @intFromPtr(data.nodes.?);
            const node_idx_normalized = node_idx / @sizeOf(zmesh.io.zcgltf.Node);

            const path = switch (gltf_channel.target_path) {
                .translation => AnimationPath.translation,
                .rotation => AnimationPath.rotation,
                .scale => AnimationPath.scale,
                else => AnimationPath.translation,
            };

            channels[j] = AnimationChannel{
                .target_node = @intCast(node_idx_normalized),
                .sampler_idx = @intCast(gltf_channel.sampler - gltf_anim.samplers),
                .path = path,
            };
        }

        const name = if (gltf_anim.name) |n|
            try allocator.dupe(u8, std.mem.span(n))
        else
            try std.fmt.allocPrint(allocator, "Animation_{d}", .{i});

        animations[i] = Animation{
            .allocator = allocator,
            .name = name,
            .channels = channels,
            .samplers = samplers,
            .duration = max_time,
        };
    }

    return animations;
}
