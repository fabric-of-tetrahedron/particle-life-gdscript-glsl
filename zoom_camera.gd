class_name ZoomCamera
extends Camera2D

# 缩放级别的下限。
@export var min_zoom = 0.2
# 缩放级别的上限。
@export var max_zoom = 10.0
# 控制每次滚轮滚动时增加或减少的缩放级别量。
@export var zoom_factor = 0.1
# 缩放动画的持续时间。
@export var zoom_duration = 0.2

# 相机的目标缩放级别。
var _zoom_level = 1.0 : set = _set_zoom_level

var tween

func _ready():
	# 获取视口大小并设置相机偏移量为视口中心。
	var vp = get_viewport_rect().size
	offset = vp * 0.5

func _set_zoom_level(value: float):
	# 如果存在正在进行的缩放动画，则停止它。
	if tween:
		tween.kill()
	tween = create_tween()
	# 将值限制在 min_zoom 和 max_zoom 之间。
	_zoom_level = clamp(value, min_zoom, max_zoom)
	# 使用补间动画将相机的 zoom 属性从当前值过渡到目标缩放级别。
	tween.tween_property(
		self,
		"zoom",
		Vector2(_zoom_level, _zoom_level),
		zoom_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _unhandled_input(event: InputEvent):
	# 处理鼠标移动事件，实现相机平移。
	if event is InputEventMouseMotion:
		if event.button_mask == MOUSE_BUTTON_LEFT:
			position -= event.relative
	# 处理放大事件。
	if event.is_action_pressed("zoom_in"):
		# 在给定类中，我们需要写 self._zoom_level = ... 或显式调用 setter 函数来使用它。
		_set_zoom_level(_zoom_level - zoom_factor)
	# 处理缩小事件。
	if event.is_action_pressed("zoom_out"):
		_set_zoom_level(_zoom_level + zoom_factor)
