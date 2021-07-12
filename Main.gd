extends Node2D

var screen_size: Vector2

var key_number: int = 88
var lowest_frequency: float = 27.5
var magnitude_bar_width: float = 0.4
var magnitude_db_array = []
var magnitude_decrease_speed: float = 60.0
var piano_bar_height: float = 0.15
var piano_bar_width: float = 0.9
onready var bar_screen_height: float = 1.0 - piano_bar_height
var lowest_magnitude: float = -60.0
export var gradient: Gradient

var delta: float = 1.0 / 60.0
var spectrum: AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(0, 0)
var stream_length: float = 0.0

var file_chosen: bool = false
var play_position: float = 0.0
var playing: bool = false
var scrubbing: bool = false

func map_range(value, source_start, source_end, target_start, target_end):
	var mapped_value: float = value - source_start
	mapped_value *= (target_end - target_start) / (source_end - source_start)
	mapped_value += target_start
	return mapped_value

func draw_magnitude(key_index: int):
	var x_position_uniform: float = 1.0 / key_number * (key_index + 0.5)
	var x_position: float = screen_size.x * x_position_uniform
	var frequency_start: float = lowest_frequency * pow(2.0, (1.0 / 12.0) * (key_index - 0.5))
	var frequency_end: float = lowest_frequency * pow(2.0, (1.0 / 12.0) * (key_index + 0.5))
	var magnitude: Vector2 = spectrum.get_magnitude_for_frequency_range(frequency_start, frequency_end, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
	if not $AudioStreamPlayer.playing:
		magnitude = Vector2.ZERO
	var magnitude_db: float = linear2db((magnitude.x + magnitude.y) / 2)
	magnitude_db = max(magnitude_db, magnitude_db_array[key_index] - magnitude_decrease_speed * delta)
	magnitude_db_array[key_index] = magnitude_db
	var height_uniform: float = max(0.0, map_range(magnitude_db, lowest_magnitude, 0.0, 0.0, 1.0))
	var height: float = screen_size.y * height_uniform
	var width: float = screen_size.x / float(key_number) * magnitude_bar_width
	var color: Color = gradient.interpolate(x_position_uniform)
	if height_uniform < 0.5:
		color = color.darkened(map_range(height_uniform, 0.0, 0.5, 0.9, 0.0))
	else:
		color = color.lightened(map_range(height_uniform, 0.5, 0.9, 0.0, 1.0))
	draw_rect(Rect2(x_position - width / 2, (screen_size.y - height) * bar_screen_height, width, height * bar_screen_height), color)

func draw_key(key_index: int):
	var x_position: float = screen_size.x / float(key_number) * (key_index + 0.5)
	var width: float = screen_size.x / float(key_number) * piano_bar_width
	var height: float = screen_size.y * piano_bar_height
	var color: Color = Color.white
	for black_position in [1, 4, 6, 9, 11]:
		if (key_index + 12 - black_position) % 12 == 0:
			color = Color.black
	draw_rect(Rect2(x_position - width / 2, screen_size.y - height, width, height), color)

func _draw():
	draw_rect(Rect2(0, 0, screen_size.x, screen_size.y), Color.black)
	for key_index in range(0, key_number):
		draw_magnitude(key_index)
		draw_key(key_index)

func initialize_values():
	$Control/startstop.disabled = false
	$Control/reset.disabled = false
	$Control/minus1.disabled = false
	$Control/plus1.disabled = false
	$Control/minus5.disabled = false
	$Control/plus5.disabled = false
	$AudioStreamPlayer.stop()
	playing = false
	play_position = 0.0
	stream_length = $AudioStreamPlayer.stream.get_length()
	$Control/TimeBar.max_value = stream_length
	$Control/TimeBar.value = play_position
	$Control/startstop.pressed = false

func viewport_size_changed():
	screen_size = get_viewport().size
	$Control.rect_size = screen_size

func _ready():
	get_tree().get_root().connect("size_changed", self, "viewport_size_changed")
	viewport_size_changed()
	for key_index in range(0, key_number):
		magnitude_db_array.append(lowest_magnitude)


func _process(_delta):
	delta = _delta
	if file_chosen:
		var stream_playing: bool = $AudioStreamPlayer.playing
		if playing and not scrubbing:
			var reached_end: bool = play_position >= stream_length - 0.1
			if not stream_playing and not reached_end:
				$AudioStreamPlayer.play(play_position)
			if reached_end:
				$AudioStreamPlayer.stop()
			play_position = $AudioStreamPlayer.get_playback_position()
			$Control/TimeBar.value = play_position
		elif playing and scrubbing:
			if stream_playing:
				$AudioStreamPlayer.stop()
			play_position = $Control/TimeBar.value
			scrubbing = false
		elif not playing and scrubbing:
			play_position = $Control/TimeBar.value
			scrubbing = false
	var minutes: int = floor(play_position / 60)
	var seconds: int = int(play_position) % 60
	$Control/Timestamp.text = "%d:%02d" % [minutes, seconds]
	update()

func _on_startstop_toggled(button_pressed):
	if button_pressed == true:
		playing = true
		$Control/startstop.text = "pause"
		$AudioStreamPlayer.play(play_position)
	else:
		playing = false
		$Control/startstop.text = "play"
		$AudioStreamPlayer.stop()

func _on_minus1_pressed():
	play_position = max(play_position - 1.0, 0.0)
	$Control/TimeBar.value = play_position
	if playing:
		$AudioStreamPlayer.play(play_position)

func _on_plus1_pressed():
	play_position = min(play_position + 1.0, stream_length)
	$Control/TimeBar.value = play_position
	if playing:
		$AudioStreamPlayer.play(play_position)

func _on_minus5_pressed():
	play_position = max(play_position - 5.0, 0.0)
	$Control/TimeBar.value = play_position
	if playing:
		$AudioStreamPlayer.play(play_position)

func _on_plus5_pressed():
	play_position = min(play_position + 5.0, stream_length)
	$Control/TimeBar.value = play_position
	if playing:
		$AudioStreamPlayer.play(play_position)

func _on_reset_pressed():
	play_position = 0.0
	$Control/TimeBar.value = play_position
	if playing:
		$AudioStreamPlayer.play(play_position)

func _on_open_pressed():
	$Control/FileDialog.popup_centered()

func _on_FileDialog_file_selected(path):
	var file = File.new()
	file.open(path, File.READ)
	var stream
	if String(path).ends_with(".ogg"):
		stream = AudioStreamOGGVorbis.new()
	elif String(path).ends_with(".mp3"):
		stream = AudioStreamMP3.new()
	stream.data = file.get_buffer(file.get_len())
	$AudioStreamPlayer.stream = stream
	file.close()
	file_chosen = true
	initialize_values()

func _on_Color1_color_changed(color):
	gradient.set_color(0, color)

func _on_Color2_color_changed(color):
	gradient.set_color(1, color)

func _on_TimeBar_scrolling():
	scrubbing = true
