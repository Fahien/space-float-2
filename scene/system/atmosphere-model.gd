## Chapter: A first atmosphere for planet-owned environments.
##
## The early launch harness treated air as a global Earth table. The active
## solar-system path now carries atmosphere as a Resource that a celestial body
## may own, instantiate, and leave empty when the body is airless. Earth is the
## first user; Moon and Sun remain vacuum by leaving their exported atmosphere
## field unset.
##
## The equations come from NASA Glenn's simplified metric atmosphere model. They
## describe a still vertical column: altitude in meters goes in, and standard
## temperature, pressure, or density comes out. The model does not know about
## scene nodes, wind, body rotation, weather, composition, or time of day. Those
## limits are intentional because the current drag path needs a small,
## inspectable environmental primitive before it needs a full fluid simulation.
##
## https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/earth-atmosphere-equation-metric/

class_name AtmosphereModel

extends Resource

## Sea-level standard temperature in Celsius.
const T0 := 15.04

## Temperature lapse rate in C/m.
const L := 0.00649

## Piecewise layers used by the simplified standard-atmosphere equations.
enum Zone {
	TROPOSPHERE,
	LOWER_STRATOSPHERE,
	UPPER_STRATOSPHERE
}

## Top of the troposphere in meters.
const TROPOSPHERE_HEIGHT := 11000.0

## Top of the lower stratosphere in meters.
const LOWER_STRATOSPHERE_HEIGHT := 25000.0


## Returns the atmosphere zone for an altitude in meters.
##
## Negative altitudes are clamped to sea level, which keeps underground or
## slightly interpenetrating bodies from producing nonstandard extrapolations.
func get_zone_at(altitude: float) -> int:
	var h = maxf(altitude, 0.0)
	if h < TROPOSPHERE_HEIGHT:
		return Zone.TROPOSPHERE
	elif h < LOWER_STRATOSPHERE_HEIGHT:
		return Zone.LOWER_STRATOSPHERE
	else:
		return Zone.UPPER_STRATOSPHERE


## Returns atmospheric temperature in Celsius for the given altitude.
##
## The piecewise curve follows the same altitude bands as `get_zone_at(...)` and
## clamps negative altitudes to the sea-level branch.
func get_temperature_at(altitude: float) -> float:
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
##
## Pressure is derived from the current simplified zone. Values above the model's
## last band remain mathematical extrapolations, not a validated upper-atmosphere
## or space-weather model.
func get_pressure_at(altitude: float) -> float:
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
##
## Callers should supply altitude relative to the owning body's mean radius.
## `CelestialBody3D.get_air_density_at(...)` performs that conversion for scene
## positions.
func get_density_at(altitude: float) -> float:
	var h = maxf(altitude, 0.0)
	var t = get_temperature_at(h)
	var p = get_pressure_at(h)
	return p / (0.2869 * (t + 273.1))
