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
    // A bounded two-level search covers normal camera movement without a
    // full-resolution dense-flow solve: +/-16px coarse, +/-4px refinement.
    for(uint level=0;level<2;level++){
        int step=level?2:8,radius=level?4:16;
        float2 origin=level?displacement:float2(0);
        for(int y=-radius;y<=radius;y+=step)for(int x=-radius;x<=radius;x+=step){
            float2 candidate=origin+float2(x,y);float error=0;
            for(int v=-1;v<=1;v++)for(int u=-1;u<=1;u++){
                float2 p=centre+float2(u,v)*3.0f;
                float a=fgLuma(previous.sample(fgSampler,(p+candidate)/size).rgb);
                float b=fgLuma(current.sample(fgSampler,p/size).rgb);
                error+=abs(a-b);
            }
            error=error/9.0f+0.0001f*dot(candidate,candidate);
            if(error<best){best=error;displacement=candidate;}
        }
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
    float4 result=current.sample(fgSampler,uv);
    float3 directDifference=abs(previous.sample(fgSampler,uv).rgb-result.rgb);
    // A coarse background vector must not move stationary HUD/text pixels.
    // This also skips the flow/warp reads when the actual pixel is unchanged.
    if(max(directDifference.r,max(directDifference.g,directDifference.b))>1.0f/255.0f){
        float4 f=forward.sample(fgSampler,uv);
        float2 previousUV=uv+0.5f*f.xy/float2(size);
        float2 currentUV=uv-0.5f*f.xy/float2(size);
        float2 margin=0.5f/float2(size);
        bool inside=all(previousUV>=margin)&&all(previousUV<=1.0f-margin)&&
                    all(currentUV>=margin)&&all(currentUV<=1.0f-margin);
        // Zero/ambiguous motion cannot justify a temporal cross-fade. Outside
        // the image, clamped sampling would stretch an edge into a false warp.
        if(inside && length(f.xy)>=0.5f && f.z<0.08f){
            float4 b=backward.sample(fgSampler,uv+f.xy/float2(size));
            if(b.z<0.08f && length(f.xy+b.xy)<2.5f){
                float4 a=previous.sample(fgSampler,previousUV);
                float4 c=current.sample(fgSampler,currentUV);
                float3 difference=abs(a.rgb-c.rgb);
                // Flow confidence describes a tile, not this pixel. Reject
                // locally disagreeing colours/edges instead of averaging two
                // misregistered pictures into blur. RGB also catches colours
                // that have equal luminance. At most ~5/255 of blend deviation
                // is admitted per channel relative to either warped sample.
                if(max(difference.r,max(difference.g,difference.b))<=0.04f)
                    result=mix(a,c,0.5f);
            }
        }
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
