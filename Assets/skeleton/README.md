# Модели и AnimationTree персонажа

В игре используются `Mannequin.tscn` и `Mannequin_F.tscn`. Обе сцены имеют
одинаковую структуру:

```text
Model
├── Armature/HumanSkeleton/Mannequin
├── AnimationPlayer
└── AnimationTree
```

`AnimationPlayer` хранит анимации, а воспроизведением управляет только
`AnimationTree`. Не вызывайте `AnimationPlayer.play()` у этих моделей.

## Ресурсы

- `meshes/Mannequin.res` и `meshes/Mannequin_F.res` — отдельные меши.
- `meshes/*_skin.res` — привязка меша к общему скелету.
- `animations/*.res` — отдельные клипы из UAL1.
- `animations/player_animations.tres` — библиотека клипов AnimationPlayer.
- `player_animation_tree.tres` — StateMachine с плавными переходами.

Верхний уровень дерева содержит только `Alive`, `Downed` и `Dead`. Внутри
`Alive` находятся `Grounded`, `JumpStart`, `Air`, `Land`, `Attack` и `Ability`.
`Grounded` — это BlendSpace1D: значение 0 проигрывает Idle, 1 — Walk, 2 —
Sprint. Циклические клипы Idle, Walk, Sprint, Air и Downed имеют
`loop_mode = LOOP_LINEAR`.

`Land` заканчивается естественно только когда герой стоит на месте. Движение,
атака, способность, новый прыжок или падение сразу переводят вложенное дерево
в соответствующее состояние.

## Управление из кода

Дерево сначала нужно активировать и запустить:

```gdscript
animation_tree.active = true
var root := animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
var alive := animation_tree.get("parameters/Alive/playback") as AnimationNodeStateMachinePlayback
root.start(&"Alive")
alive.start(&"Grounded")
animation_tree.set("parameters/Alive/Grounded/blend_position", 1.0)
```

Это выполняется в `entities/player/model/player.gd`. Состояние движения
синхронизируется надёжно при изменении через MultiplayerSynchronizer. Атака и
способность отправляются владельцем хосту, проверяются по authority и затем
надёжно рассылаются всем клиентам. Каждый компьютер смешивает позы своих
сетевых копий локально, поэтому кадры костей по сети не передаются.

Официальная документация Godot:

- https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html
- https://docs.godotengine.org/en/stable/classes/class_animationtree.html
