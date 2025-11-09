struct Uniforms {
    transform_translate: vec4<f32>, // xyz = translation, w unused
    transform_rotate: vec4<f32>,    // xyzw = quaternion rotation
    dt: f32,
    t: f32,
    _pad0: f32,
    _pad1: f32,
};

@group(0) @binding(0) var<uniform> U: Uniforms;

struct VSOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) world_pos: vec3<f32>,
    @location(1) normal: vec3<f32>,
}

fn quat_rotate(q: vec4<f32>, v: vec3<f32>) -> vec3<f32> {
    let qvec = q.xyz;
    let uv = cross(qvec, v);
    let uuv = cross(qvec, uv);
    return v + ((uv * q.w) + uuv) * 2.0;
}

@vertex
fn main(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>
) -> VSOut {
    let animated_pos = quat_rotate(U.transform_rotate, position) + U.transform_translate.xyz;
    let animated_normal = quat_rotate(U.transform_rotate, normal);
    let scale = 0.15;
    let scaled_pos = animated_pos * scale;
    
    let screen_x = 0.7;
    let screen_y = -0.6;
    let screen_z = 0.0;
    
    let final_pos = vec3<f32>(
        scaled_pos.x + screen_x,
        scaled_pos.y + screen_y,
        screen_z
    );
    
    var o: VSOut;
    o.pos = vec4<f32>(final_pos, 1.0);
    o.world_pos = animated_pos;
    o.normal = animated_normal;
    return o;
}
