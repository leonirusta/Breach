// CIELO: sol y luna procedurales, nubes por ruido y estrellas.
//
// NO es mio: es "Stylized sky with procedural sun and moon" de Godot Shaders (licencia MIT), que a
// su vez parte de "Stylized Sky Shader With Clouds". Lo unico que se ha tocado son dos cosas de
// sintaxis para que compile en Godot 4.7: `pow(x, 2)` -> `pow(x, 2.0)` (el compilador no acepta el
// exponente entero) y `seed++` sacado a una variable, porque incrementar un parametro dentro del
// bucle no esta permitido.
//   https://godotshaders.com/shader/stylized-sky-with-procedural-sun-and-moon/   (MIT)
//
// Como funciona con las luces: la PRIMERA DirectionalLight3D de la escena es el sol y la SEGUNDA es
// la luna. El shader saca de ellas la hora del dia -de que la altura del sol pase de positiva a
// negativa salen el atardecer y la noche- y la fase de la luna, iluminandola desde donde este el sol.
shader_type sky;
render_mode use_quarter_res_pass;

group_uniforms sky;
	uniform vec3 day_top_color : source_color = vec3( 0.1, 0.6, 1.0 );
	uniform vec3 day_bottom_color : source_color = vec3( 0.4, 0.8, 1.0 );
	uniform vec3 sunset_top_color : source_color = vec3( 0.7, 0.75, 1.0 );
	uniform vec3 sunset_bottom_color : source_color = vec3( 1.0, 0.5, 0.7 );
	uniform vec3 night_top_color : source_color = vec3( 0.02, 0.0, 0.04 );
	uniform vec3 night_bottom_color : source_color = vec3( 0.1, 0.0, 0.2 );

group_uniforms horizon;
	uniform vec3 horizon_color : source_color = vec3( 0.0, 0.7, 0.8 );
	uniform float horizon_blur : hint_range( 0.0, 1.0, 0.01 ) = 0.05;

group_uniforms sun;
	uniform vec3 sun_color : source_color = vec3( 10.0, 8.0, 1.0 );
	uniform vec3 sun_sunset_color : source_color = vec3( 10.0, 0.0, 0.0 );
	uniform float sun_size : hint_range( 0.01, 1.0 ) = 0.2;
	uniform float sun_blur : hint_range( 0.01, 20.0 ) = 10.0;

group_uniforms moon;
	uniform vec3 moon_color : source_color = vec3( 1.0, 0.95, 0.7 );
	uniform float moon_size : hint_range( 0.01, 1.0 ) = 0.06;
	uniform float moon_blur : hint_range( 0.01, 10.0 ) = 0.1;

group_uniforms clouds;
	uniform vec3 clouds_edge_color : source_color = vec3( 0.8, 0.8, 0.98 );
	uniform vec3 clouds_top_color : source_color = vec3( 1.0, 1.0, 1.00 );
	uniform vec3 clouds_middle_color : source_color = vec3( 0.92, 0.92, 0.98 );
	uniform vec3 clouds_bottom_color : source_color = vec3( 0.83, 0.83, 0.94 );
	uniform float clouds_speed : hint_range( 0.0, 20.0, 0.01 ) = 2.0;
	uniform float clouds_direction : hint_range( -0.5, 0.5, 0.0 ) = 0.2;
	uniform float clouds_scale : hint_range( 0.0, 4.0, 0.01 ) = 1.0;
	uniform float clouds_cutoff : hint_range( 0.0, 1.0, 0.01 ) = 0.3;
	uniform float clouds_fuzziness : hint_range( 0.0, 2.0, 0.01 ) = 0.5;
	// mas "peso" es simplemente color mas oscuro: es lo que se sube cuando llueve
	uniform float clouds_weight : hint_range( 0.0, 1.0, 0.01 ) = 0.0;
	uniform float clouds_blur : hint_range( 0.0, 1.0, 0.01 ) = 0.25;

group_uniforms stars;
	uniform sampler2D stars_texture : filter_linear_mipmap, hint_default_black;
	uniform float stars_speed : hint_range( 0.0, 20.0, 0.01 ) = 1.0;

group_uniforms settings;
	// EL CIELO QUIETO (2026-09-30, pedido: "que el cielo sea estatico para que sea gratis"): las nubes ya no se mueven con
	// el reloj. Un cielo que usa TIME obliga a Godot a rehacer el mapa de reflejos (la luz ambiental) CADA fotograma;
	// sin TIME solo se rehace cuando cambia algo (la hora, el sol). Este numero es "donde" estan las nubes.
	uniform float overwritten_time = 37.0;

