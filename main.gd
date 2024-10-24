extends Node2D

# 创建本地渲染设备
var rd = RenderingServer.create_local_rendering_device()

# 用于从计算着色器传递数据到粒子着色器的图像信息
var image_size : Vector2i = Vector2i(Common.data_texture_size, Common.data_texture_size)
var n_pixels : int = image_size.x * image_size.y

var shader_executed = false

# 着色器资源类
class ShaderResource:
	var image: Image
	var image_data: PackedByteArray
	var texture: ImageTexture
	var buffer: RID
	var uniform : RDUniform
	var fmt : RDTextureFormat
	var w : int
	var h : int

	# 初始化着色器资源
	func _init(width, height):
		self.w = width
		self.h = height
		self.image = Image.create(self.w, self.h, false, Image.FORMAT_RGBAF)

	# 填充图像像素（设置粒子初始位置和颜色）
	func _fill_image_pixels():
		var n_color = Common.n_color-1
		if n_color == 0:
			n_color = 1
		for i in Common.grid_size:
			for j in Common.grid_size:
				var col = Color(randf(), randf(), float(randi_range(0, n_color)) / n_color)
				self.image.set_pixel(i, j, col)

	# 设置纹理（从图像创建纹理）
	func _setup_texture():
		self.texture = ImageTexture.create_from_image(self.image)

	# 从渲染设备读取缓冲区（用于更新粒子位置和颜色）
	func _read_buffer(rd: RenderingDevice):
		self.image_data = rd.texture_get_data(self.buffer, 0)
		self.image = Image.create_from_data(self.w, self.h, false, Image.FORMAT_RGBAF, self.image_data)
		self._update_texture()

	# 更新纹理（用于实时更新粒子状态）
	func _update_texture():
		self.texture.update(self.image)

	# 创建uniform（设置着色器绑定）
	func _create_uniform(rd: RenderingDevice, _fmt: RDTextureFormat, bid: int):
		self.buffer = rd.texture_create(_fmt, RDTextureView.new(), [self.image.get_data()])
		self.uniform = RDUniform.new()
		self.uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		self.uniform.binding = bid
		self.uniform.add_id(self.buffer)
		self.fmt = _fmt

	# 更新uniform（更新着色器绑定的数据）
	func _update_uniform(rd: RenderingDevice):
		self.uniform.clear_ids()
		rd.texture_update(self.buffer, 0, self.image.get_data())
		self.uniform.add_id(self.buffer)

# 着色器资源（图像/纹理/缓冲区）
var p1_data : ShaderResource # 粒子位置和颜色数据
var p2_data : ShaderResource # 粒子速度数据
var p3_data : ShaderResource # 粒子旧位置数据
var force_matrix : ShaderResource # 粒子间相互作用力矩阵

var params_uniform: RDUniform # 着色器参数uniform

var shader : RID
var pipeline : RID
var uniform_set : RID
var bindings : Array

# 生成力矩阵（定义不同颜色粒子间的相互作用力）
func _gen_matrix():
	for i in range(Common.n_color):
		for j in range(Common.n_color):
			var col = Color(randf()-.5, 1, 1, 1)
			force_matrix.image.set_pixel(i, j, col)

# 创建计算着色器
func _create_shader(shader_filename):
	var shader_file = load(shader_filename)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	return rd.shader_create_from_spirv(shader_spirv)

# 初始化图像（设置初始粒子状态）
func _init_images():
	p1_data = ShaderResource.new(image_size.x, image_size.y)
	p1_data._fill_image_pixels()
	p1_data._setup_texture()
	p2_data = ShaderResource.new(image_size.x, image_size.y)
	p2_data._setup_texture()
	p3_data = ShaderResource.new(image_size.x, image_size.y)
	p3_data.image = p1_data.image
	p3_data._setup_texture()
	force_matrix = ShaderResource.new(image_size.x, image_size.y)
	_gen_matrix()
	force_matrix._setup_texture()

# 创建参数缓冲区（传递模拟参数到着色器）
func _create_params_buffer(delta):
	var params_buffer_bytes : PackedByteArray = PackedFloat32Array(
		[
			Common.num_particles,  # 粒子总数
			Common.grid_size,      # 网格大小
			Common.r_max,          # 最大作用距离
			Common.get_friction_factor(), # 摩擦系数
			Common.beta,           # 排斥力参数
			Common.dt * 0.1,       # 时间步长
			Common.n_color,        # 粒子颜色数量
			delta                  # 帧间隔时间
		]).to_byte_array()
	return rd.storage_buffer_create(params_buffer_bytes.size(), params_buffer_bytes)

