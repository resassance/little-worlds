class_name GamePlatform
extends Node

signal suspension_changed(suspended: bool)
signal message(text: String)
signal cloud_loaded(world: WorldState)
signal reward_received
var playing := false
var available := false
var polling := 0.0

func call_js(method: String, argument: String = "") -> Variant:
	if not OS.has_feature("web"): return null
	return JavaScriptBridge.eval("window.LittleWorldsPlatform && window.LittleWorldsPlatform.%s(%s)" % [method,JSON.stringify(argument)],true)

func _ready() -> void:
	if OS.has_feature("web"):

		JavaScriptBridge.eval(FileAccess.get_file_as_string("res://platform/yandex_bridge.js"),true)
		call_js("ready")

func gameplay(value: bool) -> void:
	if playing == value: return
	playing=value
	call_js("gameplay","start" if value else "stop")

func _process(delta: float) -> void:
	if not OS.has_feature("web"): return
	polling += delta
	if polling < .1: return
	polling=0
	var raw: Variant=call_js("poll")
	if not raw is String: return
	var events: Variant=JSON.parse_string(raw)
	if not events is Array: return
	for event in events:
		if not event is Dictionary: continue
		match event.get("kind",""):
			"available": available=true
			"suspend": suspension_changed.emit(bool(event.get("value",false)))
			"message": message.emit(str(event.get("text","")))
			"reward": reward_received.emit()
			"cloud":
				var encoded: String=event.get("data","")
				if encoded.length()>200000: continue
				var bytes:=Marshalls.base64_to_raw(encoded).decompress_dynamic(SaveStore.MAX_SAVE_BYTES,FileAccess.COMPRESSION_GZIP)
				var data: Variant=JSON.parse_string(bytes.get_string_from_utf8())
				var restored: WorldState=WorldState.from_dict(data) if data is Dictionary else null
				if restored==null: message.emit("Облачное сохранение повреждено. Текущий мир сохранён в памяти.")
				else: cloud_loaded.emit(restored)

func save_cloud(world: WorldState) -> void:
	if not available:
		message.emit("Облачное сохранение доступно при запуске в Яндекс Играх."); return
	var data:=world.to_dict()
	if data.is_empty(): message.emit("Не удалось прочитать карту для облака."); return
	var raw:=JSON.stringify(data).to_utf8_buffer()
	if raw.size()>SaveStore.MAX_SAVE_BYTES:
		message.emit("Мир превышает размер облачного снимка. Локальное сохранение доступно."); return
	var encoded:=Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP))
	if encoded.length()>180000:
		message.emit("Мир превышает размер облачной записи. Локальное сохранение доступно."); return
	call_js("save",encoded)

func load_cloud() -> void:
	if available: call_js("load")
	else: message.emit("Облачное сохранение доступно при запуске в Яндекс Играх.")

func rewarded() -> void:
	if available: call_js("rewarded")
	else: message.emit("Видео доступно при запуске в Яндекс Играх.")