// --- ruido para las nubes (FastNoiseLite, portado al shader por el autor) ---
const int PRIME_X = 501125321;
const int PRIME_Y = 1136930381;

float lerpf( float a, float b, float t ) {
	return a + t * ( b - a );
}

float cubic_lerp( float a, float b, float c, float d, float t ) {
	float p = d - c - ( a - b );
	return t * t * t * p + t * t * ( a - b - p ) + t * ( c - a ) + b;
}

float ping_pong( float t ) {
	t -= trunc( t * 0.5 ) * 2.0;
	return t < 1.0 ? t : 2.0 - t;
}

int hash_i( int seed, int x_primed, int y_primed ) {
	return ( seed ^ x_primed ^ y_primed ) * 0x27d4eb2d;
}

float val_coord( int seed, int x_primed, int y_primed ) {
	int h = hash_i( seed, x_primed, y_primed );
	h *= h;
	h ^= h << 19;
	return float( h ) * ( 1.0 / 2147483648.0 );
}

float single_value_cubic( int seed, float x, float y ) {
	int x1 = int( floor( x ));
	int y1 = int( floor( y ));
	float xs = x - float( x1 );
	float ys = y - float( y1 );
	x1 *= PRIME_X;
	y1 *= PRIME_Y;
	int x0 = x1 - PRIME_X;
	int y0 = y1 - PRIME_Y;
	int x2 = x1 + PRIME_X;
	int y2 = y1 + PRIME_Y;
	int x3 = x1 + ( PRIME_X << 1 );
	int y3 = y1 + ( PRIME_Y << 1 );
	return cubic_lerp(
		cubic_lerp( val_coord( seed, x0, y0 ), val_coord( seed, x1, y0 ), val_coord( seed, x2, y0 ), val_coord( seed, x3, y0 ), xs ),
		cubic_lerp( val_coord( seed, x0, y1 ), val_coord( seed, x1, y1 ), val_coord( seed, x2, y1 ), val_coord( seed, x3, y1 ), xs ),
		cubic_lerp( val_coord( seed, x0, y2 ), val_coord( seed, x1, y2 ), val_coord( seed, x2, y2 ), val_coord( seed, x3, y2 ), xs ),
		cubic_lerp( val_coord( seed, x0, y3 ), val_coord( seed, x1, y3 ), val_coord( seed, x2, y3 ), val_coord( seed, x3, y3 ), xs ),
	ys ) * ( 1.0 / ( 1.5 * 1.5 ));
}

const float FRACTAL_BOUNDING = 1.0 / 1.75;
const int OCTAVES = 5;
const float PING_PONG_STRENGTH = 2.0;
const float WEIGHTED_STRENGTH = 0.0;
const float GAIN = 0.5;
const float LACUNARITY = 2.0;

float gen_fractal_ping_pong( vec2 pos, int seed, float frequency ) {
	float x = pos.x * frequency;
	float y = pos.y * frequency;
	float sum = 0.0;
	float amp = FRACTAL_BOUNDING;
	int s = seed;
	for( int i = 0; i < OCTAVES; i++ ) {
		float noise = ping_pong(( single_value_cubic( s, x, y ) + 1.0 ) * PING_PONG_STRENGTH );
		s += 1;
		sum += ( noise - 0.5 ) * 2.0 * amp;
		amp *= lerpf( 1.0, noise, WEIGHTED_STRENGTH );
		x *= LACUNARITY;
		y *= LACUNARITY;
		amp *= GAIN;
	}
	return sum * 0.5 + 0.5;
}

// para la fase de la luna: donde corta la vista con la esfera de la luna
float sphere_intersect( vec3 view_dir, vec3 sphere_pos, float radius ) {
	float b = dot( -sphere_pos, view_dir );
	float c = dot( -sphere_pos, -sphere_pos ) - pow( radius, 2.0 );
	float h = pow( b, 2.0 ) - c;
	return h < 0.0 ? -1.0 : -b - sqrt( h );
}

