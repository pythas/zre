const TILE_SIZE_F : f32 = 64.0;
const TILE_SIZE_I : i32 = 64;
const TILE_MASK_I : i32 = TILE_SIZE_I - 1;

const PLAYER_HEIGHT      : f32 = 0.9;
const LIGHT_HEIGHT_BIAS  : f32 = 0.5;
const DIFFUSE_WALL_SCALE : f32 = 0.9;
const AMBIENT_PLANE      : f32 = 0.22;
const EPS_DIST           : f32 = 1e-4;
const EPS_DOT            : f32 = 1e-8;

struct Light {
    kind: u32,
    flags: u32,
    _pad0: u32,
    _pad1: u32,
    pos_dir: vec4<f32>,
    color_I: vec4<f32>,
    atten: vec4<f32>,
};

struct LightBuffer {
    count: u32,
    _pad0: u32,
    _pad1: u32,
    _pad2: u32,
    lights: array<Light, 8>,
};

struct Uniforms {
    screen_wh: vec4<f32>,
    player_pos: vec4<f32>,
    player_dir: vec4<f32>,
    camera_plane: vec4<f32>,
    map_size: vec4<f32>,
    fog_enabled: vec4<f32>,
    fog_color: vec4<f32>,
    fog_density: vec4<f32>,
    ceiling_tex: u32,
    floor_tex: u32,
    _pad0: u32,
    _pad1: u32,
};

struct Tile {
    kind: u32,
    texture: u32,
};

@group(0) @binding(0) var<uniform> U: Uniforms;
@group(0) @binding(1) var u_tilemap: texture_2d<u32>;
@group(0) @binding(2) var u_atlas: texture_2d_array<f32>;
@group(0) @binding(3) var u_sampler: sampler;
@group(0) @binding(4) var<storage, read> u_lights: LightBuffer;

struct RaycastResult {
    hit_id: Tile,
    map_pos: vec2<f32>,
    ray_dir: vec2<f32>,
    step: vec2<f32>,
    side: i32,
    perp_dist: f32,
};

struct WallData {
    u: f32,
    n: vec2<f32>,
};

fn fetch_tile(x: i32, y: i32) -> Tile {
    let gx = clamp(x, 0, i32(U.map_size.x) - 1);
    let gy = clamp(y, 0, i32(U.map_size.y) - 1);
    let byte = textureLoad(u_tilemap, vec2<i32>(gx, gy), 0).r;
    let kind = (byte >> 4u) & 0xFu;
    let texture = byte & 0xFu;

    return Tile(kind, texture);
}

fn sample_atlas(layer: i32, uv: vec2<f32>) -> vec4<f32> {
    let u = (floor(uv.x * TILE_SIZE_F) + 0.5) / TILE_SIZE_F;
    let v = (floor(uv.y * TILE_SIZE_F) + 0.5) / TILE_SIZE_F;

    return textureSampleLevel(u_atlas, u_sampler, vec2<f32>(u, v), layer, 0.0);
}

fn evaluate_plane_light(
    acc: vec4<f32>,
    light: Light,
    world_xy: vec2<f32>,
    world_z: f32,
    normal_sign: f32,
) -> vec4<f32> {
    if (light.flags & 0x1u) == 0u {
        return acc;
    }

    var out_acc = acc;

    if (light.kind & 0x1u) == 0u {
        let d = vec3<f32>(
            light.pos_dir.x - world_xy.x,
            light.pos_dir.y - world_xy.y,
            PLAYER_HEIGHT - world_z - LIGHT_HEIGHT_BIAS
        );
        let d2 = max(dot(d, d), EPS_DOT);
        let dist = sqrt(d2);
        let L = d / dist;

        let lambert = max(0.0, normal_sign * L.z);
        if lambert == 0.0 { return out_acc; }

        var atten: f32;
        if light.atten.x < 0.5 {
            atten = 1.0 / (1.0 + light.atten.y * dist + light.atten.z * d2);
        } else {
            atten = select(0.0, 1.0, dist <= light.atten.w);
        }

        let scale = light.color_I.w * lambert * atten * DIFFUSE_WALL_SCALE;
        out_acc += vec4<f32>(light.color_I.xyz, 1.0) * scale;
    } else {
        let dir = normalize(light.pos_dir.xyz);
        let lambert = max(0.0, normal_sign * (-dir.z));
        if lambert == 0.0 { return out_acc; }
        let scale = light.color_I.w * lambert * DIFFUSE_WALL_SCALE;
        out_acc += vec4<f32>(light.color_I.xyz, 1.0) * scale;
    }

    return out_acc;
}

