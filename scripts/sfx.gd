extends Node
## Tiny synthesizer: every sound effect is generated at startup, so the
## project has no audio assets to license or ship.

const RATE := 22050

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_sounds["swing"] = _make(0.16, func(t, n): return n * _env(t, 0.16, 0.01) * 0.5 * sin(t * 900.0 * (1.0 - t * 3.0)) )
	_sounds["hit"] = _make(0.18, func(t, n): return (sin(TAU * 90.0 * t * (1.0 - t * 2.0)) * 0.9 + n * 0.6) * _env(t, 0.18, 0.002))
	_sounds["crit"] = _make(0.3, func(t, n): return (sin(TAU * 60.0 * t) * 0.9 + n * 0.8 + sin(TAU * 1400.0 * t) * 0.2) * _env(t, 0.3, 0.001))
	_sounds["die"] = _make(0.45, func(t, n): return (n * 0.7 + sin(TAU * (160.0 - t * 260.0) * t) * 0.5) * _env(t, 0.45, 0.005))
	_sounds["hurt"] = _make(0.22, func(t, n): return (sin(TAU * 140.0 * t) * 0.8 + n * 0.3) * _env(t, 0.22, 0.003))
	_sounds["gold"] = _make(0.25, func(t, n): return (sin(TAU * 1760.0 * t) + sin(TAU * 2637.0 * t) * 0.5) * _env(t, 0.25, 0.001) * 0.35)
	_sounds["loot"] = _make(0.5, func(t, n):
		var f := 523.0 if t < 0.1 else (659.0 if t < 0.2 else 988.0)
		return (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.2) * _env(t, 0.5, 0.005))
	_sounds["potion"] = _make(0.35, func(t, n): return sin(TAU * (300.0 + 600.0 * t) * t) * _env(t, 0.35, 0.02) * 0.5)
	_sounds["cast"] = _make(0.3, func(t, n): return (n * 0.4 + sin(TAU * (500.0 - 900.0 * t) * t) * 0.5) * _env(t, 0.3, 0.005))
	_sounds["nova"] = _make(0.6, func(t, n): return (n * 0.6 + sin(TAU * 70.0 * t) * 0.8) * _env(t, 0.6, 0.004))
	_sounds["level"] = _make(0.9, func(t, n):
		var f: float = [392.0, 523.0, 659.0, 784.0][mini(int(t / 0.12), 3)]
		return (sin(TAU * f * t) * 0.45 + sin(TAU * f * 1.5 * t) * 0.15) * _env(t, 0.9, 0.01))
	_sounds["stairs"] = _make(0.8, func(t, n): return (sin(TAU * 110.0 * t) * 0.5 + sin(TAU * 165.0 * t) * 0.3 + n * 0.1) * _env(t, 0.8, 0.1))


func _env(t: float, length: float, attack: float) -> float:
	if t < attack:
		return t / attack
	return pow(1.0 - (t - attack) / (length - attack), 2.0)


func _make(length: float, gen: Callable) -> AudioStreamWAV:
	var frames := int(length * RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / RATE
		var v: float = gen.call(t, _rng.randf_range(-1.0, 1.0))
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func play(sound: String, volume_db := -6.0, pitch_jitter := 0.08) -> void:
	if not _sounds.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()
