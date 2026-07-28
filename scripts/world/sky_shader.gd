class_name SkyShader
extends RefCounted
## The sky itself: a gradient with real drifting cloud layers, a sun disc and
## stars, all evaluated procedurally.
##
## Godot's ProceduralSkyMaterial cannot draw clouds, and a cloudless sky is
## most of why an outdoor scene reads as a toy. This costs one pass over the
## sky pixels and Godot caches the radiance map from it, so the clouds also
## tint the ambient light on the ground.

static func build() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.74);
uniform vec3 horizon_color : source_color = vec3(0.74, 0.83, 0.88);
uniform vec3 ground_color : source_color = vec3(0.36, 0.38, 0.34);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.92, 0.80);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.94);
uniform vec3 cloud_shadow : source_color = vec3(0.42, 0.45, 0.52);

uniform float cloud_cover = 0.35;
uniform float cloud_sharpness = 2.2;
uniform float haze = 0.35;
uniform float star_amount = 0.0;
uniform float sun_disc = 1.0;
uniform float wind_offset = 0.0;
uniform float exposure = 1.0;

// --- value noise -------------------------------------------------------
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	// --- base gradient -------------------------------------------------
	float t = clamp(up, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(t, 0.55));
	// Haze thickens the band just above the horizon.
	col = mix(col, horizon_color, haze * pow(1.0 - t, 3.0));
	if (up < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-up * 4.0, 0.0, 1.0));
	}

	// --- stars ---------------------------------------------------------
	if (star_amount > 0.001 && up > 0.0) {
		vec2 sp = dir.xz / max(abs(dir.y) + 0.12, 0.001) * 6.0;
		float star = hash21(floor(sp * 40.0));
		float bright = smoothstep(0.9975, 1.0, star);
		col += vec3(bright) * star_amount * (0.6 + 0.4 * sin(TIME * 2.0 + star * 90.0));
	}

	// --- sun -----------------------------------------------------------
	if (LIGHT0_ENABLED) {
		float d = dot(dir, LIGHT0_DIRECTION);
		// Disc plus a broad glow that sells low sun through haze.
		float disc = smoothstep(0.9994, 0.99975, d) * sun_disc;
		float glow = pow(max(d, 0.0), 48.0) * 0.5 + pow(max(d, 0.0), 8.0) * 0.12;
		col += LIGHT0_COLOR * (disc * 12.0 + glow) * sun_tint;
	}

	// --- clouds --------------------------------------------------------
	if (up > 0.002) {
		// Project onto a flat sheet overhead, so clouds compress at the horizon.
		vec2 uv = dir.xz / max(up, 0.02) * 0.34;
		uv += vec2(wind_offset, wind_offset * 0.6);

		float base = fbm(uv * 0.9);
		float detail = fbm(uv * 3.1 + vec2(base * 0.6));
		float density = base * 0.75 + detail * 0.25;

		// cloud_cover drives how much of the noise survives the threshold.
		float threshold = mix(0.64, 0.08, clamp(cloud_cover, 0.0, 1.0));
		float mask = smoothstep(threshold, threshold + 0.30 / cloud_sharpness, density);
		// Fade the sheet out toward the horizon so it never shows a hard edge.
		mask *= smoothstep(0.0, 0.16, up);

		// Fake lighting: the side of a cloud toward the sun is bright.
		float lit = 0.5;
		if (LIGHT0_ENABLED) {
			float toward = clamp(dot(normalize(dir), LIGHT0_DIRECTION) * 0.5 + 0.5, 0.0, 1.0);
			lit = mix(0.25, 1.0, toward);
		}
		// Thicker cloud is darker underneath.
		float thickness = smoothstep(threshold, 1.0, density);
		vec3 cloud = mix(cloud_shadow, cloud_lit, lit * (1.0 - thickness * 0.45));
		if (LIGHT0_ENABLED) {
			cloud *= 0.35 + 0.65 * clamp(LIGHT0_COLOR.r + LIGHT0_COLOR.g, 0.0, 1.0);
		}
		col = mix(col, cloud, clamp(mask, 0.0, 1.0));
	}

	COLOR = col * exposure;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
