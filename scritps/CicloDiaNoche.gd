extends Node3D

@onready var sol = $Sol 
@onready var luna = $Luna

# Ajustá estos valores si querés más o menos luz general
var energia_max_sol: float = 1.0
var energia_max_luna: float = 0.2

func _ready():
	# 1. Nos conectamos para los cambios futuros
	TiempoGlobal.hora_actualizada.connect(_actualizar_cielo)
	
	# 2. EL ARREGLO: Forzamos la actualización con la hora que tenga el mundo YA mismo
	_actualizar_cielo(TiempoGlobal.hora)

func _actualizar_cielo(hora: float):
	# 1. Rotación suave continua
	var grados = ((hora - 6.0) / 24.0) * 360.0
	rotation_degrees.x = -grados
	
	# 2. Fading (Fundido) matemático de la luz
	if hora >= 0.0 and hora < 5.0:
		# Noche profunda (Luz apagada forzosamente a cero)
		sol.light_energy = 0.0
		luna.light_energy = energia_max_luna
		
	elif hora >= 5.0 and hora <= 7.0:
		# Amanecer unificado
		sol.light_energy = remap(hora, 5.0, 7.0, 0.0, energia_max_sol)
		luna.light_energy = remap(hora, 5.0, 7.0, energia_max_luna, 0.0)
		
	elif hora >= 17.5 and hora <= 19.5:
		# Atardecer: A medida que la hora va de 17.5 a 19.5, la luz se apaga de a poco
		sol.light_energy = remap(hora, 17.5, 19.5, energia_max_sol, 0.0)
		luna.light_energy = remap(hora, 17.5, 19.5, 0.0, energia_max_luna)
		
	else:
		# Día pleno (Corregido: faltaba asegurar el día completo entre las 7 y las 17.5)
		sol.light_energy = energia_max_sol
		luna.light_energy = 0.0
