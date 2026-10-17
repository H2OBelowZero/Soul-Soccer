extends Node
## Global playlist (autoload "Jukebox"). Survives pause; the menu's music page drives it.
## Every audio file in res://sounds/music/ joins the library at startup, so dropping a file there is enough.
## Menus play it dry and loud; mid-match it drops to a quiet, reverbed, muffled mix, as if it were the venue's PA.
## Songs can also be added from code, anywhere:
##     Jukebox.add_song("res://music/track.ogg", "My Track")   # path (ogg/mp3/wav) ...
##     Jukebox.add_song(my_audio_stream, "Generated")          # ... or an AudioStream
## Or list them in _ready() below. The first song added starts playing.

signal changed

const MUSIC_DIR := "res://sounds/music/"
const LAST_FILE := "user://last_song.txt"
const EXTENSIONS := ["mp3", "ogg", "wav"]
const MENU_DB := -9.0
const MATCH_DB := -21.0
const VENUE_BUS := &"Venue"

var songs: Array[Dictionary] = []   # {title: String, stream: AudioStream}
var index := -1
var shuffle := false
var player := AudioStreamPlayer.new()
var _fade: Tween
var _bus := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_venue_bus()
	player.bus = VENUE_BUS
	player.volume_db = MENU_DB
	player.finished.connect(next)
	add_child(player)
	_scan_library()
	_random_start()


## Start on a random track, never the one the previous run opened with (remembered in user://).
func _random_start() -> void:
	if songs.size() < 2:
		return
	var f := FileAccess.open(LAST_FILE, FileAccess.READ)
	var last := f.get_as_text() if f else ""
	var pool := range(songs.size()).filter(func(i: int) -> bool: return songs[i].title != last)
	play_index(pool.pick_random())
	f = FileAccess.open(LAST_FILE, FileAccess.WRITE)
	if f:
		f.store_string(songs[index].title)


## Reverb + low-pass on its own bus, switched on only while a match is live.
func _make_venue_bus() -> void:
	AudioServer.add_bus()
	_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus, VENUE_BUS)
	AudioServer.set_bus_send(_bus, &"Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3800.0
	AudioServer.add_bus_effect(_bus, lp)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.9
	rv.damping = 0.45
	rv.wet = 0.5
	rv.dry = 0.55
	AudioServer.add_bus_effect(_bus, rv)
	_venue(false)


func _venue(on: bool) -> void:
	for i in AudioServer.get_bus_effect_count(_bus):
		AudioServer.set_bus_effect_enabled(_bus, i, on)


## Exported builds list imported files as "name.mp3.import" (or ".remap"), so strip that to get the loadable path.
func _scan_library() -> void:
	var names: Array[String] = []
	for f in DirAccess.get_files_at(MUSIC_DIR):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.get_extension().to_lower() in EXTENSIONS and n not in names:
			names.append(n)
	names.sort()
	for n in names:
		add_song(MUSIC_DIR + n, n.get_basename())


## Menus on = dry and loud, match live = quiet and echoing round the venue.
func set_menu(on: bool) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween().set_ignore_time_scale(true)
	_venue(not on)
	_fade.tween_property(player, "volume_db", MENU_DB if on else MATCH_DB, 0.6)


func add_song(source: Variant, title := "") -> void:
	var s: AudioStream = source if source is AudioStream else load(String(source))
	if s == null:
		push_warning("Jukebox: could not load %s" % str(source))
		return
	if title == "":
		title = String(source).get_file().get_basename() if source is String else "Track %d" % (songs.size() + 1)
	songs.append({"title": title, "stream": s})
	changed.emit()
	if index < 0:
		play_index(0)


func play_index(i: int) -> void:
	if songs.is_empty():
		return
	index = wrapi(i, 0, songs.size())
	player.stream = songs[index].stream
	player.stream_paused = false
	player.play()
	changed.emit()


func next() -> void:
	if shuffle and songs.size() > 1:
		play_index((index + randi_range(1, songs.size() - 1)) % songs.size())
	else:
		play_index(index + 1)


func prev() -> void:
	play_index(index - 1)


func toggle() -> void:
	if player.playing and not player.stream_paused:
		player.stream_paused = true
	elif player.stream_paused:
		player.stream_paused = false
	else:
		play_index(maxi(index, 0))
	changed.emit()


func is_playing() -> bool:
	return player.playing and not player.stream_paused


func now_playing() -> String:
	return "" if index < 0 else String(songs[index].title)
