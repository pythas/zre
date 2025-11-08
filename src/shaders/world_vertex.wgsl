struct VSOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn main(@builtin(vertex_index) vi: u32) -> VSOut {
    var pos = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -3.0),
        vec2<f32>(3.0, 1.0),
        vec2<f32>(-1.0, 1.0),
    );

    var o: VSOut;
    o.pos = vec4<f32>(pos[vi], 0.0, 1.0);
    o.uv = o.pos.xy * 0.5 + vec2<f32>(0.5, 0.5);
    return o;
}
