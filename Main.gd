extends Node2D

var screen_size: Vector2

var key_number: int = 88
var lowest_frequency: float = 27.5
var magnitude_db_array = []
var smooth: bool = true
var averaging_frames: int = 4
var smoothing_disable_distance: float = 10.0
var filter: bool = false
var filtered_magnitude_array = []
var filter_max_difference: float = 0.1
var filter_appear_speed: float = 0.1
var filter_disappear_speed: float = 0.2
var lowest_magnitude: float = -60.0
var absolute_lowest_magnitude: float = -80.0
var magnitude_decrease_speed: float = 1.5 * lowest_magnitude

var color_array = []
enum ColorMode {USER, GRADIENT_CHANGE, SINGLE_CHANGE, RAINBOW}
var color_mode = ColorMode.USER
var time: float = 0.0
var color_change_speed: float = 60

var magnitude_bar_width: float = 0.4
export var gradient: Gradient
var tilt_amount: float = 0.0

var line_opacity: float = 0.0
export var line_color: Color
var line_appear_time: float = 0.2
var line_disappear_time: float = 0.5
var line_display_timer: float = 0.0
var line_display_duration: float = 1.0

var key_white_array = [] # stores information of key color (true if white)
var piano_bar_height: float = 0.15
var piano_bar_width: float = 0.9
onready var bar_screen_height: float = 1.0 - piano_bar_height
export var white_key_color: Color
export var black_key_color: Color
var white_key_height: float = 0.8
var black_key_height: float = 0.5
var c_length: float = 0.05
export var c_color: Color
export var middle_c_color: Color

# chord analysis stuff
var chord_key_array = [] # stores the frequency of pressed keys grouped by pitch
export var chord_key_default_color: Color
export var chord_key_activated_color: Color
export var chord_key_topthree_color: Color
var key_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
var invalid_chord: String = "---"
var chord: String = invalid_chord
var last_chord: String = invalid_chord
const FIRST: int = 0
const MIDDLE: int = 1
const LAST: int = 2
var chord_chart = {2: {7: ["sus2", FIRST, "sus4", LAST]},
3: {8: ["maj", LAST], 7: ["min", FIRST], 6: ["dim", FIRST], 9: ["dim", LAST]},
4: {7: ["maj", FIRST], 9: ["min", LAST], 8: ["aug", FIRST, "aug", LAST, "aug", MIDDLE]},
5: {9: ["maj", MIDDLE], 8: ["min", MIDDLE], 10: ["sus2", LAST, "sus4", MIDDLE], 7: ["sus2", MIDDLE, "sus4", FIRST]},
6: {9: ["dim", MIDDLE]}}

var delta: float = 1.0 / 60.0
var spectrum: AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(1, 0)
var stream_length: float = 0.0

var file_chosen: bool = false
var play_position: float = 0.0
var end_cut_multiply: float = 0.0005
var end_cut_constant: float = 0.1
var playing_mode: bool = false
var scrubbing: bool = false
var loop: bool = false
var reached_end: bool = false

enum HideState {NONE, UI, BOTH}
var hide_state = HideState.NONE
var button_visible: bool = true

var actual_volume: float = 1.0

func map_range(value, source_start, source_end, target_start, target_end):
	var mapped_value: float = value - source_start
	if source_start != source_end:
		mapped_value *= (target_end - target_start) / (source_end - source_start)
		mapped_value += target_start
	else: # source range is zero
		mapped_value = target_start
	return mapped_value

func linear_interpolate(factor: float, value_1, value_2):
	return (1.0 - factor) * value_1 + factor * value_2

func initialize_values():
	$Control/startstop.disabled = false
	$Control/reset.disabled = false
	$Control/minus1.disabled = false
	$Control/plus1.disabled = false
	$Control/minus5.disabled = false
	$Control/plus5.disabled = false
	$AudioStreamPlayer.stop()
	playing_mode = false
	play_position = 0.0
	stream_length = $AudioStreamPlayer.stream.get_length()
	stream_length -= max(stream_length * end_cut_multiply, end_cut_constant) # make it a bit smaller because $AudioStreamPlayer.stream.get_length() seems a bit longer for some reason
	$Control/TimeBar.max_value = stream_length
	$Control/TimeBar.value = play_position
	$Control/startstop.pressed = false