fn accumulate_plane_lights(world_xy: vec2<f32>, world_z: f32, normal_sign: f32) -> vec4<f32> {
    var acc = vec4<f32>(0.0);
    for (var i = 0u; i < u_lights.count; i++) {
        acc = evaluate_plane_light(acc, u_lights.lights[i], world_xy, world_z, normal_sign);
    }

    return acc;
}

fn plane_color(x_px: f32, row_i: i32, layer: i32) -> vec4<f32> {
    let screen_w = U.screen_wh.x;
    let screen_h = U.screen_wh.y;
    let half_h = 0.5 * screen_h;
    let pos_y_i = row_i - i32(half_h);
    if pos_y_i == 0 {
        return vec4<f32>(0.0);
    }

    let ray0 = U.player_dir.xy - U.camera_plane.xy;
    let ray1 = U.player_dir.xy + U.camera_plane.xy;
    let pos_z = half_h;
    let row_d = pos_z / abs(f32(pos_y_i));
    let step = (ray1 - ray0) * (row_d / screen_w);
    let p = U.player_pos.xy + ray0 * row_d + step * x_px;

    let world_z = select(0.0, 1.0, layer == 1);
    let normal_sign = select(1.0, -1.0, layer == 1);

    let u = (floor(fract(p.x) * TILE_SIZE_F) + 0.5) / TILE_SIZE_F;
    let v = (floor(fract(p.y) * TILE_SIZE_F) + 0.5) / TILE_SIZE_F;
    var tex = textureSampleLevel(u_atlas, u_sampler, vec2<f32>(u, v), layer, 0.0);

    let ambient_color = vec4<f32>(0.10, 0.10, 0.12, 1.0);
    let base_ambient = ambient_color * AMBIENT_PLANE;
    let plane_light = accumulate_plane_lights(p, world_z, normal_sign) + base_ambient;

    var lit = tex * plane_light;

    let fog_on = U.fog_enabled.x > 0.0;
    let fog_factor = clamp(exp(-U.fog_density.x * row_d * 0.5), 0.0, 1.0);
    let fogged = mix(U.fog_color.rgb, lit.rgb, fog_factor);
    let rgb = select(lit.rgb, fogged, fog_on);

    return vec4<f32>(rgb, tex.a);
}

fn evaluate_light(acc: vec4<f32>, light: Light, hit_point: vec2<f32>, n: vec2<f32>) -> vec4<f32> {
    if (light.flags & 0x1u) == 0u {
        return acc;
    }

    var out_acc = acc;

    if (light.kind & 0x1u) == 0u {
        let d = vec3<f32>(
            light.pos_dir.x - hit_point.x,
            light.pos_dir.y - hit_point.y,
            PLAYER_HEIGHT - LIGHT_HEIGHT_BIAS
        );
        let d2 = max(dot(d, d), EPS_DOT);
        let dist = sqrt(d2);
        let L = d / dist;

        let lambert = max(0.0, dot(n, L.xy));
        if lambert == 0.0 { return out_acc; }

        var atten: f32;
        if light.atten.x < 0.5 {
            atten = 1.0 / (1.0 + light.atten.y * dist + light.atten.z * d2);
        } else {
            atten = select(0.0, 1.0, dist <= light.atten.w);
        }

        let scale = light.color_I.w * lambert * atten * DIFFUSE_WALL_SCALE;
        out_acc += vec4<f32>(light.color_I.xyz, 1.0) * scale;
    } else {
        let dir = normalize(light.pos_dir.xyz);
        let lambert = max(0.0, dot(n, -dir.xy));
        if lambert == 0.0 { return out_acc; }
        let scale = light.color_I.w * lambert * DIFFUSE_WALL_SCALE;
        out_acc += vec4<f32>(light.color_I.xyz, 1.0) * scale;
    }

    return out_acc;
}

fn accumulate_wall_lights(hit_point: vec2<f32>, n: vec2<f32>) -> vec4<f32> {
    var acc = vec4<f32>(0.0);
    for (var i = 0u; i < u_lights.count; i++) {
        acc = evaluate_light(acc, u_lights.lights[i], hit_point, n);
    }

    return acc;
}

