#include <metal_stdlib>
using namespace metal;
// Colour-only bidirectional block matching. This is NOT MetalFX temporal
// interpolation and does not fabricate engine depth or motion-vector inputs.
constexpr sampler fgSampler(coord::normalized,address::clamp_to_edge,filter::linear);
float fgLuma(float3 c){return dot(c,float3(0.2126,0.7152,0.0722));}
kernel void huskFlow(texture2d<float,access::sample> previous [[texture(0)]],
                     texture2d<float,access::sample> current [[texture(1)]],
                     texture2d<half,access::write> flow [[texture(2)]],
                     uint2 tid [[thread_position_in_grid]]) {
    if(any(tid>=uint2(flow.get_width(),flow.get_height())))return;
    float2 size=float2(current.get_width(),current.get_height());
    float2 centre=(float2(tid)+0.5f)*size/float2(flow.get_width(),flow.get_height());
    float best=INFINITY;float2 displacement=0;
    for(int y=-4;y<=4;y+=2)for(int x=-4;x<=4;x+=2){
        float error=0;
        for(int v=-1;v<=1;v++)for(int u=-1;u<=1;u++){
            float2 p=centre+float2(u,v)*3.0f;
            float a=fgLuma(previous.sample(fgSampler,(p+float2(x,y))/size).rgb);
            float b=fgLuma(current.sample(fgSampler,p/size).rgb);
            error+=abs(a-b);
        }
        error=error/9.0f+0.0001f*float(x*x+y*y);
        if(error<best){best=error;displacement=float2(x,y);}
    }
    flow.write(half4(half2(displacement),half(best),1),tid);
}
kernel void huskInterpolate(texture2d<float,access::sample> previous [[texture(0)]],
                            texture2d<float,access::sample> current [[texture(1)]],
                            texture2d<float,access::sample> forward [[texture(2)]],
                            texture2d<float,access::sample> backward [[texture(3)]],
                            texture2d<half,access::write> output [[texture(4)]],
                            uint2 p [[thread_position_in_grid]]) {
    uint2 size=uint2(output.get_width(),output.get_height());if(any(p>=size))return;
    float2 uv=(float2(p)+0.5f)/float2(size);
    float4 f=forward.sample(fgSampler,uv);
    float4 b=backward.sample(fgSampler,uv+f.xy/float2(size));
    float4 result=current.sample(fgSampler,uv);
    // Low confidence, occlusion and large cuts use the real frame locally;
    // suppressing a bad warp is preferable to inventing object correspondence.
    if(f.z<0.08f && b.z<0.08f && length(f.xy+b.xy)<2.5f){
        result=mix(previous.sample(fgSampler,uv+0.5f*f.xy/float2(size)),
                   current.sample(fgSampler,uv-0.5f*f.xy/float2(size)),0.5f);
    }
    output.write(half4(result),p);
}
kernel void huskCopyFrame(texture2d<float,access::sample> input [[texture(0)]],
                         texture2d<half,access::write> output [[texture(1)]],
                         uint2 p [[thread_position_in_grid]]) {
    if(any(p>=uint2(output.get_width(),output.get_height())))return;
    float2 uv=(float2(p)+0.5f)/float2(output.get_width(),output.get_height());
    output.write(half4(input.sample(fgSampler,uv)),p);
}
