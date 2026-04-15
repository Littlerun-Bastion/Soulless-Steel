extends Resource
class_name CoolantType

@export var coolant_name: String
@export var density: float = 1.0          # kg/L
@export var specific_heat: float = 4.18   # kJ/(kg·°C)
@export var overheat_temp: float = 100.0  # °C

## Derived — call after loading or use inline
func get_thermal_capacity_per_litre() -> float:
	# kJ/°C per litre of this coolant
	return density * specific_heat