fn raycast(uv_x: f32) -> RaycastResult {
    let camera_x = 2.0 * uv_x - 1.0;
    let ray_dir = U.player_dir.xy + U.camera_plane.xy * camera_x;

    var map_pos = floor(U.player_pos.xy);

    let delta = vec2<f32>(
        select(abs(1.0 / ray_dir.x), 1e30, ray_dir.x == 0.0),
        select(abs(1.0 / ray_dir.y), 1e30, ray_dir.y == 0.0)
    );

    var step = vec2<f32>(0.0);
    var side_dist = vec2<f32>(0.0);

    if ray_dir.x < 0.0 {
        step.x = -1.0;
        side_dist.x = (U.player_pos.x - map_pos.x) * delta.x;
    } else {
        step.x = 1.0;
        side_dist.x = (map_pos.x + 1.0 - U.player_pos.x) * delta.x;
    }

    if ray_dir.y < 0.0 {
        step.y = -1.0;
        side_dist.y = (U.player_pos.y - map_pos.y) * delta.y;
    } else {
        step.y = 1.0;
        side_dist.y = (map_pos.y + 1.0 - U.player_pos.y) * delta.y;
    }

    var side: i32 = 0;
    var hit: Tile = Tile(0u, 0u);
    for (var i = 0; i < 1024; i++) {
        if side_dist.x < side_dist.y {
            side_dist.x += delta.x;
            map_pos.x += step.x;
            side = 0;
        } else {
            side_dist.y += delta.y;
            map_pos.y += step.y;
            side = 1;
        }

        hit = fetch_tile(i32(map_pos.x), i32(map_pos.y));

        if hit.kind != 0u {
          break;
        }
    }

    var perp = 0.0;
    if side == 0 {
        perp = (map_pos.x - U.player_pos.x + (1.0 - step.x) * 0.5) / ray_dir.x;
    } else {
        perp = (map_pos.y - U.player_pos.y + (1.0 - step.y) * 0.5) / ray_dir.y;
    }

    return RaycastResult(hit, map_pos, ray_dir, step, side, perp);
}

fn wall_uv_normal(side: i32, ray_dir: vec2<f32>, step: vec2<f32>, perp_dist: f32) -> WallData {
    var wall_x: f32;
    if side == 0 {
        wall_x = U.player_pos.y + perp_dist * ray_dir.y;
    } else {
        wall_x = U.player_pos.x + perp_dist * ray_dir.x;
    }
    wall_x = fract(wall_x);

    var u = wall_x;
    if (side == 0 && ray_dir.x > 0.0) || (side == 1 && ray_dir.y < 0.0) {
        u = 1.0 - u;
    }

    var n: vec2<f32>;
    if side == 0 { n = vec2<f32>(-step.x, 0.0); } else { n = vec2<f32>(0.0, -step.y); }

    return WallData(u, n);
}

@fragment
fn main(
    @location(0) uv: vec2<f32>,
    @builtin(position) frag_pos: vec4<f32>,
) -> @location(0) vec4<f32> {
    let screen_h = U.screen_wh.y;
    let screen_h_i = i32(screen_h);
    let half_h = 0.5 * screen_h;

    let rc = raycast(uv.x);
    if rc.hit_id.kind == 0u {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let perp = max(rc.perp_dist, EPS_DIST);
    let line_h = max(1.0, screen_h / perp);
    let half_l = 0.5 * line_h;

    var draw_start = max(0, i32(-half_l + half_h));
    var draw_end = min(screen_h_i - 1, i32(half_l + half_h));

    let row = i32(frag_pos.y);

    if row < draw_start {
        return plane_color(frag_pos.x, row, i32(U.ceiling_tex));
    }

    if row > draw_end {
        return plane_color(frag_pos.x, row, i32(U.floor_tex));
    }

    let wd = wall_uv_normal(rc.side, rc.ray_dir, rc.step, perp);

    let step_y = TILE_SIZE_F / line_h;
    let base = (f32(draw_start) - (half_h - 0.5 * line_h)) * step_y;
    let texpos_at_row = base + (f32(row - draw_start)) * step_y;
    let texture_y = i32(floor(texpos_at_row)) & TILE_MASK_I;
    let v = (f32(texture_y) + 0.5) / TILE_SIZE_F;

    let ambient_color = vec4<f32>(0.10, 0.10, 0.12, 1.0);
    let base_ambient = ambient_color * AMBIENT_PLANE;
    let hit_point = U.player_pos.xy + rc.ray_dir * rc.perp_dist;
    let wall_light = accumulate_wall_lights(hit_point, wd.n) + base_ambient;

    let wall_color = textureSampleLevel(
        u_atlas, u_sampler, vec2<f32>(wd.u, v), i32(rc.hit_id.texture), 0.0
    ) * wall_light;

    let fog_on = U.fog_enabled.x > 0.0;
    let fog_factor = clamp(exp(-U.fog_density.x * perp * 0.5), 0.0, 1.0);
    let fogged = mix(U.fog_color.rgb, wall_color.rgb, fog_factor);
    let rgb = select(wall_color.rgb, fogged, fog_on);

    return vec4<f32>(rgb, 1.0);
}
