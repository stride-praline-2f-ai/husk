#include <metal_stdlib>
using namespace metal;
// Colour-only bidirectional block matching. This is NOT MetalFX temporal
// interpolation and does not fabricate engine depth or motion-vector inputs.
constexpr sampler fgSampler(coord::normalized,address::clamp_to_edge,filter::linear);
float fgLuma(float3 c){return dot(c,float3(0.2126,0.7152,0.0722));}
float fgDifference(float3 a,float3 b){float3 d=abs(a-b);return max(d.r,max(d.g,d.b));}
bool fgStable(texture2d<float,access::sample> previous,
              texture2d<float,access::sample> current,float2 uv){
    return fgDifference(previous.sample(fgSampler,uv).rgb,current.sample(fgSampler,uv).rgb)<=1.0f/255.0f;
}
float4 fgCubicWeights(float t){
    float t2=t*t,t3=t2*t;
    return float4(-0.5f*t+t2-0.5f*t3,1.0f-2.5f*t2+1.5f*t3,
                  0.5f*t+2.0f*t2-1.5f*t3,-0.5f*t2+0.5f*t3);
}
// Reconstruct one source at the intermediate position. Clamp the cubic
// response to its central footprint: no ringing/bright halos on sharp edges.
float4 fgReproject(texture2d<float,access::sample> source,float2 uv){
    int2 extent=int2(source.get_width(),source.get_height());
    float2 pixel=uv*float2(extent)-0.5f;
    int2 base=int2(floor(pixel));float2 fraction=fract(pixel);
    if(all(fraction<0.00001f))return source.read(uint2(clamp(base,int2(0),extent-1)));
    float4 wx=fgCubicWeights(fraction.x),wy=fgCubicWeights(fraction.y);
    float4 value=0,low=INFINITY,high=-INFINITY;
    for(int y=0;y<4;y++)for(int x=0;x<4;x++){
        float4 texel=source.read(uint2(clamp(base+int2(x-1,y-1),int2(0),extent-1)));
        value+=texel*wx[x]*wy[y];
        if(x>=1&&x<=2&&y>=1&&y<=2){low=min(low,texel);high=max(high,texel);}
    }
    return clamp(value,low,high);
}
kernel void huskFlow(texture2d<float,access::sample> previous [[texture(0)]],
                     texture2d<float,access::sample> current [[texture(1)]],
                     texture2d<half,access::write> flow [[texture(2)]],
                     uint2 tid [[thread_position_in_grid]]) {
    if(any(tid>=uint2(flow.get_width(),flow.get_height())))return;
    float2 size=float2(current.get_width(),current.get_height());
    float2 centre=(float2(tid)+0.5f)*size/float2(flow.get_width(),flow.get_height());
    float best=INFINITY,residual=INFINITY;float2 displacement=0;
    // Keep the bounded tile search, then resolve odd/fractional movement.
    // The regularizer breaks ties; it must not dominate real correspondence
    // or be reported as the photometric confidence error.
    for(uint level=0;level<3;level++){
        float step=level==0?8.0f:(level==1?2.0f:0.5f);
        float radius=level==0?16.0f:(level==1?4.0f:1.0f);
        float2 origin=level?displacement:float2(0);
        for(float y=-radius;y<=radius;y+=step)for(float x=-radius;x<=radius;x+=step){
            float2 candidate=origin+float2(x,y);float error=0;
            for(int v=-1;v<=1;v++)for(int u=-1;u<=1;u++){
                float2 p=centre+float2(u,v)*3.0f;
                float3 a=previous.sample(fgSampler,(p+candidate)/size).rgb;
                float3 b=current.sample(fgSampler,p/size).rgb;
                error+=dot(abs(a-b),float3(0.2126f,0.7152f,0.0722f));
            }
            error=error/9.0f;
            float score=error+0.000001f*dot(candidate,candidate);
            if(score<best){best=score;residual=error;displacement=candidate;}
        }
    }
    flow.write(half4(half2(displacement),half(residual),1),tid);
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
    float4 f=forward.sample(fgSampler,uv);
    float2 previousUV=uv+0.5f*f.xy/float2(size);
    float2 currentUV=uv-0.5f*f.xy/float2(size);
    float2 margin=0.5f/float2(size);
    bool inside=all(previousUV>=margin)&&all(previousUV<=1.0f-margin)&&
                all(currentUV>=margin)&&all(currentUV<=1.0f-margin);
    // Zero/ambiguous motion cannot justify a temporal cross-fade. Clamping an
    // out-of-image warp would stretch the boundary into false correspondence.
    if(inside && length(f.xy)>=0.5f && f.z<0.08f){
        float4 b=backward.sample(fgSampler,uv+f.xy/float2(size));
        if(b.z<0.08f && length(f.xy+b.xy)<2.5f){
            // All admitted scene pixels use the same intermediate motion
            // phase and a SINGLE source. A per-pixel colour-difference gate
            // previously spliced unwarped current pixels among warped pixels;
            // averaging two misregistered sources added doubled contours.
            float4 reconstructed=fgReproject(current,currentUV);
            bool stationary=false;
            float3 change=abs(reconstructed.rgb-result.rgb);
            if(max(change.r,max(change.g,change.b))>0.04f){
                float3 stable=abs(previous.sample(fgSampler,uv).rgb-result.rgb);
                if(max(stable.r,max(stable.g,stable.b))<=1.0f/255.0f){
                    // Preserve stable thin HUD detail without masking a real
                    // moving object between disjoint real-frame positions.
                    float2 pixel=1.0f/float2(size);
                    bool vertical=fgStable(previous,current,uv+float2(0,pixel.y))&&
                                  fgStable(previous,current,uv-float2(0,pixel.y));
                    bool horizontal=fgStable(previous,current,uv+float2(pixel.x,0))&&
                                    fgStable(previous,current,uv-float2(pixel.x,0));
                    // An isolated colour coincidence is not a static layer.
                    stationary=(vertical||horizontal)&&fgDifference(current.sample(fgSampler,previousUV).rgb,reconstructed.rgb)<=0.04f;
                }
            }
            if(!stationary)result=reconstructed;
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
