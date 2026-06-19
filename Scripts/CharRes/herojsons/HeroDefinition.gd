# HeroDefinition.gd
# Resource описывающий героя для выбора в лобби.
# Создавай .tres файлы: New Resource → HeroDefinition
extends Resource
class_name HeroDefinition

@export var id: String = ""
@export var hero_name: String = ""
@export var icon: Texture2D = null
@export var scene: PackedScene = null   # .tscn героя с компонентами
