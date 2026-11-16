extends Node
## Procedurally synthesised sound effects (no external assets) with pooled
## 2D and 3D players.

const RATE := 22050
const POOL_3D := 28
const POOL_2D := 10

## name -> [stream, max_distance, volume_db]
var _sounds := {}
var _p3: Array[AudioStreamPlayer3D] = []
var _p2: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _loops := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	_make_all()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_p2.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 8.0
		add_child(p)
		_p3.append(p)


func _make_all() -> void:
	_reg("ar", _gun(0.16, 900.0, 0.55, 140.0), 320.0, -4.0)
	_reg("smg", _gun(0.1, 1300.0, 0.45, 180.0), 260.0, -6.0)
	_reg("pistol", _gun(0.13, 1100.0, 0.5, 160.0), 260.0, -5.0)
	_reg("pump", _gun(0.42, 500.0, 0.9, 80.0, true), 320.0, -1.0)
	_reg("tac", _gun(0.34, 600.0, 0.8, 90.0, true), 320.0, -2.0)
	_reg("sniper", _gun(0.7, 700.0, 1.0, 60.0, true), 900.0, 0.0)
	_reg("rocket", _whoosh(0.6), 400.0, -2.0)
	_reg("explosion", _boom(1.2), 700.0, 2.0)
	_reg("pickaxe_hit", _thunk(0.16, 220.0), 60.0, -3.0)
	_reg("pickaxe_crit", _thunk(0.2, 420.0, true), 60.0, -1.0)
	_reg("swing", _swish(0.18), 30.0, -10.0)
	_reg("build", _thunk(0.14, 160.0), 70.0, -6.0)
	_reg("edit", _blip(0.08, 900.0, 1300.0), 40.0, -10.0)
	_reg("break", _crash(0.45), 120.0, -2.0)
	_reg("chest_open", _chime(0.7, [523.0, 659.0, 784.0, 1046.0]), 50.0, -2.0)
	_reg("chest_hum", _hum(1.6), 14.0, -12.0)
	_reg("pickup", _blip(0.09, 600.0, 900.0), 20.0, -6.0)
	_reg("reload", _clack(0.35), 30.0, -6.0)
	_reg("step", _step(0.07), 22.0, -14.0)
	_reg("land", _thunk(0.12, 90.0), 30.0, -8.0)
	_reg("jump", _swish(0.12), 20.0, -16.0)
	_reg("hit", _blip(0.05, 1800.0, 1700.0), 1.0, -8.0)
	_reg("headshot", _chime(0.18, [1567.0, 2093.0]), 1.0, -6.0)
	_reg("shield_hit", _blip(0.07, 1200.0, 2400.0), 1.0, -9.0)
	_reg("shield_break", _crash(0.35, true), 60.0, -3.0)
	_reg("elim", _chime(0.45, [392.0, 587.0, 784.0]), 1.0, -3.0)
	_reg("heal", _chime(0.6, [440.0, 554.0, 659.0, 880.0]), 20.0, -6.0)
	_reg("storm", _rumble(3.0), 1.0, -14.0)
	_reg("wind", _noise_loop(2.0, 0.35), 1.0, -12.0)
	_reg("bus", _engine(2.0), 1.0, -14.0)
	_reg("glider", _swish(0.4), 30.0, -6.0)
	_reg("ui", _blip(0.05, 700.0, 700.0), 1.0, -10.0)
	_reg("victory", _chime(1.6, [523.0, 659.0, 784.0, 1046.0, 1318.0]), 1.0, 0.0)
	_reg("damage_taken", _thunk(0.12, 120.0), 1.0, -6.0)
	_reg("empty", _clack(0.08), 10.0, -10.0)


func _reg(n: String, s: AudioStreamWAV, dist: float, vol: float) -> void:
	_sounds[n] = [s, dist, vol]


func play(n: String, pitch := 1.0, vol_offset := 0.0) -> void:
	if not _sounds.has(n):
		return
	var p := _p2[_i2]
	_i2 = (_i2 + 1) % _p2.size()
	p.stream = _sounds[n][0]
	p.volume_db = _sounds[n][2] + vol_offset
	p.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
	p.play()


func play_at(n: String, pos: Vector3, pitch := 1.0) -> void:
	if not _sounds.has(n):
		return
	var cam := get_viewport().get_camera_3d()
	var dist: float = _sounds[n][1]
	if cam and cam.global_position.distance_to(pos) > dist:
		return
	var p := _p3[_i3]
	_i3 = (_i3 + 1) % _p3.size()
	p.stream = _sounds[n][0]
	p.max_distance = dist
	p.volume_db = _sounds[n][2]
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.global_position = pos
	p.play()


## Looping 2D ambience; vol <= -60 stops it.
func loop(n: String, vol_db: float) -> void:
	if not _loops.has(n):
		var p := AudioStreamPlayer.new()
		var s: AudioStreamWAV = (_sounds[n][0] as AudioStreamWAV).duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = s.data.size() / 2
		p.stream = s
		add_child(p)
		_loops[n] = p
	var pl: AudioStreamPlayer = _loops[n]
	if vol_db <= -60.0:
		pl.stop()
		return
	pl.volume_db = _sounds[n][2] + vol_db
	if not pl.playing:
		pl.play()


