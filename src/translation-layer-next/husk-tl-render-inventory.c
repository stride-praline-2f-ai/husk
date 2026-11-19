/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-render-inventory.h"
#include <stdatomic.h>
#include <pthread.h>
#include <string.h>
#include <stddef.h>
#define GROUPS 256
#define SLOTS 512
static atomic_bool requested,active;
static atomic_uint inventory_mode; /* 0 off; 1 image-only; 2 full per-pass diagnostics */
static atomic_uint_fast64_t images,areas,capacity_drops,contention_drops;
static pthread_mutex_t mu=PTHREAD_MUTEX_INITIALIZER;
static tl_ri_group groups[GROUPS];
static uint16_t slots[SLOTS];
/* Assets cannot consume the capacity reserved for attachments and render areas. */
static const unsigned limits[3]={64,96,96};
static unsigned used[3];
static uint32_t length;
static uint64_t probes;
typedef struct {uint32_t type;const void *next;uint32_t flags,image_type,format,width,height,depth,mips,layers,samples,tiling,usage;} image_info;
typedef struct {uint32_t type;const void *next;uint64_t renderpass,framebuffer;int32_t x,y;uint32_t width,height;} begin_info;
_Static_assert(offsetof(image_info,width)==28&&offsetof(image_info,usage)==56&&offsetof(begin_info,width)==40,"Vulkan image/render-area ABI");
void husk_ue4_set_render_inventory_mode(uint32_t mode){
 if(mode>2)mode=2;
 atomic_store_explicit(&inventory_mode,mode,memory_order_release);
 atomic_store_explicit(&requested,mode!=0,memory_order_release);
}
void husk_ue4_set_render_inventory(bool value){husk_ue4_set_render_inventory_mode(value?2:0);}
uint32_t tl_ri_inventory_mode(void){return atomic_load_explicit(&inventory_mode,memory_order_acquire);}
bool tl_ri_area_active(void){return tl_ri_active()&&tl_ri_inventory_mode()>=2;}
void tl_ri_activate(const char *project){
 atomic_store(&active,false);pthread_mutex_lock(&mu);
 memset(groups,0,sizeof(groups));memset(slots,0,sizeof(slots));memset(used,0,sizeof(used));length=0;probes=0;
 atomic_store(&images,0);atomic_store(&areas,0);atomic_store(&capacity_drops,0);atomic_store(&contention_drops,0);
 atomic_store(&active,atomic_load(&requested)&&project&&!strcmp(project,"Dungeons"));pthread_mutex_unlock(&mu);
}
bool tl_ri_active(void){return atomic_load_explicit(&active,memory_order_relaxed);}
static uint64_t key_hash(tl_ri_group v){
 uint32_t fields[]={v.kind,v.width,v.height,v.depth,v.format,v.usage,v.samples};
 uint64_t h=1469598103934665603ULL;
 for(unsigned i=0;i<7;i++){h^=fields[i];h*=1099511628211ULL;h^=h>>32;}
 return h;
}
static bool equal(tl_ri_group a,tl_ri_group b){
 return a.kind==b.kind&&a.width==b.width&&a.height==b.height&&a.depth==b.depth&&a.format==b.format&&a.usage==b.usage&&a.samples==b.samples;
}
static void record(tl_ri_group value){
 if(!value.width||!value.height)return;
 if(value.kind==0)atomic_fetch_add(&images,1);else atomic_fetch_add(&areas,1);
 if(pthread_mutex_trylock(&mu)){atomic_fetch_add(&contention_drops,1);return;}
 if(!atomic_load(&active)){pthread_mutex_unlock(&mu);return;}
 unsigned slot=(unsigned)key_hash(value)&(SLOTS-1),scan=0;
 for(;scan<SLOTS;scan++,slot=(slot+1)&(SLOTS-1)){
  probes++;
  if(!slots[slot])break;
  unsigned index=slots[slot]-1;
  if(equal(groups[index],value)){groups[index].count++;pthread_mutex_unlock(&mu);return;}
 }
 unsigned kind=value.kind==1?2:(value.usage&(0x10u|0x20u|0x8u))?1:0;
 if(scan==SLOTS||length==GROUPS||used[kind]>=limits[kind])atomic_fetch_add(&capacity_drops,1);
 else {value.count=1;groups[length]=value;slots[slot]=(uint16_t)(++length);used[kind]++;}
 pthread_mutex_unlock(&mu);
}
void tl_ri_image(const void *raw){
 if(!atomic_load_explicit(&active,memory_order_relaxed)||!raw)return;
 const image_info *p=raw;if(p->type!=14)return;
 record((tl_ri_group){.kind=0,.width=p->width,.height=p->height,.depth=p->depth,.format=p->format,.usage=p->usage,.samples=p->samples});
}
void tl_ri_render_area(const void *raw){
 if(!atomic_load_explicit(&active,memory_order_relaxed)||tl_ri_inventory_mode()<2||!raw)return;
 const begin_info *p=raw;if(p->type!=43)return;
 record((tl_ri_group){.kind=1,.width=p->width,.height=p->height,.depth=1});
}
uint32_t tl_ri_snapshot(tl_ri_group *out,uint32_t capacity,tl_ri_stats *stats){
 pthread_mutex_lock(&mu);
 uint64_t full=atomic_load(&capacity_drops),busy=atomic_load(&contention_drops);
 if(stats)*stats=(tl_ri_stats){.requested=atomic_load(&requested),.active=atomic_load(&active),
   .observed_images=atomic_load(&images),.observed_render_areas=atomic_load(&areas),.dropped=full+busy,
   .dropped_capacity=full,.dropped_contention=busy,.hash_probes=probes,
   .asset_groups=used[0],.target_groups=used[1],.area_groups=used[2]};
 uint32_t n=out?(capacity<length?capacity:length):0;if(n)memcpy(out,groups,n*sizeof(*out));
 pthread_mutex_unlock(&mu);return n;
}