# 设置着色器uniforms（绑定计算着色器需要的所有数据）
func _setup_shader_uniforms():
	var params_buffer = _create_params_buffer(0)
	params_uniform = RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 0
	params_uniform.add_id(params_buffer)
	
	var fmt = RDTextureFormat.new()
	fmt.width = image_size.x
	fmt.height = image_size.y
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	# 创建Uniforms（设置各个数据纹理的绑定）
	p1_data._create_uniform(rd, fmt, 1)
	p2_data._create_uniform(rd, fmt, 2)
	p3_data._create_uniform(rd, fmt, 3)
	force_matrix._create_uniform(rd, fmt, 4)
	_set_binding_array(0)

# 执行计算着色器（进行粒子模拟计算）
func _execute_shader():
	uniform_set = rd.uniform_set_create(bindings, shader, 0)
	pipeline = rd.compute_pipeline_create(shader)
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	# 计算工作组大小（确保能处理所有粒子）
	var work_group_size = 1
	if Common.num_particles > Common.local_size_x:
		work_group_size = Common.num_particles / Common.local_size_x
		if int(Common.num_particles) % Common.local_size_x > 0:
			work_group_size += 1
	rd.compute_list_dispatch(compute_list, work_group_size, 1, 1)
	rd.compute_list_end()
	rd.submit()
	shader_executed = true

# 设置绑定数组（更新着色器的所有输入数据）
func _set_binding_array(delta):
	params_uniform.clear_ids()
	params_uniform.add_id(_create_params_buffer(delta))
	bindings = [
		params_uniform,
		p1_data.uniform,
		p2_data.uniform,
		p3_data.uniform,
		force_matrix.uniform
	]

# 当节点进入场景树时调用（初始化设置）
func _ready():
	_init_images()
	_gen_matrix()
	force_matrix._setup_texture()
	$ParticlesGPU.amount = Common.num_particles
	$ParticlesGPU.process_material.set_shader_parameter("part_data_tex", p1_data.texture)
	$ParticlesGPU.process_material.set_shader_parameter("num_particles", Common.num_particles)
	$ParticlesGPU.process_material.set_shader_parameter("grid_size", Common.grid_size)
	shader = _create_shader("res://compute.glsl")
	_setup_shader_uniforms()
	_execute_shader()

var run_shader = true
# 每帧调用（更新粒子系统）
func _process(delta):
	if shader_executed:
		rd.sync()
		shader_executed = false
	if run_shader:
		p1_data._read_buffer(rd) # 从计算着色器读取数据以更新纹理
		_set_binding_array(delta)
		_execute_shader()
	if Input.is_action_just_pressed("change_matrix"):
			_gen_matrix()
			force_matrix._update_uniform(rd)
#	var vp_size = get_viewport_rect().size
	var vp_size = Vector2(600, 600)
	$ParticlesGPU.process_material.set_shader_parameter("vw_size", vp_size)
	$ParticlesGPU.process_material.set_shader_parameter("scale", Common.scale)
	$CanvasLayer/Label.text = "FPS: %d - Particles: %d" % [Engine.get_frames_per_second(), Common.num_particles]

func _on_control_change_common():
	pass # 用函数体替换

# 生成新的粒子分布
func _gen_new_image():
	# 等待当前执行完成
	rd.sync()
	shader_executed = false
	_gen_matrix()
	force_matrix._update_uniform(rd)
	p1_data._fill_image_pixels()
	p1_data._update_texture()
	p1_data._update_uniform(rd)
	$ParticlesGPU.process_material.set_shader_parameter("part_data_tex", p1_data.texture)
	run_shader = true

# 重新生成粒子分布
func _on_control_regen_images():
	run_shader = false
	_gen_new_image()

# 改变粒子数量
func _on_control_change_num_particles():
	$ParticlesGPU.amount = Common.num_particles

# 编辑粒子间相互作用力矩阵
func _on_control_edit_matrix():
	rd.sync()
	shader_executed = false
	_gen_matrix()
	force_matrix._update_uniform(rd)
	run_shader = true
