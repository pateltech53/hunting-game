class_name Synth
extends RefCounted
## A tiny DSP kitchen. Every sound in Wildlight is generated here at runtime,
## so the repository ships no binary audio assets.
##
## Everything works on PackedFloat32Array buffers at [constant RATE] and is
## converted to a 16-bit AudioStreamWAV at the end.

const RATE := 22050

enum Wave { SINE, TRI, SAW, SQUARE, NOISE }


static func make_buffer(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(maxi(1, int(seconds * RATE)))
	buf.fill(0.0)
	return buf


static func to_stream(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := clampf(samples[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(v * 32000.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = n
	return stream


# ---------------------------------------------------------------- oscillators

static func osc(phase: float, wave: Wave, rng: RandomNumberGenerator = null) -> float:
	match wave:
		Wave.SINE:
			return sin(phase)
		Wave.TRI:
			var t := fposmod(phase / TAU, 1.0)
			return 4.0 * absf(t - 0.5) - 1.0
		Wave.SAW:
			return 2.0 * fposmod(phase / TAU, 1.0) - 1.0
		Wave.SQUARE:
			return 1.0 if fposmod(phase / TAU, 1.0) < 0.5 else -1.0
		_:
			return rng.randf_range(-1.0, 1.0) if rng != null else randf_range(-1.0, 1.0)


## Adds a tone with an independent frequency ramp and amplitude envelope.
static func add_tone(buf: PackedFloat32Array, start: float, dur: float, f0: float,
		f1: float, amp: float, wave: Wave = Wave.SINE, curve: float = 1.0) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var idx := i0 + i
		if idx < 0 or idx >= buf.size():
			continue
		var t := float(i) / float(maxi(n, 1))
		var f: float = lerpf(f0, f1, pow(t, curve))
		phase += TAU * f / float(RATE)
		buf[idx] += osc(phase, wave) * amp * _default_env(t)


static func _default_env(t: float) -> float:
	# Fast attack, exponential-ish decay. Good default for plucks and calls.
	var attack := clampf(t / 0.02, 0.0, 1.0)
	return attack * pow(1.0 - t, 1.6)


## ADSR in normalised time, useful when a call needs a sustained middle.
static func adsr(t: float, a: float, d: float, s: float, r: float) -> float:
	if t < a:
		return t / maxf(a, 0.0001)
	if t < a + d:
		return lerpf(1.0, s, (t - a) / maxf(d, 0.0001))
	if t < 1.0 - r:
		return s
	return s * clampf((1.0 - t) / maxf(r, 0.0001), 0.0, 1.0)


static func add_noise(buf: PackedFloat32Array, start: float, dur: float, amp: float,
		rng: RandomNumberGenerator, shape: float = 1.6) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	for i in n:
		var idx := i0 + i
		if idx < 0 or idx >= buf.size():
			continue
		var t := float(i) / float(maxi(n, 1))
		buf[idx] += rng.randf_range(-1.0, 1.0) * amp * pow(1.0 - t, shape)


# ------------------------------------------------------------------- filtering

static func lowpass(buf: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	var dt := 1.0 / float(RATE)
	var rc := 1.0 / (TAU * maxf(cutoff_hz, 1.0))
	var alpha := dt / (rc + dt)
	var y := 0.0
	for i in buf.size():
		y += alpha * (buf[i] - y)
		out[i] = y
	return out


static func highpass(buf: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	var dt := 1.0 / float(RATE)
	var rc := 1.0 / (TAU * maxf(cutoff_hz, 1.0))
	var alpha := rc / (rc + dt)
	var prev_x := 0.0
	var prev_y := 0.0
	for i in buf.size():
		var x := buf[i]
		prev_y = alpha * (prev_y + x - prev_x)
		prev_x = x
		out[i] = prev_y
	return out


## Sweeping one-pole lowpass - gives noise bursts their "whoosh".
static func lowpass_sweep(buf: PackedFloat32Array, from_hz: float, to_hz: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	var dt := 1.0 / float(RATE)
	var y := 0.0
	var n := maxi(buf.size(), 1)
	for i in buf.size():
		var cutoff: float = lerpf(from_hz, to_hz, float(i) / float(n))
		var rc := 1.0 / (TAU * maxf(cutoff, 1.0))
		var alpha := dt / (rc + dt)
		y += alpha * (buf[i] - y)
		out[i] = y
	return out


## Cheap Schroeder-ish reverb: three combs into one allpass.
static func reverb(buf: PackedFloat32Array, wet: float, decay: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i] * (1.0 - wet * 0.5)
	var comb_delays := [1621, 1949, 2311]
	var comb_gains := [decay, decay * 0.93, decay * 0.87]
	for c in comb_delays.size():
		var d: int = comb_delays[c]
		var g: float = comb_gains[c]
		var line := PackedFloat32Array()
		line.resize(d)
		line.fill(0.0)
		var p := 0
		for i in buf.size():
			var delayed := line[p]
			var v := buf[i] + delayed * g
			line[p] = v
			p = (p + 1) % d
			out[i] += delayed * wet * 0.34
	# Single allpass to smear the comb resonances.
	var ap_d := 347
	var ap_g := 0.6
	var ap := PackedFloat32Array()
	ap.resize(ap_d)
	ap.fill(0.0)
	var ap_p := 0
	for i in out.size():
		var delayed := ap[ap_p]
		var v := out[i] + delayed * -ap_g
		ap[ap_p] = v
		ap_p = (ap_p + 1) % ap_d
		out[i] = delayed + v * ap_g
	return out


static func normalize(buf: PackedFloat32Array, peak: float = 0.9) -> PackedFloat32Array:
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	if m < 0.00001:
		return buf
	var g := peak / m
	for i in buf.size():
		buf[i] *= g
	return buf


## Fades the very start and end so a one-shot never clicks.
static func deglitch(buf: PackedFloat32Array, ms: float = 4.0) -> PackedFloat32Array:
	var n := maxi(1, int(ms * 0.001 * RATE))
	var size := buf.size()
	for i in mini(n, size):
		var g := float(i) / float(n)
		buf[i] *= g
		buf[size - 1 - i] *= g
	return buf


## Crossfades the loop seam so a sustained bed loops without a seam.
static func seamless(buf: PackedFloat32Array, fade_seconds: float = 0.35) -> PackedFloat32Array:
	var n := mini(int(fade_seconds * RATE), buf.size() / 3)
	if n <= 1:
		return buf
	var out := buf.duplicate()
	var size := buf.size()
	for i in n:
		var t := float(i) / float(n)
		out[i] = lerpf(buf[size - n + i], buf[i], t)
	out.resize(size - n)
	return out


# --------------------------------------------------------------- sound recipes

static func shutter(rng: RandomNumberGenerator, mirror: bool = true) -> AudioStreamWAV:
	var buf := make_buffer(0.30)
	# First curtain: bright mechanical click.
	add_noise(buf, 0.0, 0.035, 0.9, rng, 3.0)
	add_tone(buf, 0.0, 0.05, 1800.0, 420.0, 0.35, Wave.TRI)
	if mirror:
		# Mirror slap and its return.
		add_noise(buf, 0.012, 0.06, 0.55, rng, 2.2)
		add_tone(buf, 0.012, 0.09, 260.0, 120.0, 0.5, Wave.SINE)
	# Second curtain closing.
	add_noise(buf, 0.10, 0.04, 0.6, rng, 3.2)
	add_tone(buf, 0.10, 0.06, 1400.0, 380.0, 0.28, Wave.TRI)
	var filtered := lowpass(buf, 6500.0)
	filtered = highpass(filtered, 160.0)
	return to_stream(deglitch(normalize(filtered, 0.85)))


static func focus_confirm(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(0.16)
	add_tone(buf, 0.0, 0.05, 1560.0, 1560.0, 0.35)
	add_tone(buf, 0.06, 0.07, 2340.0, 2340.0, 0.3)
	return to_stream(deglitch(normalize(buf, 0.5)))


static func lens_click(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(0.12)
	add_noise(buf, 0.0, 0.02, 0.7, rng, 4.0)
	add_tone(buf, 0.0, 0.04, 900.0, 300.0, 0.25, Wave.TRI)
	return to_stream(deglitch(normalize(lowpass(buf, 5000.0), 0.55)))


static func rifle_shot(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(1.9)
	# The crack.
	add_noise(buf, 0.0, 0.09, 1.0, rng, 2.4)
	# The body.
	add_tone(buf, 0.0, 0.28, 190.0, 52.0, 0.85, Wave.SINE, 0.5)
	add_tone(buf, 0.0, 0.18, 92.0, 38.0, 0.6, Wave.TRI, 0.6)
	# Rolling echo off the treeline.
	for i in 4:
		var delay := 0.16 + float(i) * 0.19 + rng.randf_range(-0.02, 0.02)
		add_noise(buf, delay, 0.22 + float(i) * 0.06, 0.30 / (1.0 + float(i)), rng, 1.4)
	var shaped := lowpass_sweep(buf, 9000.0, 700.0)
	shaped = highpass(shaped, 45.0)
	shaped = reverb(shaped, 0.35, 0.62)
	return to_stream(deglitch(normalize(shaped, 0.95)))


static func rifle_cycle(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(0.55)
	add_noise(buf, 0.0, 0.05, 0.5, rng, 3.0)
	add_tone(buf, 0.02, 0.10, 620.0, 240.0, 0.3, Wave.SQUARE)
	add_noise(buf, 0.20, 0.06, 0.45, rng, 2.6)
	add_tone(buf, 0.22, 0.12, 380.0, 150.0, 0.32, Wave.TRI)
	add_noise(buf, 0.38, 0.05, 0.55, rng, 3.4)
	return to_stream(deglitch(normalize(lowpass(buf, 5200.0), 0.6)))


static func footstep(rng: RandomNumberGenerator, surface: String) -> AudioStreamWAV:
	var buf := make_buffer(0.34)
	match surface:
		"grass":
			add_noise(buf, 0.0, 0.14, 0.55, rng, 2.6)
			add_tone(buf, 0.0, 0.07, 150.0, 70.0, 0.22, Wave.SINE)
			return to_stream(deglitch(normalize(lowpass_sweep(buf, 4200.0, 900.0), 0.42)))
		"gravel":
			for i in 5:
				add_noise(buf, rng.randf_range(0.0, 0.07), 0.05, 0.4, rng, 3.4)
			add_tone(buf, 0.0, 0.06, 190.0, 80.0, 0.2, Wave.SINE)
			return to_stream(deglitch(normalize(highpass(buf, 400.0), 0.45)))
		"wood":
			add_tone(buf, 0.0, 0.16, 240.0, 120.0, 0.55, Wave.TRI)
			add_tone(buf, 0.0, 0.10, 540.0, 300.0, 0.22, Wave.SINE)
			add_noise(buf, 0.0, 0.03, 0.35, rng, 3.0)
			return to_stream(deglitch(normalize(lowpass(buf, 3800.0), 0.5)))
		"water":
			add_noise(buf, 0.0, 0.22, 0.6, rng, 1.4)
			add_tone(buf, 0.02, 0.14, 900.0, 260.0, 0.2, Wave.SINE)
			return to_stream(deglitch(normalize(lowpass_sweep(buf, 5200.0, 1200.0), 0.5)))
		"snow":
			add_noise(buf, 0.0, 0.12, 0.5, rng, 2.0)
			return to_stream(deglitch(normalize(lowpass(buf, 2200.0), 0.35)))
		_:
			add_noise(buf, 0.0, 0.10, 0.5, rng, 2.6)
			return to_stream(deglitch(normalize(lowpass(buf, 3000.0), 0.4)))


## One generic animal-voice engine. Species differ only by their parameters,
## which keeps a dozen distinct calls inside one code path.
##   base/end   - pitch sweep in Hz
##   rough      - amplitude modulation depth (growl / bleat)
##   rough_hz   - modulation rate
##   breath     - noise mixed in
##   harmonics  - how many overtones
##   dur        - seconds
##   wobble     - vibrato depth in Hz
static func animal_call(rng: RandomNumberGenerator, p: Dictionary) -> AudioStreamWAV:
	var dur := float(p.get("dur", 0.7))
	var buf := make_buffer(dur + 0.6)
	var base := float(p.get("base", 220.0))
	var end_f := float(p.get("end", base * 0.8))
	var rough := float(p.get("rough", 0.0))
	var rough_hz := float(p.get("rough_hz", 28.0))
	var breath := float(p.get("breath", 0.08))
	var harmonics := int(p.get("harmonics", 5))
	var wobble := float(p.get("wobble", 0.0))
	var wobble_hz := float(p.get("wobble_hz", 6.0))
	var curve := float(p.get("curve", 1.0))
	var env_a := float(p.get("attack", 0.08))
	var env_r := float(p.get("release", 0.35))
	var n := int(dur * RATE)
	var phases := PackedFloat32Array()
	phases.resize(harmonics)
	phases.fill(0.0)
	for i in n:
		var t := float(i) / float(maxi(n, 1))
		var f: float = lerpf(base, end_f, pow(t, curve))
		f += sin(TAU * wobble_hz * t * dur) * wobble
		var env := adsr(t, env_a, 0.18, 0.78, env_r)
		var am: float = 1.0 - rough * 0.5 * (1.0 - cos(TAU * rough_hz * t * dur))
		var sample := 0.0
		for h in harmonics:
			var mult := float(h + 1)
			phases[h] += TAU * f * mult / float(RATE)
			var hg: float = 1.0 / pow(mult, float(p.get("tilt", 1.3)))
			sample += sin(phases[h]) * hg
		sample /= 2.2
		sample += rng.randf_range(-1.0, 1.0) * breath
		buf[i] += sample * env * am
	var shaped := lowpass(buf, float(p.get("tone", 4200.0)))
	shaped = highpass(shaped, float(p.get("body", 80.0)))
	shaped = reverb(shaped, float(p.get("space", 0.25)), 0.55)
	return to_stream(deglitch(normalize(shaped, 0.8)))


static func bird_chirp(rng: RandomNumberGenerator, seed_index: int) -> AudioStreamWAV:
	var local := RandomNumberGenerator.new()
	local.seed = 9917 + seed_index * 7717
	var buf := make_buffer(1.4)
	var notes := local.randi_range(2, 6)
	var t := 0.05
	for i in notes:
		var f0 := local.randf_range(2200.0, 4600.0)
		var f1 := f0 * local.randf_range(0.6, 1.6)
		var d := local.randf_range(0.04, 0.11)
		add_tone(buf, t, d, f0, f1, 0.42, Wave.SINE)
		add_tone(buf, t, d * 0.8, f0 * 2.0, f1 * 2.0, 0.12, Wave.SINE)
		t += d + local.randf_range(0.02, 0.10)
	var shaped := reverb(highpass(buf, 900.0), 0.28, 0.5)
	return to_stream(deglitch(normalize(shaped, 0.45)))


static func wind_bed(rng: RandomNumberGenerator, seconds: float = 8.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = rng.randf_range(-1.0, 1.0)
	var shaped := lowpass(buf, 700.0)
	shaped = lowpass(shaped, 420.0)
	shaped = highpass(shaped, 60.0)
	# Slow gusts.
	for i in n:
		var t := float(i) / float(RATE)
		var gust := 0.55 + 0.45 * sin(TAU * t / 7.0) * sin(TAU * t / 2.75 + 1.3)
		shaped[i] *= gust
	return to_stream(seamless(normalize(shaped, 0.5)), true)


static func rain_bed(rng: RandomNumberGenerator, seconds: float = 6.0, heavy := false) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = rng.randf_range(-1.0, 1.0)
	var shaped := lowpass(buf, 5200.0 if heavy else 3200.0)
	shaped = highpass(shaped, 380.0)
	# Individual droplets on top of the hiss.
	var drops := int(seconds * (90.0 if heavy else 34.0))
	for d in drops:
		var pos := rng.randf_range(0.0, seconds - 0.05)
		add_tone(shaped, pos, 0.02, rng.randf_range(1800.0, 5200.0), 900.0, 0.10, Wave.SINE)
	return to_stream(seamless(normalize(shaped, 0.55)), true)


static func stream_bed(rng: RandomNumberGenerator, seconds: float = 6.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = rng.randf_range(-1.0, 1.0)
	var shaped := lowpass(buf, 2400.0)
	shaped = highpass(shaped, 500.0)
	for i in n:
		var t := float(i) / float(RATE)
		shaped[i] *= 0.7 + 0.3 * sin(TAU * t / 1.9 + sin(TAU * t / 0.7))
	return to_stream(seamless(normalize(shaped, 0.4)), true)


static func ui_tick(rng: RandomNumberGenerator, pitch: float, soft := true) -> AudioStreamWAV:
	var buf := make_buffer(0.18)
	add_tone(buf, 0.0, 0.09, pitch, pitch * 0.98, 0.4, Wave.SINE)
	if not soft:
		add_noise(buf, 0.0, 0.02, 0.25, rng, 4.0)
	return to_stream(deglitch(normalize(buf, 0.35)))


## Rising four-note figure used when a species enters the Discovery Book.
static func discovery_sting(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(2.6)
	var scale := [392.0, 466.16, 587.33, 698.46, 880.0]
	var t := 0.0
	for i in scale.size():
		var f: float = scale[i]
		add_tone(buf, t, 1.1, f, f, 0.30, Wave.SINE)
		add_tone(buf, t, 0.9, f * 2.0, f * 2.0, 0.10, Wave.SINE)
		add_tone(buf, t, 1.4, f * 0.5, f * 0.5, 0.14, Wave.TRI)
		t += 0.16
	var shaped := reverb(buf, 0.45, 0.72)
	return to_stream(deglitch(normalize(shaped, 0.6)))


static func score_flourish(rng: RandomNumberGenerator, great: bool) -> AudioStreamWAV:
	var buf := make_buffer(1.8)
	var notes := [523.25, 659.25, 783.99, 1046.5] if great else [523.25, 659.25]
	var t := 0.0
	for f: float in notes:
		add_tone(buf, t, 0.8, f, f, 0.28, Wave.SINE)
		add_tone(buf, t, 0.6, f * 3.0, f * 3.0, 0.05, Wave.SINE)
		t += 0.11
	return to_stream(deglitch(normalize(reverb(buf, 0.35, 0.6), 0.5)))


static func thunder(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(4.2)
	# An initial crack, then a long tumbling rumble made of overlapping bursts.
	add_noise(buf, 0.0, 0.5, 0.55, rng, 0.8)
	for i in 9:
		var t := rng.randf_range(0.05, 3.0)
		add_noise(buf, t, rng.randf_range(0.5, 1.6), rng.randf_range(0.20, 0.55), rng, 0.9)
	add_tone(buf, 0.0, 3.4, 46.0, 24.0, 0.55, Wave.SINE, 0.4)
	add_tone(buf, 0.3, 2.6, 71.0, 33.0, 0.32, Wave.TRI, 0.5)
	var shaped := lowpass_sweep(buf, 900.0, 110.0)
	shaped = highpass(shaped, 24.0)
	shaped = reverb(shaped, 0.55, 0.82)
	return to_stream(deglitch(normalize(shaped, 0.85), 20.0))


static func heartbeat(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(1.0)
	add_tone(buf, 0.0, 0.22, 68.0, 40.0, 0.9, Wave.SINE, 0.6)
	add_tone(buf, 0.30, 0.18, 60.0, 36.0, 0.6, Wave.SINE, 0.6)
	return to_stream(deglitch(normalize(lowpass(buf, 220.0), 0.7)))


static func camera_raise(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(0.4)
	add_noise(buf, 0.0, 0.18, 0.30, rng, 1.8)
	add_tone(buf, 0.0, 0.22, 180.0, 320.0, 0.16, Wave.TRI)
	return to_stream(deglitch(normalize(lowpass_sweep(buf, 1200.0, 3000.0), 0.3)))


# ------------------------------------------------------------------ music beds

## Builds one looping music layer. Frequencies are quantised so that every
## partial completes a whole number of cycles inside the loop, which means the
## bed loops perfectly without a crossfade artefact.
##   chord   - array of semitone offsets from the root
##   root_hz - the root
##   mood    - 0 calm, 1 wonder, 2 tension
static func music_layer(chord: Array, root_hz: float, seconds: float, mood: int,
		rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	buf.fill(0.0)

	# Sustained pad: each chord tone gets three slightly detuned partials.
	for semi: float in chord:
		var f := root_hz * pow(2.0, semi / 12.0)
		for d in 3:
			var detune: float = [0.0, 0.13, -0.11][d]
			var freq := _quantise(f + detune, seconds)
			var amp := 0.16 / (1.0 + float(d) * 0.7)
			var lfo_rate := _quantise_rate(0.07 + 0.031 * float(d), seconds)
			var phase := 0.0
			for i in n:
				var t := float(i) / float(RATE)
				phase += TAU * freq / float(RATE)
				var swell := 0.55 + 0.45 * sin(TAU * lfo_rate * t)
				buf[i] += sin(phase) * amp * swell

	# A low drone anchors the harmony.
	var drone_f := _quantise(root_hz * 0.5, seconds)
	var dphase := 0.0
	for i in n:
		dphase += TAU * drone_f / float(RATE)
		buf[i] += (sin(dphase) + 0.3 * sin(dphase * 2.0)) * 0.13

	if mood == 1:
		# Wonder: a sparse pentatonic figure drifting over the pad.
		var pent := [0.0, 3.0, 5.0, 7.0, 10.0, 12.0, 15.0]
		var t := 0.0
		while t < seconds - 1.2:
			var semi: float = pent[rng.randi_range(0, pent.size() - 1)]
			var f := root_hz * 2.0 * pow(2.0, semi / 12.0)
			add_tone(buf, t, 1.1, f, f, 0.13, Wave.SINE)
			add_tone(buf, t, 0.8, f * 2.0, f * 2.0, 0.04, Wave.SINE)
			t += rng.randf_range(0.7, 1.8)
	elif mood == 2:
		# Tension: a pulse on the root and a tritone shimmer.
		var beat := seconds / 16.0
		for i in 16:
			var amp: float = 0.16 if i % 4 == 0 else 0.08
			add_tone(buf, float(i) * beat, beat * 0.9, root_hz, root_hz * 0.98, amp, Wave.TRI)
		add_tone(buf, 0.0, seconds, root_hz * 1.4142, root_hz * 1.4142, 0.035, Wave.SINE)

	var shaped := lowpass(buf, 2600.0 if mood != 2 else 1800.0)
	shaped = highpass(shaped, 42.0)
	shaped = reverb(shaped, 0.42, 0.74)
	shaped = normalize(shaped, 0.62)
	return to_stream(shaped, true)


## Nudges a frequency so it fits a whole number of cycles in the loop.
static func _quantise(freq: float, seconds: float) -> float:
	var cycles := maxf(1.0, round(freq * seconds))
	return cycles / seconds


static func _quantise_rate(rate: float, seconds: float) -> float:
	var cycles := maxf(1.0, round(rate * seconds))
	return cycles / seconds


# ------------------------------------------------------- ambience: living world

## Crickets and cicadas. Two bands: a dense high shimmer that reads as cicadas
## in the heat, and sparse low chirps that carry at night.
static func insect_bed(rng: RandomNumberGenerator, seconds: float = 7.0,
		night := false) -> AudioStreamWAV:
	var buf := make_buffer(seconds)
	var chirps := int(seconds * (26.0 if night else 14.0))
	for c in chirps:
		var at := rng.randf_range(0.0, seconds - 0.2)
		var f := rng.randf_range(2600.0, 4400.0) if night else rng.randf_range(4200.0, 6800.0)
		# A cricket chirp is a short burst of pulses, not one tone.
		var pulses := rng.randi_range(2, 4)
		for p in pulses:
			add_tone(buf, at + float(p) * 0.035, 0.018, f, f * 0.97, 0.10, Wave.TRI)
	if not night:
		# Daytime cicada shimmer: amplitude-modulated noise up high.
		var n := buf.size()
		var shimmer := PackedFloat32Array()
		shimmer.resize(n)
		for i in n:
			shimmer[i] = rng.randf_range(-1.0, 1.0)
		shimmer = highpass(lowpass(shimmer, 7200.0), 3800.0)
		for i in n:
			var t := float(i) / float(RATE)
			shimmer[i] *= 0.16 * (0.6 + 0.4 * sin(TAU * t * 11.0))
			buf[i] += shimmer[i]
	return to_stream(seamless(normalize(buf, 0.34)), true)


## Leaves. Sits above the wind bed in the spectrum so the two stack into one
## convincing canopy instead of muddying each other.
static func leaf_bed(rng: RandomNumberGenerator, seconds: float = 6.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = rng.randf_range(-1.0, 1.0)
	var shaped := highpass(lowpass(buf, 6400.0), 1400.0)
	for i in n:
		var t := float(i) / float(RATE)
		# Rustle comes in irregular pushes, like gusts catching the canopy.
		var gust := 0.30 + 0.70 * maxf(0.0,
			sin(TAU * t / 5.3) * sin(TAU * t / 1.7 + 0.9) + 0.25)
		shaped[i] *= gust
	return to_stream(seamless(normalize(shaped, 0.30)), true)


## The low room-tone of a forest after dark: air, distance and a little owl.
static func night_bed(rng: RandomNumberGenerator, seconds: float = 8.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = rng.randf_range(-1.0, 1.0)
	var shaped := lowpass(buf, 260.0)
	shaped = highpass(shaped, 40.0)
	for i in n:
		shaped[i] *= 0.5
	# Two distant hoots per loop, well back in the reverb.
	for h in 2:
		var at := rng.randf_range(0.5, seconds - 2.0)
		add_tone(shaped, at, 0.28, 300.0, 262.0, 0.09, Wave.SINE)
		add_tone(shaped, at + 0.45, 0.34, 262.0, 248.0, 0.07, Wave.SINE)
	shaped = reverb(shaped, 0.5, 0.8)
	return to_stream(seamless(normalize(shaped, 0.30)), true)


## A branch going under a boot. The cue that you have just given yourself away.
static func branch_snap(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(0.5)
	add_noise(buf, 0.0, 0.012, 0.85, rng, 1.0)
	add_tone(buf, 0.0, 0.05, rng.randf_range(320.0, 640.0), 120.0, 0.35, Wave.TRI)
	# The splintering tail.
	for s in 5:
		add_noise(buf, rng.randf_range(0.01, 0.16), 0.008, 0.22, rng, 1.0)
	var shaped := lowpass(buf, 5200.0)
	shaped = reverb(shaped, 0.22, 0.55)
	return to_stream(deglitch(normalize(shaped, 0.7)))


## Something entering water, or leaving it in a hurry.
static func water_splash(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(0.8)
	add_noise(buf, 0.0, 0.09, 0.7, rng, 2.0)
	# Bubbles: rising pitches after the impact.
	for b in 7:
		var at := rng.randf_range(0.04, 0.42)
		var f := rng.randf_range(500.0, 1500.0)
		add_tone(buf, at, 0.05, f, f * 1.8, 0.10, Wave.SINE)
	var shaped := lowpass(buf, 4200.0)
	shaped = highpass(shaped, 180.0)
	shaped = reverb(shaped, 0.3, 0.6)
	return to_stream(deglitch(normalize(shaped, 0.6)))


# --------------------------------------------------------- plucked / struck

## Karplus-Strong: a burst of noise fed through a decaying delay line. Cheap,
## and it sounds like a real string because it is the same physics.
static func pluck(buf: PackedFloat32Array, start: float, freq: float, amp: float,
		rng: RandomNumberGenerator, damp: float = 0.996, dur: float = 2.2) -> void:
	var delay := maxi(2, int(float(RATE) / maxf(freq, 20.0)))
	var line := PackedFloat32Array()
	line.resize(delay)
	for i in delay:
		line[i] = rng.randf_range(-1.0, 1.0)
	var start_i := int(start * RATE)
	var count := mini(int(dur * RATE), buf.size() - start_i)
	var idx := 0
	for i in count:
		var nxt := (idx + 1) % delay
		# Average neighbouring samples: the low-pass that makes it decay.
		var v := (line[idx] + line[nxt]) * 0.5 * damp
		line[idx] = v
		idx = nxt
		# Fade the tail so notes do not click when they run out.
		var fade := 1.0 - float(i) / float(count)
		buf[start_i + i] += v * amp * fade


## Struck string: a piano is mostly a fast attack, a handful of slightly sharp
## partials, and a long decay.
static func strike(buf: PackedFloat32Array, start: float, freq: float, amp: float,
		dur: float = 2.6) -> void:
	var partials := [1.0, 2.001, 3.004, 4.01, 5.02]
	var gains := [1.0, 0.42, 0.22, 0.10, 0.05]
	for p in partials.size():
		var f: float = freq * float(partials[p])
		if f > float(RATE) * 0.45:
			continue
		var start_i := int(start * RATE)
		var count := mini(int(dur * RATE), buf.size() - start_i)
		var phase := 0.0
		var g: float = amp * float(gains[p])
		for i in count:
			phase += TAU * f / float(RATE)
			var t := float(i) / float(RATE)
			# Higher partials die away faster, as they do on a real string.
			var decay: float = exp(-t * (1.6 + float(p) * 1.4))
			buf[start_i + i] += sin(phase) * g * decay


# ------------------------------------------------------------- adaptive music

## Soft fingerpicked acoustic guitar. The morning bed.
static func music_acoustic(rng: RandomNumberGenerator, seconds: float,
		root_hz: float) -> AudioStreamWAV:
	var buf := make_buffer(seconds)
	# An open, unhurried voicing - root, fifth, octave, ninth.
	var voicing := [0.0, 7.0, 12.0, 14.0, 19.0]
	var step := 0.42
	var t := 0.0
	var i := 0
	while t < seconds - 2.2:
		var semi: float = voicing[i % voicing.size()]
		var f := root_hz * pow(2.0, semi / 12.0)
		pluck(buf, t, f, 0.34, rng, 0.9965, minf(2.4, seconds - t))
		# Every fourth note, add the octave above for a little lift.
		if i % 4 == 3:
			pluck(buf, t + 0.06, f * 2.0, 0.13, rng, 0.994, minf(1.6, seconds - t))
		t += step * (1.5 if i % 8 == 7 else 1.0)
		i += 1
	var shaped := lowpass(buf, 4200.0)
	shaped = highpass(shaped, 70.0)
	shaped = reverb(shaped, 0.34, 0.7)
	return to_stream(seamless(normalize(shaped, 0.5)), true)


## Sparse piano. The rain bed - slow, spaced, a little melancholy.
static func music_piano(rng: RandomNumberGenerator, seconds: float,
		root_hz: float) -> AudioStreamWAV:
	var buf := make_buffer(seconds)
	# Natural minor, so it stays wistful rather than sad.
	var scale := [0.0, 3.0, 5.0, 7.0, 10.0, 12.0]
	var t := 0.0
	while t < seconds - 2.6:
		var semi: float = scale[rng.randi_range(0, scale.size() - 1)]
		var f := root_hz * pow(2.0, semi / 12.0)
		strike(buf, t, f, 0.26, minf(2.8, seconds - t))
		# A quiet left hand underneath every other phrase.
		if rng.randf() < 0.45:
			strike(buf, t + 0.02, root_hz * 0.5, 0.15, minf(3.0, seconds - t))
		t += rng.randf_range(0.9, 1.9)
	var shaped := lowpass(buf, 3400.0)
	shaped = highpass(shaped, 55.0)
	shaped = reverb(shaped, 0.46, 0.8)
	return to_stream(seamless(normalize(shaped, 0.48)), true)


## Slow ambient pad for the small hours. Barely moves.
static func music_pad(rng: RandomNumberGenerator, seconds: float,
		root_hz: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	buf.fill(0.0)
	for semi: float in [0.0, 7.0, 15.0, 19.0]:
		var f := _quantise(root_hz * pow(2.0, semi / 12.0), seconds)
		for d in 2:
			var detune: float = [0.0, 0.09][d]
			var freq := _quantise(f + detune, seconds)
			var rate := _quantise_rate(0.033 + 0.017 * float(d), seconds)
			var phase := 0.0
			for i in n:
				var t := float(i) / float(RATE)
				phase += TAU * freq / float(RATE)
				buf[i] += sin(phase) * 0.13 * (0.5 + 0.5 * sin(TAU * rate * t))
	var shaped := lowpass(buf, 1500.0)
	shaped = reverb(shaped, 0.55, 0.86)
	return to_stream(seamless(normalize(shaped, 0.5)), true)


## Music swells when a legendary animal comes into view.
static func legendary_swell(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(4.5)
	var root := 174.61                                  # F3
	for semi: float in [0.0, 7.0, 12.0, 16.0, 19.0]:
		var f := root * pow(2.0, semi / 12.0)
		var phase := 0.0
		for i in buf.size():
			var t := float(i) / float(RATE)
			phase += TAU * f / float(RATE)
			# Slow crescendo, then a long release.
			var env: float = smoothstep(0.0, 2.2, t) * (1.0 - smoothstep(2.6, 4.5, t))
			buf[i] += sin(phase) * 0.11 * env
	add_noise(buf, 0.0, 2.4, 0.05, rng, 0.6)             # a breath of air under it
	var shaped := lowpass(buf, 3000.0)
	shaped = reverb(shaped, 0.6, 0.88)
	return to_stream(deglitch(normalize(shaped, 0.62)))


## The little orchestral lift for a frame that came out perfectly.
static func orchestral_flourish(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buf := make_buffer(2.6)
	var root := 261.63                                   # C4
	# A rising arpeggio, strings-ish, each note overlapping the last.
	var steps := [0.0, 4.0, 7.0, 12.0, 16.0, 19.0]
	for s in steps.size():
		var f := root * pow(2.0, float(steps[s]) / 12.0)
		var at := float(s) * 0.11
		add_tone(buf, at, 1.5, f, f * 1.002, 0.15, Wave.SINE)
		add_tone(buf, at, 1.2, f * 2.0, f * 2.0, 0.04, Wave.TRI)
	add_noise(buf, 0.0, 0.06, 0.10, rng, 3.0)
	var shaped := lowpass(buf, 5200.0)
	shaped = reverb(shaped, 0.5, 0.8)
	return to_stream(deglitch(normalize(shaped, 0.6)))
