extends SceneTree
# tests/net_security_selftest.gd — اختبار أمن الشبكة (بدون واجهة):
#   godot --headless --path godot_project_FINAL --script res://tests/net_security_selftest.gd
# بيرجّع exit code = 1 لو أي اختبار فشل.

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	_test_device_id()
	_test_lan_identity()
	_test_state_sanitizer()
	_test_text_sanitizers()
	_test_source_guards()
	print("NET SECURITY SELFTEST: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _test_device_id() -> void:
	var a: String = NetSecurity.make_device_id()
	var b: String = NetSecurity.make_device_id()
	check(a.length() >= 32, "device id is at least 32 chars")
	check(a != b, "two device ids differ")
	check(a.is_valid_hex_number(false), "device id is hex")
	check(not a.begins_with("player_"), "device id is not the old timestamp format")


func _test_lan_identity() -> void:
	check(NetSecurity.lan_uid(7) == "lan_7", "lan uid is derived from the sender peer id")
	check(NetSecurity.lan_uid(0) == "", "peer id 0 is rejected")
	check(NetSecurity.lan_uid(-3) == "", "negative peer id is rejected")


func _test_state_sanitizer() -> void:
	var raw := {
		"x": 12.5, "y": 1.0, "z": -3.0, "rotY": 1.2,
		"hp": 50, "maxHp": 100, "level": 3,
		"userId": "lan_999", "username": "[b]victim[/b]", "evil": "drop table",
	}
	var s: Dictionary = NetSecurity.sanitize_lan_state(raw)
	check(not s.has("userId") and not s.has("username"), "identity keys from the client are dropped")
	check(not s.has("evil"), "unknown keys are dropped")
	check(is_equal_approx(float(s.get("x", -1)), 12.5), "valid position is kept")
	check(int(s.get("hp", -1)) == 50, "valid hp is kept")
	var bad := {"x": INF, "y": NAN, "z": 1.0e12, "hp": -5, "maxHp": 99999999, "level": 100000, "rotY": "abc"}
	var t: Dictionary = NetSecurity.sanitize_lan_state(bad)
	check(is_finite(float(t.get("x", 0.0))), "infinite x is neutralized")
	check(is_finite(float(t.get("y", 0.0))), "NaN y is neutralized")
	check(absf(float(t.get("z", 0.0))) <= NetSecurity.MAX_COORD, "huge z is clamped")
	check(int(t.get("hp", 0)) >= 0, "negative hp is clamped to 0")
	check(int(t.get("maxHp", 0)) <= NetSecurity.MAX_HP, "huge maxHp is clamped")
	check(int(t.get("level", 0)) <= NetSecurity.MAX_LEVEL, "huge level is clamped")
	check(typeof(t.get("rotY", 0.0)) == TYPE_FLOAT, "non-numeric rotY becomes a float")
	var u: Dictionary = NetSecurity.sanitize_lan_state({"hp": 500, "maxHp": 100})
	check(int(u.get("hp", 0)) <= int(u.get("maxHp", 0)), "hp never exceeds maxHp")


func _test_text_sanitizers() -> void:
	check(NetSecurity.escape_bbcode("[b]hi[/b]").find("[b]") == -1, "bbcode tags are escaped")
	check(NetSecurity.escape_bbcode("[url=http://x]a[/url]").find("[url") == -1, "url tag is escaped")
	check(NetSecurity.escape_bbcode("hello") == "hello", "plain text is unchanged")
	check(NetSecurity.sanitize_username("  [b]Ali[/b]  ").find("[") == -1, "username has no bbcode")
	check(NetSecurity.sanitize_username("A".repeat(100)).length() <= NetSecurity.MAX_NAME, "username is length-limited")
	check(NetSecurity.sanitize_username("   ") == "Player", "empty username falls back to Player")
	check(NetSecurity.sanitize_chat("x".repeat(1000)).length() <= NetSecurity.MAX_CHAT, "chat is length-limited")
	var cleaned: String = NetSecurity.sanitize_chat("a\u0001b\nc\u007fd")
	var clean_ok := true
	for ch in cleaned:
		if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127:
			clean_ok = false
	check(clean_ok and cleaned.find("a") != -1 and cleaned.find("d") != -1, "control chars are removed from chat but text is kept")


# حارس انحدار على الكود نفسه (مش بديل لاختبار شبكة حقيقي، بس يمنع رجوع الثغرتين)
func _test_source_guards() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/NetworkManager.gd")
	check(src.find("get_unix_time_from_system()).replace") == -1, "device id no longer built from the clock")
	check(src.find("NetSecurity.make_device_id()") != -1, "NetworkManager uses the secure device id")
	check(src.find("get_remote_sender_id()") != -1, "LAN RPCs derive identity from the sender id")
	var chat := FileAccess.get_file_as_string("res://scripts/ChatUI.gd")
	check(chat.find("NetSecurity.escape_bbcode") != -1, "ChatUI escapes bbcode before display")
