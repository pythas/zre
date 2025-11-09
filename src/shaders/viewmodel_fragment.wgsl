struct Uniforms {
    dt: f32,
    t: f32,
};

@group(0) @binding(0) var<uniform> U: Uniforms;
@group(0) @binding(1) var u_texture: texture_2d<u32>;
@group(0) @binding(2) var u_sampler: sampler;

@fragment
fn main(
    @location(0) world_pos: vec3<f32>,
    @location(1) normal: vec3<f32>
) -> @location(0) vec4<f32> {
    // Simple lighting based on normal
    let light_dir = normalize(vec3<f32>(0.5, 1.0, 0.3));
    let n = normalize(normal);
    let diffuse = max(dot(n, light_dir), 0.0);
    
    // Base color with lighting
    let base_color = vec3<f32>(0.7, 0.7, 0.8);
    let ambient = 0.3;
    let color = base_color * (ambient + diffuse * 0.7);
    
    return vec4<f32>(color, 1.0);
}
