extends SceneTree
# tests/currency_selftest.gd — اختبار نظام العملات:
#   godot --headless --path godot_project_FINAL --script res://tests/currency_selftest.gd

var passed: int = 0
var failed: int = 0
var CS = load("res://scripts/CurrencySystem.gd")


func _initialize() -> void:
	_test_conversion()
	_test_spend()
	_test_negative_amounts()
	_test_load_state()
	print("CURRENCY SELFTEST: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", label)


func _fresh():
	var c = CS.new()
	for k in c.wallet.keys():
		c.wallet[k] = 0
	return c


func _test_conversion() -> void:
	var c = _fresh()
	c.add_iron_value(10)
	check(c.wallet[CS.Coin.COPPER] == 1 and c.wallet[CS.Coin.IRON] == 0, "10 iron becomes 1 copper")
	c.add_iron_value(1000000 - 10)
	check(c.wallet[CS.Coin.ROYAL_GOLD] == 1, "1,000,000 iron is 1 royal gold")
	check(c.total_in_iron() == 1000000, "total value is preserved")
	var d = _fresh()
	d.add_iron_value(300000000)
	check(d.wallet[CS.Coin.DIAMOND] == 1, "300,000,000 iron is 1 diamond")


func _test_spend() -> void:
	var c = _fresh()
	c.add_iron_value(1500)
	check(c.try_spend_iron_value(700), "spending within balance succeeds")
	check(c.total_in_iron() == 800, "balance is reduced correctly")
	check(not c.try_spend_iron_value(801), "overspending fails")
	check(c.total_in_iron() == 800, "failed spend does not change balance")


func _test_negative_amounts() -> void:
	var c = _fresh()
	c.add_iron_value(100)
	check(not c.try_spend_iron_value(-500), "negative spend is rejected")
	check(c.total_in_iron() == 100, "negative spend does not create money")
	c.add_iron_value(-9999)
	check(c.total_in_iron() == 100, "negative add is ignored")
	c.add_coins(CS.Coin.GOLD, -5)
	check(c.total_in_iron() == 100, "negative coin add is ignored")
	check(c.try_spend_iron_value(0), "spending zero is allowed")


func _test_load_state() -> void:
	var c = _fresh()
	c.load_state({"0": -50, "1": "abc", "2": 3.7, "3": 99999999999999})
	for k in c.wallet.keys():
		check(typeof(c.wallet[k]) == TYPE_INT and c.wallet[k] >= 0, "loaded wallet value %s is a non-negative int" % str(k))
	check(c.total_in_iron() < 9223372036854775807 and c.total_in_iron() >= 0, "loaded total does not overflow")
