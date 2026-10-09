shader_type canvas_item;
uniform float bend_amount : hint_range(-3.0, 3.0) = 0.0;
uniform float wind_strength : hint_range(0.0,1.0) = 0.01;

void fragment(){
    COLOR = texture(TEXTURE, UV);
}

void vertex(){
    float raw_weight = 1.0 - UV.y;
    float weight = pow(raw_weight, 2.2);
    // 微风：随时间左右摆动
    float wind = sin(TIME * 2.0) * wind_strength;
    // 踩踏弯曲 + 微风叠加在一起
    VERTEX.x += (bend_amount + wind) * weight;
}