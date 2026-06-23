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
uniform float red_factor = 0.0;     // 0 = clear, 1 = fully red sky (late rounds)

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

	// Late-round redness: blend the whole sky toward a bright red.
	vec3 red_top = vec3(0.42, 0.04, 0.03);
	vec3 red_hor = vec3(0.88, 0.13, 0.06);
	vec3 red_col = mix(red_hor, red_top, pow(up, 0.6));
	col = mix(col, red_col, red_factor);

	COLOR = col;
}
"""

# Background colour while the dither effect is on, so PostProcess can detect sky
# pixels and draw a smooth (un-dithered) sky there. Must not occur on geometry.
const SENTINEL: Color = Color(1.0, 0.0, 1.0)

var _env: WorldEnvironment = null
var _sky_mat: ShaderMaterial = null
var _day: float = 1.0
var _sunset: float = 0.0
var _red: float = 0.0

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
	# Ambient gives base visibility for the whole scene; the POV light adds
	# contrast/shadow on top. Ambient energy is live-tunable from Settings.
	# Neutral ambient so surface colours read true (no blue wash) — the Mortal Sin
	# palette wants punchy, readable surface colour, not a tint.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.99, 0.96)
	_env = WorldEnvironment.new()
	_env.environment = env
	add_child(_env)

	_update_ambient()
	apply(0.0)
	_apply_background()
	Settings.settings_changed.connect(_update_ambient)
	Settings.settings_changed.connect(_apply_background)

func _exit_tree() -> void:
	PostProcess.clear_sky()

## Apply the live-tunable ambient (base visibility) from Settings.
func _update_ambient() -> void:
	if _env:
		_env.environment.ambient_light_energy = Settings.ambient_light

## With the dither effect on, clear the 3D background to a sentinel colour so
## PostProcess draws a smooth (un-dithered) sky there; with it off, show the real
## procedural sky.
func _apply_background() -> void:
	if _env == null:
		return
	if Settings.stylize_enabled:
		_env.environment.background_mode = Environment.BG_COLOR
		_env.environment.background_color = SENTINEL
		PostProcess.set_sky(_day, _sunset, _red)
	else:
		_env.environment.background_mode = Environment.BG_SKY
		PostProcess.clear_sky()

## Set the sky from match progress (time-of-day) and redness (0 clear → 1 fully
## red, ramped by round). The world is lit by the POV light; this is the backdrop.
func apply(progress: float, red: float = 0.0) -> void:
	progress = clampf(progress, 0.0, 1.0)
	_day = clampf(1.0 - progress, 0.05, 1.0)
	_sunset = clampf(1.0 - absf(progress - 0.5) * 2.0, 0.0, 1.0)
	_red = clampf(red, 0.0, 1.0)
	_sky_mat.set_shader_parameter("day_factor", _day)
	_sky_mat.set_shader_parameter("sunset_factor", _sunset)
	_sky_mat.set_shader_parameter("red_factor", _red)
	if Settings.stylize_enabled:
		PostProcess.set_sky(_day, _sunset, _red)
