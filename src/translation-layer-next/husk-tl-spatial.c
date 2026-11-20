/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-spatial.h"
bool tl_spatial_dimensions(int width,int height,int percent,tl_spatial_config *out) {
    if(!out||width<64||height<64||width>8192||height>8192||percent<50||percent>=100)return false;
    /* Round to the nearest 8-pixel boundary instead of flooring both axes.
     * 1816x1280 Duo output: 50%=912x640, 60%=1088x768,
     * 67%=1216x856. This avoids gratuitous aspect-ratio drift.
     */
    int w=((width*percent+400)/800)*8,h=((height*percent+400)/800)*8;
    if(w<64||h<64||w>=width||h>=height)return false;
    double ratio=(double)w*height/((double)h*width);
    if(ratio<0.99||ratio>1.01)return false;
    *out=(tl_spatial_config){1,sizeof(*out),(uint32_t)w,(uint32_t)h,(uint32_t)width,(uint32_t)height,1,0};
    return true;
}
