#!/usr/bin/env python3
"""Execute the production midpoint lookup with an analytic texture sampler.

Portable arithmetic regression; this is not Metal compilation or phone proof.
The Apple GPU sequence test separately exercises the full production kernel.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MidpointCoordinates(unittest.TestCase):
    def test_production_lookup_matches_affine_inverse_and_preserves_translation(self):
        source = (ROOT / 'patches/metalfx/HuskFramegen.metal').read_text()
        helper = source[source.index('float4 fgMidpointFlow('):source.index('kernel void huskInterpolate(')]
        compiler = shutil.which('c++')
        self.assertIsNotNone(compiler, 'C++ compiler required for production arithmetic regression')
        harness = r'''
#include <cassert>
#include <cmath>
using uint = unsigned;
struct float2 { float x,y; };
float2 operator+(float2 a,float2 b){return {a.x+b.x,a.y+b.y};}
float2 operator-(float2 a,float2 b){return {a.x-b.x,a.y-b.y};}
float2 operator*(float a,float2 b){return {a*b.x,a*b.y};}
float2 operator/(float2 a,float2 b){return {a.x/b.x,a.y/b.y};}
struct float4 { float2 xy; float z,w; };
namespace access { constexpr int sample=0; }
constexpr int fgSampler=0;
template<class T,int A> struct texture2d {
    float a,b,c,d,tx,ty;
    float4 sample(int,float2 uv) const {
        float x=uv.x*64,y=uv.y*64;
        return {{a*x+b*y+tx,c*x+d*y+ty},.01f,1};
    }
};
'''
        cases = r'''
int main(){
    texture2d<float,access::sample> fields[]={
        {0,0,0,0,0,0}, {0,0,0,0,-8,4},
        {.5f,0,0,.25f,-24,-12}, {0,.3f,-.3f,0,-8,4}
    };
    for(auto field:fields)for(float x:{24.f,32.f,40.f})for(float y:{24.f,32.f,40.f}){
        float2 uv={x/64,y/64};
        auto f=fgMidpointFlow(field,uv,{64,64});
        float2 q={x-.5f*f.xy.x,y-.5f*f.xy.y};
        // Analytic inverse of (I + 0.5*A)*q = p - 0.5*t.
        float a=1+.5f*field.a,b=.5f*field.b,c=.5f*field.c,d=1+.5f*field.d;
        float px=x-.5f*field.tx,py=y-.5f*field.ty,det=a*d-b*c;
        float2 exact={(d*px-b*py)/det,(a*py-c*px)/det};
        assert(std::hypot(q.x-exact.x,q.y-exact.y)<.03f);
        assert(f.z==.01f && f.w==1);
    }
    auto old=fields[2].sample(fgSampler,{.5f,.5f});
    // Frozen171 looks up at p: q=(36,34); exact q=(35.2,33.777...).
    assert(std::hypot(32-.5f*old.xy.x-35.2f,32-.5f*old.xy.y-33.777777f)>.8f);
}
'''
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            (p / 'lookup.cpp').write_text('#include <initializer_list>\n' + harness + helper + cases)
            subprocess.run([compiler, '-std=c++17', '-Wall', '-Werror', str(p / 'lookup.cpp'), '-o', str(p / 'lookup')], check=True)
            subprocess.run([str(p / 'lookup')], check=True)

    def test_capture_metrics_distinguish_copy_corruption_and_detail_loss(self):
        source = (ROOT / 'patches/metalfx/HuskFGCapture.inc').read_text()
        code = source.split('// FG_IMAGE_METRICS_BEGIN', 1)[1].split('// FG_IMAGE_METRICS_END', 1)[0]
        harness = r"""
#include <cstdint>
#include <cmath>
#include <algorithm>
#include <cassert>
#include <cstring>
""" + code + r"""
int main(){
    uint8_t a[512]={},b[512]={};
    // Two rows, four RGB pixels; row padding and alpha are not image detail.
    for(unsigned y=0;y<2;y++)for(unsigned x=0;x<4;x++){
        for(unsigned c=0;c<3;c++)a[y*256+x*4+c]=(x%2)*200;
        a[y*256+x*4+3]=255;
    }
    std::memcpy(b,a,sizeof a);b[3]=0;b[30]=77;
    auto same=fgImageMetrics(a,b,4,2,256);
    assert(same.pixels==8 && same.changed==0 && same.maximumDifference==0);
    assert(same.referenceEdges==same.outputEdges);
    b[0]=10;auto damaged=fgImageMetrics(a,b,4,2,256);
    assert(damaged.changed==1 && damaged.maximumDifference==10 && damaged.absoluteDifference==10);
    for(unsigned y=0;y<2;y++)for(unsigned x=0;x<4;x++)for(unsigned c=0;c<3;c++)b[y*256+x*4+c]=100;
    auto blurred=fgImageMetrics(a,b,4,2,256);
    assert(blurred.changed==8 && blurred.referenceEdges>0 && blurred.outputEdges==0);
    assert(fgImageMetrics(a,b,0,0,256).pixels==0);
}
"""
        with tempfile.TemporaryDirectory() as d:
            p = Path(d); (p / 'metrics.cpp').write_text(harness)
            subprocess.run(['c++', '-std=c++17', '-Wall', '-Werror', str(p / 'metrics.cpp'), '-o', str(p / 'metrics')], check=True)
            subprocess.run([str(p / 'metrics')], check=True)

if __name__ == '__main__':
    unittest.main()
