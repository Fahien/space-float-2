extends GdUnitTestSuite


func test_ui_formats_orbital_values() -> void:
	var ui: Variant = auto_free(Ui.new())

	assert_str(ui._format_value("eccentricity", 0.123456)).is_equal("0.1235")
	assert_str(ui._format_value("periapsis", 123.45)).is_equal("123.5 m")
	assert_str(ui._format_value("apoapsis", null)).is_equal("N/A")
	assert_str(ui._format_value("apoapsis", INF)).is_equal("N/A")
