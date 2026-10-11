extends Node
# GameConfig.gd — Autoload (Singleton) اسمه "GameConfig"
# بيتحكم في وضع اللعبة: أونلاين (متصل بسيرفر Nakama حقيقي) أو أوفلاين (كله محلي على الجهاز)
# القيم دي بتتحفظ في ملف عشان تفضل زي ما هي بين مرة وتانية من غير ما تعدّل كود

const CONFIG_PATH := "user://game_config.cfg"

# النسخة الحالية: أوفلاين + LAN فقط. الأونلاين (Nakama) متقفل لحد ما يجهز موديول السيرفر.
# لما تجهز سيرفرك: غيّرها true وهيظهر قسم السيرفر في شاشة الاتصال.
const ONLINE_ENABLED := false

var offline_mode: bool = true       # true = يلعب من غير سيرفر خالص (تجربة/عرض/بدون إنترنت)
var server_host: String = "127.0.0.1"
var server_port: int = 7350
var server_use_ssl: bool = false
var server_key: String = "defaultkey"

# فترة انتظار قبل ما يعتبر إن السيرفر مش موجود ويرجع أوفلاين تلقائياً
const CONNECT_TIMEOUT_SEC := 6.0


func _ready() -> void:
	load_config()


func load_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		save_config()  # أول مرة تشتغل اللعبة: يبني ملف افتراضي (أوفلاين)
		return
	offline_mode = cfg.get_value("network", "offline_mode", true)
	server_host = cfg.get_value("network", "server_host", "127.0.0.1")
	server_port = cfg.get_value("network", "server_port", 7350)
	server_use_ssl = cfg.get_value("network", "server_use_ssl", false)
	server_key = cfg.get_value("network", "server_key", "defaultkey")
	if not ONLINE_ENABLED:
		offline_mode = true


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("network", "offline_mode", offline_mode)
	cfg.set_value("network", "server_host", server_host)
	cfg.set_value("network", "server_port", server_port)
	cfg.set_value("network", "server_use_ssl", server_use_ssl)
	cfg.set_value("network", "server_key", server_key)
	cfg.save(CONFIG_PATH)


func set_offline_mode(value: bool) -> void:
	offline_mode = value
	save_config()


func set_server(host: String, port: int, use_ssl: bool = false, key: String = "defaultkey") -> void:
	server_host = host
	server_port = port
	server_use_ssl = use_ssl
	server_key = key
	offline_mode = false
	save_config()
