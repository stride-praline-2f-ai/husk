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
static atomic_uint_fast64_t dropped_assets,dropped_targets,dropped_areas;
static pthread_mutex_t mu=PTHREAD_MUTEX_INITIALIZER;
static tl_ri_group groups[GROUPS];
static uint16_t slots[SLOTS];
/* Assets cannot consume the capacity reserved for attachments and render areas. */
static const unsigned limits[3]={64,96,96};
static unsigned used[3];
static uint32_t length;
static uint64_t probes;
/* Retain ONLY currently live Vulkan target handles and their view/framebuffer
 * links. Metadata ownership stays with the guest; no GPU textures are copied.
 * Explicit full inventory can additionally count renderpass use. */
#define RI_IMAGES 512
#define RI_VIEWS 1024
#define RI_FRAMEBUFFERS 256
typedef struct {void *device;uint64_t image;uint32_t format,usage,width,height;} ri_image;
typedef struct {void *device;uint64_t view,image;} ri_view;
typedef struct {void *device;uint64_t framebuffer;uint8_t flags;} ri_framebuffer;
static ri_image live_images[RI_IMAGES];
static ri_view live_views[RI_VIEWS];
static ri_framebuffer live_framebuffers[RI_FRAMEBUFFERS];
static tl_ri_lineage_stats lineage;

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
 memset(live_images,0,sizeof(live_images));memset(live_views,0,sizeof(live_views));
 memset(live_framebuffers,0,sizeof(live_framebuffers));
 lineage=(tl_ri_lineage_stats){.version=1,.size=sizeof(lineage)};
 atomic_store(&images,0);atomic_store(&areas,0);atomic_store(&capacity_drops,0);atomic_store(&contention_drops,0);
 atomic_store(&dropped_assets,0);atomic_store(&dropped_targets,0);atomic_store(&dropped_areas,0);
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
 if(scan==SLOTS||length==GROUPS||used[kind]>=limits[kind]){
  atomic_fetch_add_explicit(&capacity_drops,1,memory_order_relaxed);
  if(kind==0)atomic_fetch_add_explicit(&dropped_assets,1,memory_order_relaxed);
  else if(kind==1)atomic_fetch_add_explicit(&dropped_targets,1,memory_order_relaxed);
  else atomic_fetch_add_explicit(&dropped_areas,1,memory_order_relaxed);
 } else {value.count=1;groups[length]=value;slots[slot]=(uint16_t)(++length);used[kind]++;}
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
   .asset_groups=used[0],.target_groups=used[1],.area_groups=used[2],
   .dropped_capacity_assets=atomic_load_explicit(&dropped_assets,memory_order_relaxed),
   .dropped_capacity_targets=atomic_load_explicit(&dropped_targets,memory_order_relaxed),
   .dropped_capacity_areas=atomic_load_explicit(&dropped_areas,memory_order_relaxed)};
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
 result.lost_asset_observations=atomic_load_explicit(&dropped_assets,memory_order_relaxed);
 result.lost_target_observations=atomic_load_explicit(&dropped_targets,memory_order_relaxed);
 result.lost_render_area_observations=atomic_load_explicit(&dropped_areas,memory_order_relaxed);
 result.lost_contention_observations=atomic_load_explicit(&contention_drops,memory_order_relaxed);
 result.lost_observations=result.lost_asset_observations+result.lost_target_observations+
                          result.lost_render_area_observations+result.lost_contention_observations;
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

/* ABI-compatible Vulkan 64-bit creation-info prefixes. Validate type before
 * field access and bound guest-provided attachment counts. */
typedef struct {uint32_t type;const void *next;uint32_t flags;uint64_t image;uint32_t view_type,format;} ri_view_create;
typedef struct {uint32_t type;const void *next;uint32_t flags;uint64_t renderpass;uint32_t attachments;const uint64_t *views;uint32_t width,height,layers;} ri_fb_create;
_Static_assert(offsetof(ri_view_create,image)==24&&offsetof(ri_view_create,format)==36&&offsetof(ri_fb_create,views)==40&&offsetof(ri_fb_create,width)==48,"Vulkan resource lineage ABI");

