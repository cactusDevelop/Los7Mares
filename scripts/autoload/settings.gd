extends Node

const SETTINGS_FILE_PATH := "user://settings.cfg"
const DEFAULT_LOCALE := "fr"
const AVAILABLE_LOCALES: Array[String] = ["fr", "en", "es"]
const DEFAULT_VOLUME := 1.0


func _ready() -> void:
	_load_locale()
	_load_volume()


func _load_locale() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE_PATH)
	var locale: String = DEFAULT_LOCALE
	if err == OK:
		locale = config.get_value("settings", "locale", DEFAULT_LOCALE)
	TranslationServer.set_locale(locale)


func set_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE_PATH)
	config.set_value("settings", "locale", locale)
	config.save(SETTINGS_FILE_PATH)


func _load_volume() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE_PATH)
	var volume: float = DEFAULT_VOLUME
	if err == OK:
		volume = config.get_value("settings", "volume", DEFAULT_VOLUME)
	_apply_volume(volume)


func set_volume(volume: float) -> void:
	_apply_volume(volume)
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE_PATH)
	config.set_value("settings", "volume", volume)
	config.save(SETTINGS_FILE_PATH)


func get_volume() -> float:
	var bus_index := AudioServer.get_bus_index("Master")
	return db_to_linear(AudioServer.get_bus_volume_db(bus_index))


func _apply_volume(volume: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(volume))
