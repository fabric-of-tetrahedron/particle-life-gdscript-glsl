#[compute]
#version 450

layout(local_size_x=1024,local_size_y=1,local_size_z=1)in;

layout(set=0,binding=0,std430)restrict buffer Params{
	float num_particles;
	float grid_size;
	float r_max;
	float friction_factor;
	float beta;
	float dt;
	float n_color;
	float delta;
}params;

// 粒子位置和颜色数据
layout(rgba32f,binding=1)uniform image2D particle_position_color;// rg: position / color
// 粒子速度数据
layout(rgba32f,binding=2)uniform image2D particle_velocity;// rg: velocity
// 粒子旧位置数据
layout(rgba32f,binding=3)uniform image2D particle_old_position;// rg: old position
// 力矩阵数据
layout(rgba32f,binding=4)uniform image2D force_matrix;// r: force

// 将一维索引转换为二维坐标
ivec2 index_to_2d_coord(int index){
	int grid_size=int(params.grid_size);
	int row=int(index/grid_size);
	int col=index%grid_size;
	return ivec2(col,row);
}

// 包裹位置，处理边界情况
float wrap_position(float original, float target){
	float distance=target-original;
	if(distance>.5||distance<-.5){
		return target<original?target+1.:target-1.;
	}
	return target;
}

// 限制位置在0到1之间
float clamp_position(float value){
	return value>1.?0.:value<0.?1.:value;
}

// 计算力的大小
float calculate_force(float distance, int color_1, int color_2){
	float beta=params.beta;
	if(distance<beta){
		return distance/beta-1.;
	}else if(beta<distance&&distance<1.){
		float force_magnitude=imageLoad(force_matrix,ivec2(color_1,color_2)).r;
		return force_magnitude*(1.-abs(2.*distance-1.-beta)/(1.-beta));
	}
	return 0.;
}

void main(){
	int particle_index=int(gl_GlobalInvocationID.x);
	int total_particles=int(params.num_particles);
	if(particle_index>=total_particles){
		// 超出粒子数量范围，不做任何改变
		return;
	}
	ivec2 particle_coord=index_to_2d_coord(particle_index);
	vec4 particle_data=imageLoad(particle_position_color,particle_coord);// 当前位置
	vec2 particle_position=particle_data.rg;
	int particle_color=int(particle_data.b*(params.n_color-1.));
	vec2 total_force=vec2(0);

	// 计算粒子间的力
	for(int i=0;i<total_particles;i++){
		vec4 other_particle_data=imageLoad(particle_old_position,index_to_2d_coord(i));
		vec2 other_position=other_particle_data.rg;
		int other_color=int(other_particle_data.b*params.n_color-1.);
		float wrapped_x=wrap_position(particle_position.x,other_position.x);
		float wrapped_y=wrap_position(particle_position.y,other_position.y);
		other_position=vec2(wrapped_x,wrapped_y);
		vec2 distance_vector=other_position-particle_position;
		float distance=length(distance_vector);
		if(distance>0.&&distance<params.r_max){
			float force_magnitude=calculate_force(distance/params.r_max,particle_color,other_color);
			total_force+=force_magnitude*(distance_vector/distance);
		}
	}
	total_force*=params.r_max;

	// 更新速度和位置
	vec4 velocity_data=imageLoad(particle_velocity,particle_coord);// 当前速度
	vec2 velocity=velocity_data.rg;
	velocity*=params.friction_factor;
	velocity+=total_force*params.dt;
	particle_position+=velocity*params.delta;
	particle_position.x=clamp_position(particle_position.x);
	particle_position.y=clamp_position(particle_position.y);

	// 存储更新后的数据
	vec4 old_particle_data=particle_data;
	particle_data.rg=particle_position;
	velocity_data.rg=velocity;
	imageStore(particle_position_color,particle_coord,particle_data);
	imageStore(particle_velocity,particle_coord,velocity_data);
	imageStore(particle_old_position,particle_coord,old_particle_data);
}
