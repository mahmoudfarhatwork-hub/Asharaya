class_name TouchCircle
extends Control
# TouchCircle.gd — دايرة بتتفرد (جويستيك/زر) مع كلمة صغيرة جواها.

var circle_color: Color = Color(1, 1, 1, 0.25)
var label_text: String = ""


func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, size.x / 2.0, circle_color)
	draw_arc(c, size.x / 2.0 - 2.0, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 3.0)
	if label_text != "":
		var font := ThemeDB.fallback_font
		var fs := int(size.x * 0.26)
		var ts := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, Vector2((size.x - ts.x) / 2.0, size.y / 2.0 + fs * 0.35), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)
