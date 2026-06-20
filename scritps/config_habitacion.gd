extends Resource
class_name ConfigHabitacion

@export var escena: PackedScene
@export var nombre_debug: String = "Habitacion"

@export_category("Reglas de Generación")
## El peso define la probabilidad. 100 = muy común, 10 = rara, 1 = rarísima.
@export var peso_probabilidad: float = 100.0 

## Cuántas veces puede aparecer en toda la partida. 0 significa infinito.
@export var limite_maximo: int = 0

# Array con las baldosas exactas que ocupa la habitación. 
# Por defecto siempre ocupa la baldosa (0,0,0), que es donde normalmente está el centro la sala.
@export var huella_celdas: Array[Vector3i] = [Vector3i(0, 0, 0)]