func change_time(new_time):
	play_position = clamp(new_time, 0.0, stream_length)
	$Control/TimeBar.value = play_position
	$AudioStreamPlayer.seek(play_position)

func import_mp3(path: String):
	var file = File.new()
	file.open(path, File.READ)
	var stream = AudioStreamMP3.new()
	stream.data = file.get_buffer(file.get_len())
	return stream

func import_ogg(path: String):
	var file = File.new()
	file.open(path, File.READ)
	var stream = AudioStreamOGGVorbis.new()
	stream.data = file.get_buffer(file.get_len())
	file.close()
	return stream

func control_playback():
	if file_chosen:
		reached_end = play_position >= stream_length
		var stream_playing: bool = $AudioStreamPlayer.playing
		if not scrubbing:
			if playing_mode:
				if not stream_playing:
					if not reached_end:
						$AudioStreamPlayer.play(play_position)
					elif reached_end and loop:
						$AudioStreamPlayer.play(0.0)
				elif stream_playing and reached_end:
					if loop:
						$AudioStreamPlayer.play(0.0)
					else:
						$AudioStreamPlayer.stop()
			elif not playing_mode and stream_playing:
				$AudioStreamPlayer.stop()
			play_position = $AudioStreamPlayer.get_playback_position()
			$Control/TimeBar.value = play_position
		elif scrubbing:
			if playing_mode and stream_playing:
				$AudioStreamPlayer.stop()
			play_position = $Control/TimeBar.value
			$AudioStreamPlayer.seek(play_position)
			scrubbing = false

func color_from_hue(hue: float):
	return Color.from_hsv(hue - floor(hue), 1.0, 1.0)

func update_colors():
	match color_mode:
		ColorMode.USER:
			for key_index in range(0, key_number):
				var x_position_uniform: float = 1.0 / key_number * (key_index + 0.5)
				color_array[key_index] = gradient.interpolate(x_position_uniform)
		ColorMode.GRADIENT_CHANGE:
			var hue_1: float = time / color_change_speed
			var hue_2: float = hue_1 + 1.0 / 3.0
			gradient.set_color(0, color_from_hue(hue_1))
			gradient.set_color(1, color_from_hue(hue_2))
			for key_index in range(0, key_number):
				var x_position_uniform: float = 1.0 / key_number * (key_index + 0.5)
				var color: Color = color_from_hue(gradient.interpolate(x_position_uniform).h)
				color = color.lightened(map_range(abs(x_position_uniform - 0.5), 0.0, 0.5, 0.5, 0.0))
				color_array[key_index] = color
		ColorMode.SINGLE_CHANGE:
			var hue: float = time / color_change_speed + 2.0 / 3.0
			var color: Color = color_from_hue(hue).lightened(0.4)
			for key_index in range(0, key_number):
				color_array[key_index] = color
		ColorMode.RAINBOW:
			for key_index in range(0, key_number):
				var x_position_uniform: float = 1.0 / key_number * (key_index + 0.5)
				var hue: float = x_position_uniform + time / color_change_speed
				color_array[key_index] = color_from_hue(color_from_hue(hue).h).lightened(0.2)

func change_speed(speed: float):
	if speed == 1.0:
		$AudioStreamPlayer.bus = "Analyze"
		$AudioStreamPlayer.pitch_scale = 1.0
	else:
		$AudioStreamPlayer.bus = "PitchShifted"
		$AudioStreamPlayer.pitch_scale = speed
		AudioServer.get_bus_effect(2, 0).pitch_scale = 1.0 / speed

func change_button_visibility():
	if button_visible:
		$ControlHide/HideRegion/hide.modulate.a = 1.0
	else:
		$ControlHide/HideRegion/hide.modulate.a = 0.0

