@tool
@icon("res://icons/my_node.svg")
class_name MyClass
extends Node2D

signal health_changed(new_health: int, max_health: int)
signal died

@export var speed: float = 100.0
@export var health: int = 100
@onready var sprite: Sprite2D = $Sprite2D

var private_var: String = "hidden"

func _ready():
    pass

func _process(delta: float) -> void:
    position += velocity * delta

func take_damage(amount: int) -> void:
    health -= amount
    health_changed.emit(health, 100)
    if health <= 0:
        died.emit()
