class_name Sfx
extends Node
## Game audio. Gameplay events play recorded samples from res://sounds/sfx/ (se_foofon#N.wav), picked from the
## category that fits the situation; the synthesized sounds (hits, horn, crowd bed, amapiano-ish loop) are the
## fallback and the ambience.

const SAMPLE_PATH := "res://sounds/sfx/se_foofon#%d.wav"
## Sample numbers per category, as [first, last] inclusive.
const CATS := {
	"crowd": [[1, 29], [32, 62], [75, 82], [87, 90], [102, 108], [113, 116], [165, 166]],
	"ball": [[68, 74], [85, 85], [91, 94], [110, 110], [120, 137], [148, 153]],
	"skills": [[63, 67], [117, 117], [140, 147]],
	"tackle": [[94, 94], [138, 139], [154, 164]],
	"ability": [[29, 31], [145, 147]],   # the soul ball's powers
	"whistle": [[83, 85]],
	"net": [[97, 101], [109, 109]],
	"extra": [[109, 109], [119, 119]],
}
## Game event -> [category, min length s, max length s, gain dB]. Length splits a category by weight of sound:
## short ball samples are touches, longer ones are blasts; short crowd samples are gasps, long ones roars.
const EVENTS := {
	"touch": ["ball", 0.0, 0.2, 0.0],        # ball lands at a player's feet
	"kick": ["ball", 0.2, 0.45, 0.0],        # pass / shot
	"thud": ["ball", 0.45, 0.7, 0.0],        # ball off a wall / cage / brick, parry
	"boom": ["ball", 0.7, 1.5, 0.0],         # power shot
	"skill": ["skills", 0.0, 1.0, 0.0],      # nutmeg, rainbow flick, fake, roulette
	"lunge": ["tackle", 0.4, 0.8, 0.0],      # slide tackle / keeper dive
	"bam": ["tackle", 0.2, 0.4, 4.0],        # tackle won / shoulder charge
	"power": ["ability", 0.0, 1.0, 0.0],     # stage-up, burst sprint, soul shot
	"soul_big": ["ability", 1.0, 3.0, 0.0],  # hungry / overloaded stage-up, backlash, soul goal
	"whistle": ["whistle", 0.0, 9.0, 0.0],
	"net": ["net", 0.0, 9.0, 0.0],           # goal
	"clunk": ["extra", 0.0, 9.0, 0.0],       # brick added to the goal
	"gasp": ["crowd", 0.0, 3.5, -3.0],       # near miss, save, parry
	"cheer": ["crowd", 3.5, 7.0, -3.0],      # goal
	"roar": ["crowd", 7.0, 11.0, -3.0],      # full time
}

const RATE := 22050
const BPM := 112.0
# Log-drum lines per bar: step -> Hz.
const LOG := [{0: 55.0, 3: 55.0, 6: 65.4, 10: 55.0, 11: 82.4, 14: 49.0}, {0: 43.7, 3: 43.7, 7: 55.0, 10: 65.4, 12: 49.0, 14: 55.0}]
const CHORDS := [[220.0, 261.6, 329.6, 392.0], [174.6, 220.0, 261.6, 329.6]]

var bank := {}
var pools := {}     # event -> Array of sample streams
var pool: Array[AudioStreamPlayer] = []
var next := 0
var crowd: AudioStreamPlayer       # looping bed
var crowd_fx: AudioStreamPlayer    # one crowd reaction at a time
var _lp := 0.0
var _lp2 := 0.0


func _ready() -> void:
	bank.kick = _render(0.14, func(t: float) -> float:
		return sin(TAU * (50.0 + 160.0 * exp(-t * 35.0)) * t) * exp(-t * 22.0) + _noise() * exp(-t * 120.0) * 0.4)
	bank.touch = _render(0.08, func(t: float) -> float:
		return sin(TAU * 180.0 * t) * exp(-t * 60.0) * 0.5 + _noise() * exp(-t * 200.0) * 0.2)
	bank.boom = _render(0.7, func(t: float) -> float:
		return sin(TAU * (40.0 + 120.0 * exp(-t * 12.0)) * t) * exp(-t * 5.0) + _low(_noise(), 0.2) * exp(-t * 6.0) * 1.2)
	bank.bam = _render(0.25, func(t: float) -> float:
		return _low(_noise(), 0.3) * exp(-t * 14.0) * 1.6 + sin(TAU * 90.0 * t) * exp(-t * 20.0) * 0.6)
	bank.thud = _render(0.15, func(t: float) -> float:
		return sin(TAU * 110.0 * t) * exp(-t * 30.0) * 0.7 + _low(_noise(), 0.3) * exp(-t * 40.0))
	bank.whoosh = _render(0.3, func(t: float) -> float:
		return _low(_noise(), 0.35) * sin(PI * t / 0.3) * 0.7)
	bank.whistle = _render(0.6, func(t: float) -> float:
		return sin(TAU * 2900.0 * t + 3.0 * sin(TAU * 35.0 * t)) * minf(t * 40.0, 1.0) * minf((0.6 - t) * 20.0, 1.0) * 0.35)
	bank.goal = _render(1.8, func(t: float) -> float:
		var v := 0.0
		for f: float in [233.1, 293.7, 349.2]:
			v += fmod(f * t, 1.0) * 2.0 - 1.0
		return v * 0.14 * minf(t * 20.0, 1.0) * minf((1.8 - t) * 3.0, 1.0))
	bank.clunk = _render(0.35, func(t: float) -> float:
		return sin(TAU * (70.0 + 60.0 * exp(-t * 30.0)) * t) * exp(-t * 12.0) + _noise() * exp(-t * 60.0) * 0.5)
	bank.power = _render(0.45, func(t: float) -> float:
		return sin(TAU * (300.0 * t + 1000.0 * t * t)) * (1.0 - t / 0.45) * 0.35)
	bank.ui = bank.touch
	_load_samples()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	crowd_fx = AudioStreamPlayer.new()
	add_child(crowd_fx)
	crowd = AudioStreamPlayer.new()
	crowd.stream = _render(4.0, _crowd, true)
	add_child(crowd)
	crowd.play()
	Jukebox.add_song(_render(32 * 60.0 / BPM / 4.0, _music, true), "Street Amapiano (built-in)")