void sky() {
	// EL CIELO DE FONDO SALE DE LA PASADA A UN CUARTO DE RESOLUCION (2026-09-30, pedido: "el cielo cuesta un monton de
	// fps: hazlo que no cueste nada"). `use_quarter_res_pass` estaba puesto, pero luego se calculaba TODO otra vez a
	// resolucion completa en cada pixel de cielo: el ruido de las nubes (tres capas de 5 octavas cubicas) se pagaba dos
	// veces. Ahora la pasada grande solo lee lo de la pequeña (16 veces menos pixeles) y el mapa de reflejos sigue igual.
	// (sin `return`: en la funcion sky() no se permite)
	if ( !AT_QUARTER_RES_PASS && !AT_CUBEMAP_PASS ) {
		COLOR = QUARTER_RES_COLOR.rgb;
	} else {
		float time = overwritten_time;

		// --- CIELO ---
		float _eyedir_y = abs( sin( EYEDIR.y * PI * 0.5 ));
		vec3 _sky_color = mix( day_bottom_color, day_top_color, _eyedir_y );
		_sky_color = mix( _sky_color, vec3( 0.0 ), clamp(( 0.7 - clouds_cutoff ) * clouds_weight, 0.0, 1.0 ));

		float _sunset_amount = clamp( 0.5 - abs( LIGHT0_DIRECTION.y ), 0.0, 0.5 ) * 2.0;
		float _sunset_distance = clamp( 1.0 - pow( distance( EYEDIR, LIGHT0_DIRECTION ), 2.0 ), 0.0, 1.0 );
		vec3 _sky_sunset_color = mix( sunset_bottom_color, sunset_top_color, _eyedir_y + 0.5 );
		_sky_sunset_color = mix( _sky_sunset_color, sunset_bottom_color, _sunset_amount * _sunset_distance );
		_sky_color = mix( _sky_color, _sky_sunset_color, _sunset_amount );

		float _night_amount = clamp( -LIGHT0_DIRECTION.y + 0.7, 0.0, 1.0 );
		vec3 _sky_night_color = mix( night_bottom_color, night_top_color, _eyedir_y );
		_sky_color = mix( _sky_color, _sky_night_color, _night_amount );

		COLOR = _sky_color;

		// --- HORIZONTE ---
		float _horizon_amount = 0.0;
		if( EYEDIR.y < 0.0 ) {
			_horizon_amount = clamp( abs( EYEDIR.y ) / horizon_blur, 0.0, 1.0 );
			vec3 _horizon_color = mix( horizon_color, _sky_color, _night_amount * 0.9 );
			_horizon_color = mix( _horizon_color, vec3( 0.0 ), ( 1.0 - clouds_cutoff ) * clouds_weight * 0.7 );
			COLOR = mix( COLOR, _horizon_color, _horizon_amount );
		}

		// --- LUNA ---
		float _moon_amount = 0.0;
		if( LIGHT1_ENABLED ) {
			float _moon_size = moon_size + cos( LIGHT1_DIRECTION.y * PI ) * moon_size * 0.25;
			float _moon_distance = distance( EYEDIR, LIGHT1_DIRECTION ) / _moon_size;
			_moon_amount = clamp(( 1.0 - _moon_distance ) / moon_blur, 0.0, 1.0 );
			if( _moon_amount > 0.0 ) {
				float _moon_intersect = sphere_intersect( EYEDIR, LIGHT1_DIRECTION, _moon_size );
				// SIN NaN: en el borde de la esfera el vector puede salir nulo, y normalize(0) da NaN. En PC queda
				// en un punto suelto; en el movil, al suavizar el mapa de reflejos, el NaN se extiende en una
				// MANCHA NEGRA alrededor de la luna en todo lo que refleja (el suelo mojado).
				vec3 _moon_n0 = LIGHT1_DIRECTION - EYEDIR * _moon_intersect;
				vec3 _moon_normal = dot( _moon_n0, _moon_n0 ) > 1e-8 ? normalize( _moon_n0 ) : LIGHT1_DIRECTION;
				float _moon_n_dot_l = pow( clamp( dot( _moon_normal, -LIGHT0_DIRECTION ), 0.05, 1.0 ), 2.0 );
				_moon_amount *= 1.0 - _horizon_amount;
				COLOR = mix( COLOR, moon_color, _moon_n_dot_l * _moon_amount );
			}
		}

		// --- SOL ---
		float _sun_distance = 0.0;
		if( LIGHT0_ENABLED ) {
			_sun_distance = distance( EYEDIR, LIGHT0_DIRECTION );
			float _sun_size = sun_size + cos( LIGHT0_DIRECTION.y * PI ) * sun_size * 0.25;
			float _sun_amount = clamp(( 1.0 - _sun_distance / _sun_size ) / sun_blur, 0.0, 1.0 );
			if( _sun_amount > 0.0 ) {
				float _sunset_amount2 = 1.0;
				if( LIGHT0_DIRECTION.y > 0.0 ) {
					_sunset_amount2 = clamp( cos( LIGHT0_DIRECTION.y * PI ), 0.0, 1.0 );
				}
				vec3 _sun_color = mix( sun_color, sun_sunset_color, _sunset_amount2 );
				_sun_amount = clamp( _sun_amount * ( 1.0 - _moon_amount ), 0.0, 1.0 );
				_sun_amount *= 1.0 - _horizon_amount;
				if( _sun_color.r > 1.0 || _sun_color.g > 1.0 || _sun_color.b > 1.0 ) {
					_sun_color *= _sun_amount;
				}
				COLOR = mix( COLOR, _sun_color, _sun_amount );
			}
		}

		// --- ESTRELLAS ---
		vec2 _sky_uv = EYEDIR.xz / sqrt( abs( EYEDIR.y ) + 0.001 );
		if( EYEDIR.y > -0.01 && LIGHT0_DIRECTION.y < 0.0 ) {
			float _c = cos( stars_speed * time * 0.005 );
			float _s = sin( stars_speed * time * 0.005 );
			vec2 _stars_uv = vec2( _sky_uv.x * _c - _sky_uv.y * _s, _sky_uv.x * _s + _sky_uv.y * _c );
			vec3 _stars_color = texture( stars_texture, _stars_uv ).rgb * -LIGHT0_DIRECTION.y;
			_stars_color *= 1.0 - _moon_amount;
			COLOR += _stars_color;
		}

		// --- NUBES ---
		if( EYEDIR.y > 0.0 ) {
			float _clouds_speed = time * clouds_speed * 0.01;
			float _sin_x = sin( clouds_direction * PI * 2.0 );
			float _cos_y = cos( clouds_direction * PI * 2.0 );
			vec2 _clouds_movement = vec2( _sin_x, _cos_y ) * _clouds_speed;
			float _noise_top = gen_fractal_ping_pong(( _sky_uv + _clouds_movement ) * clouds_scale, 0, 0.5 );
			_clouds_movement = vec2( _sin_x * 0.97, _cos_y * 1.07 ) * _clouds_speed * 0.89;
			float _noise_middle = gen_fractal_ping_pong(( _sky_uv + _clouds_movement ) * clouds_scale, 1, 0.75 );
			_clouds_movement = vec2( _sin_x * 1.01, _cos_y * 0.89 ) * _clouds_speed * 0.79;
			float _noise_bottom = gen_fractal_ping_pong(( _sky_uv + _clouds_movement ) * clouds_scale, 2, 1.0 );
			_noise_bottom = smoothstep( clouds_cutoff, clouds_cutoff + clouds_fuzziness, _noise_bottom );
			_noise_middle = smoothstep( clouds_cutoff, clouds_cutoff + clouds_fuzziness, _noise_middle + _noise_bottom * 0.2 ) * 1.1;
			_noise_top = smoothstep( clouds_cutoff, clouds_cutoff + clouds_fuzziness, _noise_top + _noise_middle * 0.4 ) * 1.2;
			float _clouds_amount = clamp( _noise_top + _noise_middle + _noise_bottom, 0.0, 1.0 );
			_clouds_amount *= clamp( abs( EYEDIR.y ) / clouds_blur, 0.0, 1.0 );

			vec3 _clouds_color = mix( vec3( 0.0 ), clouds_top_color, _noise_top );
			_clouds_color = mix( _clouds_color, clouds_middle_color, _noise_middle );
			_clouds_color = mix( _clouds_color, clouds_bottom_color, _noise_bottom );
			_clouds_color = mix( clouds_edge_color, _clouds_color, _noise_top );
			_clouds_color = mix( _clouds_color, clamp( sun_color, 0.0, 1.0 ), pow( 1.0 - clamp( _sun_distance, 0.0, 1.0 ), 5.0 ));
			_clouds_color = mix( _clouds_color, sunset_bottom_color, _sunset_amount * 0.75 );
			_clouds_color = mix( _clouds_color, _sky_color, clamp( _night_amount, 0.0, 0.98 ));
			_clouds_color = mix( _clouds_color, vec3( 0.0 ), clouds_weight * 0.9 );
			COLOR = mix( COLOR, _clouds_color, _clouds_amount );
		}

		// EL MAPA DE REFLEJOS, LIMPIO (pedido 2026-09-21: "en el movil el reflejo del sol o la luna da una mancha
		// oscura"). Dos cosas que en PC no se notan y en muchas graficas de movil si:
		//   * un NaN o un infinito en un solo texel se extiende al filtrar el mapa (radiancia) y sale NEGRO;
		//   * el sol va a 10x el blanco: en un mapa de reflejos de poca precision se desborda.
		// Solo en la pasada del mapa de reflejos (AT_CUBEMAP_PASS): el cielo que se VE de fondo no cambia.
		if ( any( isnan( COLOR )) || any( isinf( COLOR ))) {
			COLOR = _sky_color;
		}
		COLOR = max( COLOR, vec3( 0.0 ));
		if ( AT_CUBEMAP_PASS ) {
			COLOR = min( COLOR, vec3( 4.0 ));
		}
	}
}
