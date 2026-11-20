extends SkinData
class_name IconSkinData

# Skin for things shown as an icon: the menu (fairy / firefly light) and the
# music box. Leave `icon` empty to use the built-in drawn placeholder.

@export var icon: Texture2D
@export var glow_color: Color = Color(0.75, 1.0, 0.7)    # glow around the icon
@export var tint: Color = Color(1, 1, 1)
