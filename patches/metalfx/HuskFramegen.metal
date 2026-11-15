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
    float3 ax=float3(wx.x,wx.y+wx.z,wx.w),ay=float3(wy.x,wy.y+wy.z,wy.w);
    float3 px=float3(float(base.x)-0.5f,float(base.x)+0.5f+wx.z/ax.y,float(base.x)+2.5f)/float(extent.x);
    float3 py=float3(float(base.y)-0.5f,float(base.y)+0.5f+wy.z/ay.y,float(base.y)+2.5f)/float(extent.y);
    float4 value=0,low=INFINITY,high=-INFINITY;
    for(uint y=0;y<3;y++)for(uint x=0;x<3;x++)value+=source.sample(fgSampler,float2(px[x],py[y]))*ax[x]*ay[y];
    for(int y=0;y<2;y++)for(int x=0;x<2;x++){
        float4 texel=source.read(uint2(clamp(base+int2(x,y),int2(0),extent-1)));
        low=min(low,texel);high=max(high,texel);
    }
    return clamp(value,low,high);
}
float fgPatchError(texture2d<float,access::sample> previous,
                   texture2d<float,access::sample> current,float2 centre,
                   float2 displacement,float spacing,uint lod){
    float2 size=float2(current.get_width(),current.get_height());float error=0;
    for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++){
        float2 p=centre+float2(x,y)*spacing;
        float3 a=previous.sample(fgSampler,(p+displacement)/size,level(float(lod))).rgb;
        float3 b=current.sample(fgSampler,p/size,level(float(lod))).rgb;
        error+=dot(abs(a-b),float3(0.2126f,0.7152f,0.0722f));
    }
    return error/25.0f;
}
// Estimate camera/surface motion on a64px grid FIRST. Independent wide
// searches on every16px tile overfit grass/brick repetition and temporal noise.
kernel void huskCoarseFlow(texture2d<float,access::sample> previous [[texture(0)]],
                           texture2d<float,access::sample> current [[texture(1)]],
                           texture2d<half,access::write> output [[texture(2)]],
                           uint2 tid [[thread_position_in_grid]]){
    if(any(tid>=uint2(output.get_width(),output.get_height())))return;
    float2 size=float2(current.get_width(),current.get_height());
    float2 centre=(float2(tid)+0.5f)*size/float2(output.get_width(),output.get_height());
    float2 displacement=0;float residual=INFINITY;
    for(uint stage=0;stage<2;stage++){
        uint lod=min(2-stage,previous.get_num_mip_levels()-1);
        float radius=stage?4.0f:16.0f,step=stage?1.0f:4.0f,spacing=stage?4.0f:12.0f;
        float2 origin=displacement;float best=INFINITY;
        for(float y=-radius;y<=radius;y+=step)for(float x=-radius;x<=radius;x+=step){
            float2 candidate=origin+float2(x,y);
            float error=fgPatchError(previous,current,centre,candidate,spacing,lod);
            float score=error+0.000001f*dot(candidate,candidate);
            if(score<best){best=score;residual=error;displacement=candidate;}
        }
    }
    output.write(half4(half2(displacement),half(residual),1),tid);
}
kernel void huskFlow(texture2d<float,access::sample> previous [[texture(0)]],
                     texture2d<float,access::sample> current [[texture(1)]],
                     texture2d<half,access::write> flow [[texture(2)]],
                     texture2d<float,access::sample> coarse [[texture(3)]],
                     uint2 tid [[thread_position_in_grid]]) {
    if(any(tid>=uint2(flow.get_width(),flow.get_height())))return;
    float2 size=float2(current.get_width(),current.get_height());
    float2 centre=(float2(tid)+0.5f)*size/float2(flow.get_width(),flow.get_height());
    float2 uv=centre/size,seed=coarse.sample(fgSampler,uv).xy;
    float2 displacement=seed;float best=INFINITY,residual=INFINITY;
    // Small residual search plus actual coarse corner hypotheses/zero. The
    // wide search is paid only on the coarse grid, with a spatial prior.
    for(uint choice=0;choice<14;choice++){
        float2 candidate;
        if(choice<9)candidate=seed+float2(int(choice%3)-1,int(choice/3)-1);
        else if(choice==9)candidate=0;
        else{
            float2 grid=uv*float2(coarse.get_width(),coarse.get_height())-0.5f;
            int2 pos=int2(floor(grid))+int2((choice-10)%2,(choice-10)/2);
            pos=clamp(pos,int2(0),int2(coarse.get_width(),coarse.get_height())-1);
            candidate=coarse.read(uint2(pos)).xy;
        }
        float error=fgPatchError(previous,current,centre,candidate,2.0f,0);
        float2 delta=candidate-seed;
        float score=error+0.0005f*min(dot(delta,delta),4.0f);
        if(score<best){best=score;residual=error;displacement=candidate;}
    }
    // Resolve continuous motion after the half-pixel search. Quantizing every
    // tile independently to0.5px makes a smooth camera pan vary across scenery.
    // A centred RGB least-squares step rejects constant illumination offsets;
    // retain a step only when it improves the actual photometric residual.
    for(uint iteration=0;iteration<2;iteration++){
        float3 sx=0,sy=0,se=0;float xx=0,xy=0,yy=0,bx=0,by=0;
        constexpr float3 weight=float3(0.2126f,0.7152f,0.0722f);
        for(int v=-1;v<=1;v++)for(int u=-1;u<=1;u++){
            float2 p=centre+float2(u,v)*3.0f,q=p+displacement;
            float3 a=previous.sample(fgSampler,q/size).rgb;
            float3 e=a-current.sample(fgSampler,p/size).rgb;
            float3 gx=previous.sample(fgSampler,(q+float2(0.5f,0))/size).rgb-previous.sample(fgSampler,(q-float2(0.5f,0))/size).rgb;
            float3 gy=previous.sample(fgSampler,(q+float2(0,0.5f))/size).rgb-previous.sample(fgSampler,(q-float2(0,0.5f))/size).rgb;
            sx+=gx;sy+=gy;se+=e;
            xx+=dot(gx*gx,weight);xy+=dot(gx*gy,weight);yy+=dot(gy*gy,weight);
            bx+=dot(gx*e,weight);by+=dot(gy*e,weight);
        }
        xx=max(0.0f,xx-dot(sx*sx,weight)/9.0f);yy=max(0.0f,yy-dot(sy*sy,weight)/9.0f);
        xy-=dot(sx*sy,weight)/9.0f;bx-=dot(sx*se,weight)/9.0f;by-=dot(sy*se,weight)/9.0f;
        if(xx+yy<0.0001f)break;
        xx+=0.00001f;yy+=0.00001f;float determinant=xx*yy-xy*xy;
        if(determinant<=0.0000000001f)break;
        float2 delta=clamp(float2(xy*by-yy*bx,xy*bx-xx*by)/determinant,float2(-0.5f),float2(0.5f));
        float2 candidate=displacement+delta;
        float error=fgPatchError(previous,current,centre,candidate,2.0f,0);
        if(!isfinite(error)||error>=residual)break;
        residual=error;displacement=candidate;
    }
    flow.write(half4(half2(displacement),half(residual),1),tid);
}
// Remove isolated tile outliers without carrying stale residuals. A median
// that materially worsens its own dense RGB evidence is rejected at boundaries.
kernel void huskRegularizeFlow(texture2d<float,access::sample> previous [[texture(0)]],
                               texture2d<float,access::sample> current [[texture(1)]],
                               texture2d<float,access::read> raw [[texture(2)]],
                               texture2d<half,access::write> output [[texture(3)]],
                               uint2 tid [[thread_position_in_grid]]){
    int2 extent=int2(output.get_width(),output.get_height());if(any(tid>=uint2(extent)))return;
    float2 values[9];uint index=0;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++)values[index++]=raw.read(uint2(clamp(int2(tid)+int2(x,y),int2(0),extent-1))).xy;
    for(uint i=1;i<9;i++)for(uint j=i;j>0;j--){float2 lo=min(values[j-1],values[j]),hi=max(values[j-1],values[j]);values[j-1]=lo;values[j]=hi;}
    float4 own=raw.read(tid);float2 candidate=values[4];
    float2 centre=(float2(tid)+0.5f)*float2(current.get_width(),current.get_height())/float2(extent);
    float error=fgPatchError(previous,current,centre,candidate,2.0f,0);
    if(!isfinite(error)||error>own.z+0.01f){candidate=own.xy;error=own.z;}
    output.write(half4(half2(candidate),half(error),1),tid);
}
// One bounded256-thread reduction; GPU-only in ordinary use. A poor field
// must not splice scattered intermediate patches into an otherwise real image.
kernel void huskFlowQuality(texture2d<float,access::read> forward [[texture(0)]],
                            texture2d<float,access::sample> backward [[texture(1)]],
                            texture2d<float,access::write> output [[texture(2)]],
                            constant uint2 &size [[buffer(0)]],
                            uint lane [[thread_index_in_threadgroup]]){
    threadgroup float3 votes[256];float3 count=0;
    uint width=forward.get_width(),height=forward.get_height();
    for(uint i=lane;i<width*height;i+=256){
        uint2 p=uint2(i%width,i/width);float4 f=forward.read(p);
        float2 uv=(float2(p)+0.5f)/float2(width,height),match=uv+f.xy/float2(size);
        float4 b=backward.sample(fgSampler,match);float error=length(f.xy+b.xy);
        bool valid=all(match>=0)&&all(match<=1)&&f.z<0.08f&&b.z<0.08f&&error<2.5f;
        count+=float3(valid?1.0f:0.0f,isfinite(error)?min(error,64.0f):64.0f,length(f.xy)<0.5f?1.0f:0.0f);
    }
    votes[lane]=count;threadgroup_barrier(mem_flags::mem_threadgroup);
    for(uint stride=128;stride;stride/=2){if(lane<stride)votes[lane]+=votes[lane+stride];threadgroup_barrier(mem_flags::mem_threadgroup);}
    if(lane==0){float3 result=votes[0]/float(width*height);output.write(float4(result,result.x>=0.80f?1.0f:0.0f),uint2(0));}
}
kernel void huskInterpolate(texture2d<float,access::sample> previous [[texture(0)]],
                            texture2d<float,access::sample> current [[texture(1)]],
                            texture2d<float,access::sample> forward [[texture(2)]],
                            texture2d<float,access::sample> backward [[texture(3)]],
                            texture2d<half,access::write> output [[texture(4)]],
                            texture2d<float,access::read> quality [[texture(5)]],
                            uint2 p [[thread_position_in_grid]]) {
    uint2 size=uint2(output.get_width(),output.get_height());if(any(p>=size))return;
    float2 uv=(float2(p)+0.5f)/float2(size);
    float4 result=current.sample(fgSampler,uv);
    if(quality.read(uint2(0)).w<0.5f){output.write(half4(result),p);return;}
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
