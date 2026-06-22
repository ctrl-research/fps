extends Node3D
class_name DayNightSky
"""
Procedural sky + sun with a day→sunset→night cycle.

Builds a WorldEnvironment whose sky is a procedural shader (gradient + sun disk +
animated fbm clouds) and a DirectionalLight sun. apply(progress) advances the
time of day: 0.0 = day, 0.5 = sunset (sun at the horizon, warm sky), 1.0 = night
(sun below the horizon, dark sky, dim clouds). Modes call apply() each round with
their match progress.

Reusable: add as a child of a scene and call apply() (defaults to day at _ready).
"""

const SKY_SHADER: String = """
shader_type sky;

uniform float day_factor = 1.0;     // 1 = day, 0 = night
uniform float sunset_factor = 0.0;  // peaks at the sunset midpoint

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void sky() {
	float up = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 day_top = vec3(0.20, 0.42, 0.82);
	vec3 day_hor = vec3(0.70, 0.80, 0.95);
	vec3 night_top = vec3(0.01, 0.02, 0.06);
	vec3 night_hor = vec3(0.04, 0.06, 0.13);
	vec3 sunset = vec3(0.95, 0.45, 0.20);

	vec3 top = mix(night_top, day_top, day_factor);
	vec3 hor = mix(night_hor, day_hor, day_factor);
	hor = mix(hor, sunset, sunset_factor * (1.0 - up));
	vec3 col = mix(hor, top, pow(up, 0.5));

	// Sun disk + glow (the scene's DirectionalLight).
	if (LIGHT0_ENABLED) {
		float sd = dot(normalize(EYEDIR), -normalize(LIGHT0_DIRECTION));
		col += LIGHT0_COLOR * smoothstep(0.9990, 0.9997, sd) * 6.0;
		col += LIGHT0_COLOR * pow(max(sd, 0.0), 48.0) * 0.4 * day_factor;
	}

	// Drifting fbm clouds above the horizon.
	if (EYEDIR.y > 0.02) {
		vec2 uv = EYEDIR.xz / (EYEDIR.y + 0.2) * 1.2 + TIME * 0.006;
		float c = smoothstep(0.45, 0.85, fbm(uv)) * smoothstep(0.02, 0.25, EYEDIR.y);
		vec3 cloud = mix(vec3(0.08, 0.09, 0.13), vec3(1.0), day_factor);
		cloud = mix(cloud, sunset, sunset_factor * 0.5);
		col = mix(col, cloud, c * 0.8);
	}

	COLOR = col;
}
"""

var _env: WorldEnvironment = null
var _sky_mat: ShaderMaterial = null

func _ready() -> void:
	_sky_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SKY_SHADER
	_sky_mat.shader = shader

	var sky := Sky.new()
	sky.sky_material = _sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Lighting comes from the player's POV light, not the sky. Keep only a low
	# ambient floor so distant geometry stays a faintly-visible silhouette.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.6)
	env.ambient_light_energy = 0.15
	_env = WorldEnvironment.new()
	_env.environment = env
	add_child(_env)

	apply(0.0)

## Set the time of day from match progress (0 day → 0.5 sunset → 1 night). Only
## the sky backdrop colour changes now — the world is lit by the POV light.
func apply(progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	var day := clampf(1.0 - progress, 0.05, 1.0)
	var sunset := clampf(1.0 - absf(progress - 0.5) * 2.0, 0.0, 1.0)
	_sky_mat.set_shader_parameter("day_factor", day)
	_sky_mat.set_shader_parameter("sunset_factor", sunset)