## Samples for every event, filtered by category and length. A sample claimed by "whistle" (85 is also a
## ball sound) stays out of the other pools so a power shot never blows a whistle.
func _load_samples() -> void:
	var cache := {}
	for ev: String in EVENTS:
		var spec: Array = EVENTS[ev]
		var samples: Array[AudioStream] = []
		for r: Array in CATS[spec[0]]:
			for n in range(r[0], r[1] + 1):
				if spec[0] != "whistle" and _has(CATS.whistle, n):
					continue
				if not cache.has(n):
					cache[n] = load(SAMPLE_PATH % n) if ResourceLoader.exists(SAMPLE_PATH % n) else null
				var s: AudioStream = cache[n]
				if s and s.get_length() >= spec[1] and s.get_length() < spec[2]:
					samples.append(s)
		pools[ev] = samples


static func _has(ranges: Array, n: int) -> bool:
	for r: Array in ranges:
		if n >= r[0] and n <= r[1]:
			return true
	return false


func play(sound: String, db := 0.0) -> void:
	var spec: Array = EVENTS.get(sound, [])
	var samples: Array = pools.get(sound, [])
	var stream: AudioStream = samples.pick_random() if not samples.is_empty() else bank.get(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer
	if spec and spec[0] == "crowd":
		p = crowd_fx
	else:
		p = pool[next]
		next = (next + 1) % pool.size()
	p.stream = stream
	p.volume_db = db + (spec[3] if spec and not samples.is_empty() else 0.0)
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


## Cut the crowd reaction (new match / back to the menu).
func hush() -> void:
	crowd_fx.stop()


func set_excite(e: float) -> void:
	crowd.volume_db = linear_to_db(0.25 + e * 0.9) - 4.0


func _noise() -> float:
	return randf() * 2.0 - 1.0


func _low(x: float, a: float) -> float:
	_lp += (x - _lp) * a
	return _lp


func _render(dur: float, fn: Callable, loop := false) -> AudioStreamWAV:
	_lp = 0.0
	_lp2 = 0.0
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = fn.call(float(i) / RATE)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


func _crowd(t: float) -> float:
	_lp += (_noise() - _lp) * 0.12
	_lp2 += (_lp - _lp2) * 0.3
	return _lp2 * 2.4 * (0.75 + 0.25 * sin(TAU * 0.5 * t) * sin(TAU * 0.25 * t + 1.0))


func _music(t: float) -> float:
	var step_len := 60.0 / BPM / 4.0
	var step := int(t / step_len)
	var st := t - step * step_len
	var s := step % 16
	var bar := (step / 16) % 2
	var beat_t := fmod(t, step_len * 4.0)
	var v := sin(TAU * (45.0 + 90.0 * exp(-beat_t * 30.0)) * beat_t) * exp(-beat_t * 9.0) * 0.55
	var n := _noise()
	_lp += (n - _lp) * 0.3
	v += (n - _lp) * exp(-st * 45.0) * (0.14 if s % 2 == 1 else 0.07)  # shaker
	if s == 4 or s == 12:
		v += n * exp(-st * 22.0) * 0.3  # clap
	var line: Dictionary = LOG[bar]
	for k in range(s, -1, -1):
		if line.has(k):
			var nt := t - (bar * 16 + k) * step_len
			v += sin(TAU * line[k] * nt * (1.0 + 0.6 * exp(-nt * 25.0))) * exp(-nt * 4.5) * 0.55
			break
	for f: float in CHORDS[bar]:
		v += (absf(fmod(t * f, 1.0) * 4.0 - 2.0) - 1.0) * 0.025
	return v * 0.8