/* Vulkan 1.x VkFormat numeric values. Classify only metadata, never infer
 * a texture's scene meaning or replace engine-provided motion/depth.
 * A floating-point RGBA colour target can also resemble a velocity target. */
static bool ri_depth_format(uint32_t format)
{
 return format==124u||format==125u||format==126u||format==128u||format==129u||format==130u;
}
static bool ri_vector_format(uint32_t format)
{
 return format==83u || format==103u || format==97u;
}
static bool ri_color_format(uint32_t format)
{
 return !ri_depth_format(format) && format>0u;
}
void tl_ri_metalfx_snapshot(tl_ri_metalfx_candidates *out)
{
 if(!out)return;
 tl_ri_metalfx_candidates result={0};
 result.version=1;result.size=sizeof(result);
 pthread_mutex_lock(&mu);
 result.active=atomic_load_explicit(&active,memory_order_relaxed);
 result.lost_observations=atomic_load_explicit(&capacity_drops,memory_order_relaxed)+
                          atomic_load_explicit(&contention_drops,memory_order_relaxed);
 for(uint32_t i=0;i<length;i++){
  const tl_ri_group *g=&groups[i];
  if(g->kind!=0||!g->width||!g->height||g->depth!=1||g->samples!=1)continue;
  result.retained_image_groups++;
  bool read=(g->usage & (0x4u|0x1u))!=0; /* SAMPLED or TRANSFER_SRC */
  bool render=(g->usage & 0x10u)!=0; /* COLOR_ATTACHMENT */
  bool depth=(g->usage & 0x20u)!=0; /* DEPTH_STENCIL_ATTACHMENT */
  bool storage=(g->usage & 0x8u)!=0; /* STORAGE */
  if(ri_depth_format(g->format)&&depth){
   result.depth_attachment_groups++;
   if(read)result.readable_depth_groups++;
  }
  if(ri_vector_format(g->format) && (render||storage)){
   result.vector_format_groups++;
   if(read)result.writable_vector_groups++;
  }
  if(ri_color_format(g->format)&&render){
   result.renderable_color_groups++;
   if(read)result.readable_color_groups++;
  }
 }
 pthread_mutex_unlock(&mu);
 *out=result;
}