func stop_all_loops() -> void:
	for n: String in _loops:
		_loops[n].stop()


# ------------------------------------------------------------------ synthesis

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


## Gunshot: filtered noise crack + low thump + tail.
func _gun(dur: float, crack_hz: float, body: float, thump_hz: float, boom := false) -> AudioStreamWAV:
	var b := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	var a := clampf(crack_hz / RATE * 6.0, 0.02, 0.9)
	for i in b.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1, 1)
		lp += (n - lp) * a
		lp2 += (lp - lp2) * 0.08
		var crack := (n - lp) * exp(-t * 60.0) * 0.8
		var bod := lp * exp(-t * (8.0 / body)) * 1.6
		var thump := sin(TAU * thump_hz * t * (1.0 - t * 2.0)) * exp(-t * 18.0) * (1.2 if boom else 0.7)
		var tail := lp2 * exp(-t * 4.0) * (2.5 if boom else 1.2)
		b[i] = (crack + bod + thump + tail) * 0.7
	return _wav(b)


func _boom(dur: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.05
		b[i] = (lp * 4.0 * exp(-t * 3.0) + sin(TAU * 50.0 * t) * exp(-t * 5.0)) * 0.9
	return _wav(b)


func _whoosh(dur: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.15
		b[i] = lp * 2.0 * minf(t * 20.0, 1.0) * exp(-t * 3.0) + sin(TAU * 90.0 * t) * exp(-t * 20.0) * 0.6
	return _wav(b)


func _thunk(dur: float, hz: float, bright := false) -> AudioStreamWAV:
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		var tone := sin(TAU * hz * t * (1.0 - t * 1.5)) * exp(-t * 30.0)
		var n := _rng.randf_range(-1, 1) * exp(-t * 80.0) * 0.5
		var ring := sin(TAU * hz * 4.1 * t) * exp(-t * 18.0) * (0.4 if bright else 0.0)
		b[i] = (tone + n + ring) * 0.85
	return _wav(b)


func _swish(dur: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := sin(PI * t / dur)
		lp += (_rng.randf_range(-1, 1) - lp) * (0.05 + 0.25 * env)
		b[i] = lp * env * 1.6
	return _wav(b)


func _blip(dur: float, f0: float, f1: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * lerpf(f0, f1, t / dur) / RATE
		b[i] = sin(ph) * exp(-t * 25.0) * 0.6
	return _wav(b)


func _chime(dur: float, notes: Array) -> AudioStreamWAV:
	var b := _buf(dur)
	var step := dur / (notes.size() + 1)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var st := k * step * 0.6
			if t >= st:
				var tt := t - st
				v += (sin(TAU * notes[k] * tt) + 0.3 * sin(TAU * notes[k] * 2.0 * tt)) * exp(-tt * 5.0)
		b[i] = v * 0.25
	return _wav(b)


func _crash(dur: float, glassy := false) -> AudioStreamWAV:
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1, 1)
		lp += (n - lp) * (0.5 if glassy else 0.12)
		var crackle := 1.0 if _rng.randf() < 0.2 else 0.3
		b[i] = lp * crackle * exp(-t * 7.0) * 1.4 + sin(TAU * 70.0 * t) * exp(-t * 15.0) * 0.4
	return _wav(b)


func _hum(dur: float) -> AudioStreamWAV:
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		var v := sin(TAU * 220.0 * t) + 0.5 * sin(TAU * 330.0 * t) + 0.3 * sin(TAU * 440.0 * t + sin(TAU * 2.5 * t))
		b[i] = v * 0.18 * (0.8 + 0.2 * sin(TAU * t / dur))
	return _wav(b)


func _clack(dur: float) -> AudioStreamWAV:
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		var hit1 := _rng.randf_range(-1, 1) * exp(-t * 120.0)
		var t2 := t - dur * 0.6
		var hit2 := _rng.randf_range(-1, 1) * exp(-t2 * 120.0) if t2 > 0.0 else 0.0
		b[i] = (hit1 + hit2) * 0.6 + sin(TAU * 1800.0 * t) * exp(-t * 60.0) * 0.2
	return _wav(b)


func _step(dur: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.2
		b[i] = lp * exp(-t * 50.0) * 1.5
	return _wav(b)


func _rumble(dur: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var lp := 0.0
	var n := b.size()
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.03
		var fade := minf(1.0, minf(i, n - i) / 2000.0)
		b[i] = (lp * 3.0 + sin(TAU * 40.0 * t) * 0.2) * fade
	return _wav(b)


func _noise_loop(dur: float, bright: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var lp := 0.0
	var n := b.size()
	for i in n:
		lp += (_rng.randf_range(-1, 1) - lp) * bright * 0.3
		var fade := minf(1.0, minf(i, n - i) / 2000.0)
		b[i] = lp * 1.8 * fade
	return _wav(b)


func _engine(dur: float) -> AudioStreamWAV:
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 110.0 * t) * 0.3 + _rng.randf_range(-0.1, 0.1)) * 0.6
	return _wav(b)
