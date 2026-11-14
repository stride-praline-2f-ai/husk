
#include <assert.h>
#include <stdio.h>
#include "husk-tl-dvm-graphics.c"
static const char *font_path;
const char *tl_path_resolve(const char *path,char *buffer,size_t capacity) {(void)path;snprintf(buffer,capacity,"%s",font_path);return buffer;}
static int actual_weight(CTFontRef f) {
 int tag=0x77676874;CFNumberRef key=CFNumberCreate(NULL,kCFNumberIntType,&tag);
 CFDictionaryRef values=CTFontCopyVariation(f);CFNumberRef number=values?CFDictionaryGetValue(values,key):NULL;
 double weight=-1;
 if(number)CFNumberGetValue(number,kCFNumberDoubleType,&weight);
 else {
  CFArrayRef axes=CTFontCopyVariationAxes(f);
  for(CFIndex i=0;axes && i<CFArrayGetCount(axes);i++) {
   CFDictionaryRef axis=CFArrayGetValueAtIndex(axes,i);int identifier=0;
   CFNumberRef axisID=CFDictionaryGetValue(axis,kCTFontVariationAxisIdentifierKey);
   if(axisID && CFNumberGetValue(axisID,kCFNumberIntType,&identifier) && identifier==tag) {
    CFNumberRef fallback=CFDictionaryGetValue(axis,kCTFontVariationAxisDefaultValueKey);
    if(fallback)CFNumberGetValue(fallback,kCFNumberDoubleType,&weight);
   }
  }
  if(axes)CFRelease(axes);
 }
 if(values)CFRelease(values);CFRelease(key);assert(weight>=0);return (int)weight;
}
static double coverage(CTFontRef font) {
 int width=1100,height=100;uint8_t *pixels=calloc((size_t)width*height,4);
 CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
 CGContextRef c=CGBitmapContextCreate(pixels,width,height,8,width*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);assert(c);
 CGContextSetRGBFillColor(c,1,1,1,1);CGContextFillRect(c,CGRectMake(0,0,width,height));
 CGContextSetRGBFillColor(c,0,0,0,1);CGContextSetShouldAntialias(c,true);
 CTFontRef sizedFont=CTFontCreateCopyWithAttributes(font,42,NULL,NULL);
 const void *keys[]={kCTFontAttributeName,kCTForegroundColorFromContextAttributeName};const void *values[]={sizedFont,kCFBooleanTrue};
 CFDictionaryRef attrs=CFDictionaryCreate(NULL,keys,values,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 CFAttributedStringRef str=CFAttributedStringCreate(NULL,CFSTR("AnkiDroid Collection is empty"),attrs);CTLineRef line=CTLineCreateWithAttributedString(str);
 CGContextSetTextPosition(c,10,35);CTLineDraw(line,c);
 double sum=0;for(int i=0;i<width*height;i++)sum+=255-pixels[i*4];
 CFRelease(line);CFRelease(str);CFRelease(attrs);CFRelease(sizedFont);CGContextRelease(c);CGColorSpaceRelease(space);free(pixels);return sum;
}
int main(int argc,char **argv) {
 assert(argc==2);font_path=argv[1];CTFontRef base=roboto();assert(base);
 CTFontRef thin=with_weight(base,100,false);assert(actual_weight(thin)==100);
 // This recreates the old 400 special case: retaining this named instance leaves weight100.
 CTFontRef normalized=with_weight(thin,400,false);assert(actual_weight(normalized)==400);
 gface *normal=face_family("sans-serif",0);assert(actual_weight(normal->base)==400);
 CTFontRef cache1=sized(normal,42),cache2=sized(normal,42);assert(actual_weight(cache1)==400 && actual_weight(cache2)==400);
 gface *medium=face_family("sans-serif-medium",0);assert(actual_weight(medium->base)==500);
 gface *light=face_family("sans-serif-light",0);assert(actual_weight(light->base)==300);
 gface *bold=face_family("sans-serif",1);assert(actual_weight(bold->base)==700);
 CTFontRef italic=with_weight(base,400,true);assert(actual_weight(italic)==400);
 int italTag=0x6974616c;CFNumberRef italKey=CFNumberCreate(NULL,kCFNumberIntType,&italTag);
 CFDictionaryRef italValues=CTFontCopyVariation(italic);double italValue=0;
 assert(italValues && CFNumberGetValue(CFDictionaryGetValue(italValues,italKey),kCFNumberDoubleType,&italValue) && italValue==1);
 CFStringRef family=CTFontCopyFamilyName(italic);assert(CFStringFind(family,CFSTR("Roboto"),0).location!=kCFNotFound);
 CFRelease(family);CFRelease(italValues);CFRelease(italKey);
 double oldCoverage=coverage(thin),fixedCoverage=coverage(normal->base);
 assert(oldCoverage>0 && fixedCoverage>oldCoverage*1.25);
 printf("CoreText regular100->400, sized cache, light300/medium500/bold700/italic preserved; same-size glyph coverage %.0f -> %.0f passed\n",oldCoverage,fixedCoverage);
 CFRelease(cache1);CFRelease(cache2);CFRelease(thin);CFRelease(normalized);CFRelease(italic);return 0;
}