static ri_image *ri_find_image(void *device,uint64_t image){
 for(unsigned i=0;i<RI_IMAGES;i++)if(live_images[i].device==device&&live_images[i].image==image&&image)return &live_images[i];
 return NULL;
}
static ri_view *ri_find_view(void *device,uint64_t view){
 for(unsigned i=0;i<RI_VIEWS;i++)if(live_views[i].device==device&&live_views[i].view==view&&view)return &live_views[i];
 return NULL;
}
void tl_ri_image_created(void *device,uint64_t image,const void *raw){
 if(!tl_ri_active()||!raw||!image||!device)return;
 const image_info *p=raw;
 if(p->type!=14||!(p->usage&(0x8u|0x10u|0x20u)))return;
 if(pthread_mutex_trylock(&mu)){atomic_fetch_add(&contention_drops,1);return;}
 ri_image *slot=ri_find_image(device,image);
 if(!slot)for(unsigned i=0;i<RI_IMAGES;i++)if(!live_images[i].image){slot=&live_images[i];break;}
 if(slot){*slot=(ri_image){device,image,p->format,p->usage,p->width,p->height};lineage.tracked_target_images++;}
 else lineage.dropped_records++;
 pthread_mutex_unlock(&mu);
}
void tl_ri_image_destroyed(void *device,uint64_t image){
 if(!tl_ri_active()||!image)return;
 if(pthread_mutex_trylock(&mu)){atomic_fetch_add(&contention_drops,1);return;}
 ri_image *slot=ri_find_image(device,image);if(slot)memset(slot,0,sizeof(*slot));
 pthread_mutex_unlock(&mu);
}
void tl_ri_view_created(void *device,uint64_t view,const void *raw){
 if(!tl_ri_active()||!raw||!view||!device)return;
 const ri_view_create *p=raw;if(p->type!=15||!p->image)return;
 if(pthread_mutex_trylock(&mu)){atomic_fetch_add(&contention_drops,1);return;}
 ri_image *image=ri_find_image(device,p->image);
 if(image){
  ri_view *slot=ri_find_view(device,view);
  if(!slot)for(unsigned i=0;i<RI_VIEWS;i++)if(!live_views[i].view){slot=&live_views[i];break;}
  if(slot){*slot=(ri_view){device,view,p->image};lineage.tracked_target_views++;}
  else lineage.dropped_records++;
 } else lineage.missing_image_view_links++;
 pthread_mutex_unlock(&mu);
}
void tl_ri_view_destroyed(void *device,uint64_t view){
 if(!tl_ri_active()||!view)return;
 if(pthread_mutex_trylock(&mu)){atomic_fetch_add(&contention_drops,1);return;}
 ri_view *slot=ri_find_view(device,view);if(slot)memset(slot,0,sizeof(*slot));
 pthread_mutex_unlock(&mu);
}
void tl_ri_framebuffer_created(void *device,uint64_t framebuffer,const void *raw){
 if(!tl_ri_active()||!raw||!framebuffer||!device)return;
 const ri_fb_create *p=raw;
 if(p->type!=37||!p->views||!p->attachments||p->attachments>32)return;
 if(pthread_mutex_trylock(&mu)){atomic_fetch_add(&contention_drops,1);return;}
 uint8_t flags=0;
 for(uint32_t i=0;i<p->attachments;i++){
  ri_view *view=ri_find_view(device,p->views[i]);
  ri_image *image=view?ri_find_image(device,view->image):NULL;
  if(!image){lineage.missing_framebuffer_view_links++;continue;}
  if(ri_depth_format(image->format)&&(image->usage&0x20u))flags|=1;
  if(ri_vector_format(image->format)&&(image->usage&0x18u))flags|=2;
 }
 ri_framebuffer *slot=NULL;
 for(unsigned i=0;i<RI_FRAMEBUFFERS;i++)if(live_framebuffers[i].device==device&&live_framebuffers[i].framebuffer==framebuffer){slot=&live_framebuffers[i];break;}
 if(!slot)for(unsigned i=0;i<RI_FRAMEBUFFERS;i++)if(!live_framebuffers[i].framebuffer){slot=&live_framebuffers[i];break;}
 if(slot){
  *slot=(ri_framebuffer){device,framebuffer,flags};
  lineage.tracked_framebuffers++;
  if(flags&1)lineage.depth_framebuffers++;
  if(flags&2)lineage.vector_like_framebuffers++;
  if(flags==3)lineage.mixed_depth_vector_framebuffers++;
 }else lineage.dropped_records++;
 pthread_mutex_unlock(&mu);
}
void tl_ri_framebuffer_destroyed(void *device,uint64_t framebuffer){
 if(!tl_ri_active()||!framebuffer)return;
 if(pthread_mutex_trylock(&mu)){atomic_fetch_add(&contention_drops,1);return;}
 for(unsigned i=0;i<RI_FRAMEBUFFERS;i++)if(live_framebuffers[i].device==device&&live_framebuffers[i].framebuffer==framebuffer){memset(&live_framebuffers[i],0,sizeof(live_framebuffers[i]));break;}
 pthread_mutex_unlock(&mu);
}
void tl_ri_pass_begin(const void *raw){
 if(!tl_ri_area_active()||!raw)return;
 const begin_info *p=raw;if(p->type!=43||!p->framebuffer)return;
 if(pthread_mutex_trylock(&mu)){atomic_fetch_add(&contention_drops,1);return;}
 /* Opaque framebuffer handles are unique among live objects for a device;
  * this explicit pass probe does not imply rendering really completed. */
 for(unsigned i=0;i<RI_FRAMEBUFFERS;i++)if(live_framebuffers[i].framebuffer==p->framebuffer){
  if(live_framebuffers[i].flags&1)lineage.used_depth_framebuffers++;
  if(live_framebuffers[i].flags&2)lineage.used_vector_like_framebuffers++;
  break;
 }
 pthread_mutex_unlock(&mu);
}
void tl_ri_lineage_snapshot(tl_ri_lineage_stats *out){
 if(!out)return;
 pthread_mutex_lock(&mu);*out=lineage;pthread_mutex_unlock(&mu);
}