func analyze_frequencies():
	if not $AudioStreamPlayer.playing:
		# stop processing when paused, so that it appears frozen
		return
	
	for key_index in range(0, key_number):
		var frequency_start: float = lowest_frequency * pow(2.0, (1.0 / 12.0) * (key_index - 0.5))
		var frequency_end: float = lowest_frequency * pow(2.0, (1.0 / 12.0) * (key_index + 0.5))
		var magnitude: Vector2 = spectrum.get_magnitude_for_frequency_range(frequency_start, frequency_end, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
		if not $AudioStreamPlayer.playing: # do this or weird stuff will happend while paused (spooky)
			magnitude = Vector2.ZERO
		var magnitude_db: float = linear2db((magnitude.x + magnitude.y) / 2)
		
		# tilt magnitude
		magnitude_db += map_range(key_index, 0, key_number - 1, -tilt_amount, tilt_amount)
		
		# fix infinity errors when magnitude is 0
		if magnitude_db == -INF:
			magnitude_db = absolute_lowest_magnitude
		
		# average values over several frames
		var sum: float = magnitude_db
		for frame in averaging_frames - 1:
			var copied_value: float = magnitude_db_array[key_index][frame + 1]
			magnitude_db_array[key_index][frame] = copied_value
			sum += copied_value
		if smooth:
			var average: float = sum / averaging_frames
			var difference: float = magnitude_db - magnitude_db_array[key_index][averaging_frames - 2]
			difference = clamp(map_range(difference, 0.0, 20.0, 0.0, 1.0), 0.0, 1.0)
			# do this so that sudden increases in magnitudes aren't smoothed out
			magnitude_db = linear_interpolate(difference, average, magnitude_db)
#			magnitude_db = average
		magnitude_db_array[key_index][averaging_frames - 1] = magnitude_db
		
		# gradually decrease value to make it less jumpy
		magnitude_db = max(magnitude_db_array[key_index][averaging_frames - 2] + magnitude_decrease_speed * delta, magnitude_db)
		magnitude_db = max(absolute_lowest_magnitude, magnitude_db)
		magnitude_db_array[key_index][averaging_frames - 1] = magnitude_db
	
	# analyze peak frequencies
	for key_index in range(1, key_number - 1):
		var center_value: float = magnitude_db_array[key_index][averaging_frames - 1]
		var left_value: float = magnitude_db_array[key_index - 1][averaging_frames - 1]
		var right_value: float = magnitude_db_array[key_index + 1][averaging_frames - 1]
		if center_value >= left_value - filter_max_difference and center_value >= right_value - filter_max_difference:
			filtered_magnitude_array[key_index] = min(1.0, filtered_magnitude_array[key_index] + 1.0 / filter_appear_speed * delta)
		else:
			filtered_magnitude_array[key_index] = max(0.0, filtered_magnitude_array[key_index] - 1.0 / filter_disappear_speed * delta)

func analyze_chord():
	# summerize notes over octaves
	var threshold_magnitude: float = lowest_magnitude - absolute_lowest_magnitude
	for chord_key_index in 12: # add up the magnitude of same notes through different octaves
		chord_key_array[chord_key_index] = 0
		for original_key_index in 7: # number of full octaves
			var current_key_index: int = 3 + chord_key_index + (original_key_index * 12) # only use keys in octave 1 to 7 (discarding 0 and 8)
			var current_magnitude: float = (magnitude_db_array[current_key_index][averaging_frames - 1] - absolute_lowest_magnitude) * filtered_magnitude_array[current_key_index]
			chord_key_array[chord_key_index] += max(current_magnitude - threshold_magnitude, 0)
	var max_magnitude: float = chord_key_array.max()
	for chord_key_index in 12: # convert range to 0-1
		var new_value: float = chord_key_array[chord_key_index]
		new_value = map_range(new_value, 0, max_magnitude, 0, 1)
		chord_key_array[chord_key_index] = new_value
	
	# get triad and figure out chord
	var sorted_chord_key_array = chord_key_array.duplicate()
	sorted_chord_key_array.sort() # sort from lowest to highest
	var triad_values = [sorted_chord_key_array[11], sorted_chord_key_array[10], sorted_chord_key_array[9]]
	if triad_values.min() == 0: # invalid triad
		chord = invalid_chord
	else:
		var triad_keys = [chord_key_array.find(triad_values[0]), chord_key_array.find(triad_values[1]), chord_key_array.find(triad_values[2])]
		triad_keys.sort() # sort by key index
		
		var chord_info = chord_chart.get(triad_keys[1] - triad_keys[0], {}).get(triad_keys[2] - triad_keys[0], [])
		chord = ""
		if chord_info.size() != 0:
			for chord_index in chord_info.size() / 2:
				var chord_name: String = chord_info[chord_index * 2]
				var chord_start_key: int = chord_info[chord_index * 2 + 1]
				if chord_index > 0:
					chord += " / "
				chord += key_names[triad_keys[chord_start_key]] + chord_name
		else:
			chord = invalid_chord

func draw_magnitude():
	for key_index in range(0, key_number):
		var magnitude: float = magnitude_db_array[key_index][averaging_frames - 1]
		var x_position_uniform: float = 1.0 / key_number * (key_index + 0.5)
		var x_position: float = screen_size.x * x_position_uniform
		var height_uniform: float = max(0.0, map_range(magnitude, lowest_magnitude, 0.0, 0.0, 1.0))
		var height: float = screen_size.y * height_uniform
		var width: float = screen_size.x / float(key_number) * magnitude_bar_width
		var color: Color = color_array[key_index]
		var alpha: float = 1.0
		if height_uniform < 0.5:
			alpha *= map_range(height_uniform, 0.0, 0.5, 0.1, 1.0)
		else:
			color = color.lightened(map_range(height_uniform, 0.5, 1.0, 0.0, 1.0))
		if filter:
			alpha *= map_range(filtered_magnitude_array[key_index], 0.0, 1.0, 0.2, 1.0)
		color.a = alpha
		draw_rect(Rect2(x_position - width / 2, (screen_size.y - height) * bar_screen_height, width, height * bar_screen_height), color)

func draw_lines():
	# calculate line opacity
	if line_display_timer > 0.0:
		line_display_timer -= delta
		line_opacity += 1.0 / line_appear_time * delta
	else:
		line_opacity -= 1.0 / line_disappear_time * delta
	line_opacity = clamp(line_opacity, 0.0, 1.0)
	var color: Color = line_color
	color.a = line_opacity
	
	# draw lines from -120dB to 50dB
	for db in range(-120, 40, 20):
		var line_height_left = screen_size.y * map_range(db - tilt_amount, lowest_magnitude, 0.0, 1.0, 0.0) * bar_screen_height
		var line_height_right = screen_size.y * map_range(db + tilt_amount, lowest_magnitude, 0.0, 1.0, 0.0) * bar_screen_height
		draw_line(Vector2(0.0, line_height_left), Vector2(screen_size.x, line_height_right), color, 2.0, true)
	draw_rect(Rect2(0, screen_size.y * bar_screen_height, screen_size.x, screen_size.y), Color.black) # hide lower portion of screen

func draw_key():
	for key_index in range(0, key_number):
		var x_position: float = screen_size.x / float(key_number) * (key_index + 0.5)
		var width: float = screen_size.x / float(key_number) * piano_bar_width
		var height: float = screen_size.y * piano_bar_height
		# calculate the colour
		var magnitude: float = magnitude_db_array[key_index][averaging_frames - 1]
		var magnitude_normalized: float = clamp(map_range(magnitude, lowest_magnitude, 0.0, 0.0, 2.0), 0.0, 2.0)
		var emit_color: Color = color_array[key_index]
		if magnitude_normalized >= 1.0:
			emit_color = emit_color.lightened(map_range(magnitude_normalized, 1.0, 2.0, 0.0, 1.0))
		var factor: float = filtered_magnitude_array[key_index] * min(magnitude_normalized, 1.0)
		if key_white_array[key_index]:
			var final_color: Color = white_key_color.linear_interpolate(emit_color, factor)
			draw_rect(Rect2(x_position - width / 2, screen_size.y - height, width, height), white_key_color)
			draw_rect(Rect2(x_position - width / 2, screen_size.y - height, width, height * white_key_height), final_color)
		else:
			var final_color: Color = black_key_color.linear_interpolate(emit_color, factor)
			draw_rect(Rect2(x_position - width / 2, screen_size.y - height, width, height), black_key_color)
			draw_rect(Rect2(x_position - width / 2, screen_size.y - height, width, height * black_key_height), final_color)

func draw_c():
	var height: float = screen_size.y * piano_bar_height * c_length
	var width: float = screen_size.x / float(key_number) * piano_bar_width
	for c_index in 8:
		var key_index: int = 3 + c_index * 12
		var x_position: float = screen_size.x / float(key_number) * (key_index + 0.5)
		if c_index != 3:
#			draw_circle(Vector2(x_position, y_position), radius, circle_color)
			draw_rect(Rect2(x_position - width / 2, screen_size.y - height, width, height), c_color)
		else:
#			draw_circle(Vector2(x_position, y_position), radius, center_circle_color)
			draw_rect(Rect2(x_position - width / 2, screen_size.y - height, width, height), middle_c_color)

func draw_chord_keys():
	var sorted_chord_key_array = chord_key_array.duplicate()
	sorted_chord_key_array.sort() # sort from lowest to highest
	var third_highest: float = sorted_chord_key_array[9] # third highest value 
	var chord_keys = $Control/chord_keys
	for key_index in 12:
		var current_value: float = chord_key_array[key_index]
		if current_value >= third_highest:
			chord_keys.get_node(str(key_index)).modulate = chord_key_default_color.linear_interpolate(chord_key_topthree_color, current_value)
		else:
			chord_keys.get_node(str(key_index)).modulate = chord_key_default_color.linear_interpolate(chord_key_activated_color, current_value)
	$Control/chord_name.text = chord
	if chord != last_chord: # fade in text if chord has changed
		$Control/chord_tween.interpolate_property($Control/chord_name, "self_modulate", Color(1, 1, 1, 0), Color(1, 1, 1, 1), 0.2, Tween.TRANS_CIRC, Tween.EASE_IN_OUT)
		$Control/chord_tween.start()
	last_chord = chord

func _draw():
	update_colors()
	draw_rect(Rect2(0, 0, screen_size.x, screen_size.y), Color.black)
	draw_lines()
	draw_magnitude()
	draw_chord_keys()
	if hide_state != HideState.BOTH:
		draw_key()
		draw_c()

func viewport_size_changed():
	screen_size = get_viewport().size
	$Control.rect_size = screen_size
	$ControlHide.rect_size = screen_size
	if hide_state != HideState.NONE:
		$Control.rect_position.x = screen_size.x

func _ready():
	# make viewport resize detectable
	get_tree().get_root().connect("size_changed", self, "viewport_size_changed")
	viewport_size_changed()
	
	# initialize arrays
	for key_index in range(0, key_number):
		var values = []
		for frame in averaging_frames:
			values.append(absolute_lowest_magnitude)
		magnitude_db_array.append(values)
		
		filtered_magnitude_array.append(0)
		
		key_white_array.append(true)
		for black_position in [1, 4, 6, 9, 11]:
			if (key_index + 12 - black_position) % 12 == 0:
				key_white_array[key_index] = false
		
		var x_position_uniform: float = 1.0 / key_number * (key_index + 0.5)
		color_array.append(gradient.interpolate(x_position_uniform))
	
	for key_index in 12:
		chord_key_array.append(0)

func _process(_delta):
	delta = _delta
	time += delta
	
	control_playback()
	
	# display time position
	var minutes: int = int(floor(play_position / 60))
	var seconds: int = int(play_position) % 60
	$Control/Timestamp.text = "%d:%02d" % [minutes, seconds]
	
	analyze_frequencies()
	analyze_chord()
	update()
	
	change_button_visibility()
#	print(magnitude_db_array[40])
#	print(play_position)

func _on_startstop_toggled(button_pressed):
	if button_pressed == true:
		playing_mode = true
		$Control/startstop.text = "pause"

	else:
		playing_mode = false
		$Control/startstop.text = "play"

func _on_minus1_pressed():
	change_time(play_position - 1.0)

func _on_plus1_pressed():
	change_time(play_position + 1.0)

func _on_minus5_pressed():
	change_time(play_position - 5.0)

func _on_plus5_pressed():
	change_time(play_position + 5.0)

func _on_reset_pressed():
	change_time(0.0)

func _on_open_pressed():
	$Control/FileDialog.popup_centered()

func _on_FileDialog_file_selected(path):
	if String(path).ends_with(".ogg"):
		$AudioStreamPlayer.stream = import_ogg(path)
	elif String(path).ends_with(".mp3"):
		$AudioStreamPlayer.stream = import_mp3(path)
	file_chosen = true
	$Control/filename.text = path
	initialize_values()

func _on_Color1_color_changed(color):
	gradient.set_color(0, color)

func _on_Color2_color_changed(color):
	gradient.set_color(1, color)

func _on_TimeBar_scrolling():
	scrubbing = true

func _on_smooth_toggled(button_pressed):
	if button_pressed:
		smooth = true
	else:
		smooth = false

func _on_min_dB_value_changed(value):
	lowest_magnitude = value
	magnitude_decrease_speed = 1.5 * lowest_magnitude
	line_display_timer = line_display_duration

func _on_filter_toggled(button_pressed):
	if button_pressed:
		filter = true
	else:
		filter = false

func _on_chord_toggled(button_pressed):
	if button_pressed:
		$Control/chord_keys.visible = true
		$Control/chord_name.visible = true
	else:
		$Control/chord_keys.visible = false
		$Control/chord_name.visible = false

func _on_tilt_value_changed(value):
	tilt_amount = value
	line_display_timer = line_display_duration

func _on_loop_toggled(button_pressed):
	if button_pressed:
		loop = true
	else:
		loop = false

# release focus from text fields when mouse exits them, so that shortcut keys work corecctly
func _on_min_dB_mouse_exited():
	$Control/min_dB.get_line_edit().release_focus()

func _on_tilt_mouse_exited():
	$Control/tilt.get_line_edit().release_focus()

func _on_hide_pressed():
	match hide_state:
		HideState.NONE:
			hide_state = HideState.UI
			$Control.rect_position.x = screen_size.x
			if $ControlHide/HideRegion/hide.is_hovered():
				button_visible = true
			else:
				button_visible = false
			$ControlHide/HideRegion/hide.text = "hide keyboard"
		HideState.UI:
			hide_state = HideState.BOTH
			bar_screen_height = 1.0
			if $ControlHide/HideRegion/hide.is_hovered():
				button_visible = true
			else:
				button_visible = false
			$ControlHide/HideRegion/hide.text = "unhide all"
		HideState.BOTH:
			hide_state = HideState.NONE
			$Control.rect_position.x = 0
			bar_screen_height = 1.0 - piano_bar_height
			button_visible = true
			$ControlHide/HideRegion/hide.text = "hide UI"

func _on_full_screen_toggled(button_pressed):
	if button_pressed:
		OS.window_fullscreen = true
	else:
		OS.window_fullscreen = false

func _on_volume_value_changed(value):
	# make volume control sound as linear as possible
	var clamped_value: float = clamp(value, 0.0, 1.0)
	var volume_db: float = map_range(pow(clamped_value, 0.25), 0.0, 1.0, -80.0, 0.0)
	AudioServer.set_bus_volume_db(0, volume_db)
	if value != -1.0: # record value when not muted
		actual_volume = value

func _on_mute_toggled(button_pressed):
	if button_pressed:
		$Control/volume.value = -1.0
	else:
		$Control/volume.value = actual_volume

func _on_color_pressed():
	match color_mode:
		ColorMode.USER:
			color_mode = ColorMode.GRADIENT_CHANGE
		ColorMode.GRADIENT_CHANGE:
			color_mode = ColorMode.SINGLE_CHANGE
		ColorMode.SINGLE_CHANGE:
			color_mode = ColorMode.RAINBOW
		ColorMode.RAINBOW:
			color_mode = ColorMode.USER
			gradient.set_color(0, $Control/Color1.color)
			gradient.set_color(1, $Control/Color2.color)

func _on_HideRegion_mouse_entered():
	if hide_state != HideState.NONE:
		button_visible = true

func _on_HideRegion_mouse_exited():
	if hide_state != HideState.NONE:
		button_visible = false

func _on_OptionButton_item_selected(index):
	match index:
		0: # speed is 2.0
			change_speed(2.0)
		1: # speed is 1.5
			change_speed(1.5)
		2: # speed is 1.0
			change_speed(1.0)
		3: # speed is 0.8
			change_speed(0.8)
		4: # speed is 0.5
			change_speed(0.5)
