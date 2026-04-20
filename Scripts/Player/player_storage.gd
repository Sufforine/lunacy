extends Node

# Array sized like the storage grid (rows * cols).
# Each entry is either null or a Dictionary:
# { item_name: String, icon_path: String, is_stackable: bool, amount: int }
var slots_state: Array = []
