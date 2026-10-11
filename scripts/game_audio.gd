class_name GameAudio
extends Node

var effects: AudioStreamPlayer
var ambience: AudioStreamPlayer
var muted := false
var preferences: GamePreferences

func setup(value: GamePreferences) -> void:
	preferences = value
	effects = AudioStreamPlayer.new(); add_child(effects)
	effects.stream = tone()
	ambience = AudioStreamPlayer.new(); add_child(ambience)
	ambience.stream = ocean()
	update_volume()
	ambience.play()

static func tone() -> AudioStreamWAV:
	var bytes := PackedByteArray()
	for i in 1600:
		var t := float(i)/16000.0
		var sample := (sin(TAU*660*t)+sin(TAU*990*t)*0.3) * exp(-t*45) * 0.18
		bytes.append_array(PackedByteArray([int(sample*32767)&255,(int(sample*32767)>>8)&255]))
	var sound := AudioStreamWAV.new()
	sound.format=AudioStreamWAV.FORMAT_16_BITS; sound.mix_rate=16000; sound.data=bytes
	return sound

static func ocean() -> AudioStreamWAV:
	var bytes := PackedByteArray()
	var random := RandomNumberGenerator.new(); random.seed=77231
	var smooth := 0.0
	for i in 64000:
		smooth=lerpf(smooth,random.randf_range(-1,1),.08)
		var wave := (0.3+0.2*sin(TAU*i/64000.0)) * smooth
		var edge := minf(1,minf(float(i)/500,float(64000-i)/500))
		var sample := int(wave*edge*32767)
		bytes.append_array(PackedByteArray([sample&255,(sample>>8)&255]))
	var sound := AudioStreamWAV.new()
	sound.format=AudioStreamWAV.FORMAT_16_BITS; sound.mix_rate=16000; sound.data=bytes
	sound.loop_mode=AudioStreamWAV.LOOP_FORWARD; sound.loop_begin=0; sound.loop_end=64000
	return sound

func update_volume() -> void:
	if effects == null: return
	effects.volume_db=linear_to_db(maxf(.00001,preferences.effects))
	ambience.volume_db=linear_to_db(maxf(.00001,preferences.ambience))
	effects.stream_paused=muted; ambience.stream_paused=muted

func click() -> void:
	if effects != null and preferences.effects > 0 and not muted: effects.play()

func set_muted(value: bool) -> void:
	muted=value; update_volume()

func _exit_tree() -> void:
	for player in [effects,ambience]:
		if is_instance_valid(player): player.stop(); player.stream=null
