## Piecewise standard-atmosphere helper for the launch harness.
##
## The formulas come from NASA Glenn's simplified metric atmosphere model.
## This is intentionally a first-order environment model: altitude in,
## density/pressure/temperature out. It does not depend on scene nodes.
##
## https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/earth-atmosphere-equation-metric/

class_name AtmosphereModel

extends RefCounted

## Sea-level standard temperature in Celsius.
const T0 := 15.04

## Temperature lapse rate in C/m.
const L := 0.00649

enum Zone {
	TROPOSPHERE,
	LOWER_STRATOSPHERE,
	UPPER_STRATOSPHERE
}

const TROPOSPHERE_HEIGHT := 11000.0
const LOWER_STRATOSPHERE_HEIGHT := 25000.0

## Returns the piecewise atmosphere zone for a given altitude in meters.
static func get_zone_at(altitude: float) -> int:
	var h = maxf(altitude, 0.0)
	if h < TROPOSPHERE_HEIGHT:
		return Zone.TROPOSPHERE
	elif h < LOWER_STRATOSPHERE_HEIGHT:
		return Zone.LOWER_STRATOSPHERE
	else:
		return Zone.UPPER_STRATOSPHERE


## Returns atmospheric temperature in Celsius for the given altitude.
static func get_temperature_at(altitude: float) -> float:
	var h = maxf(altitude, 0.0)
	var zone = get_zone_at(h)
	if zone == Zone.TROPOSPHERE:
		return T0 - L * h
	elif zone == Zone.LOWER_STRATOSPHERE:
		return -56.46
	elif zone == Zone.UPPER_STRATOSPHERE:
		return -131.21 + 0.00299 * h
	else:
		return 0.0


## Returns atmospheric pressure in kilopascals for the given altitude.
static func get_pressure_at(altitude: float) -> float:
	var h = maxf(altitude, 0.0)
	var t = get_temperature_at(h)

	var zone = get_zone_at(h)
	if zone == Zone.TROPOSPHERE:
		return 101.29 * pow((t + 273.1) / 288.08, 5.256)
	elif zone == Zone.LOWER_STRATOSPHERE:
		return 22.65 * exp(1.73 - (0.000157 * h))
	elif zone == Zone.UPPER_STRATOSPHERE:
		return 2.488 * pow((t + 273.1) / 216.6, -11.388)
	else:
		return 0.0


## Returns atmospheric density in kg/m^3 for the given altitude.
static func get_density_at(altitude: float) -> float:
	var h = maxf(altitude, 0.0)
	var t = get_temperature_at(h)
	var p = get_pressure_at(h)
	return p / (0.2869 * (t + 273.1))
