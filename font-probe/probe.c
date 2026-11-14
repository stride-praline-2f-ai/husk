#include <stdio.h>
#include "husk-tl-dvm-graphics.c"
static const char *font_path;
const char *tl_path_resolve(const char *path,char *buffer,size_t capacity) { (void)path;snprintf(buffer,capacity,"%s",font_path);return buffer; }
static void show(const char *label,CTFontRef f) {
 CFStringRef name=CTFontCopyPostScriptName(f);char text[256];CFStringGetCString(name,text,sizeof(text),kCFStringEncodingUTF8);CFRelease(name);
 printf("%s name=%s\n",label,text);
 CFDictionaryRef v=CTFontCopyVariation(f);if(v){CFShow(v);CFRelease(v);}
}
int main(int argc,char **argv) { if(argc!=2)return 2;font_path=argv[1];
 CTFontRef base=roboto();if(!base)return 3;show("descriptor-first",base);
 gface *normal=face_family("sans-serif",0);show("husk-normal",normal->base);
 CTFontRef regular=with_weight(base,400,false);show("weight400",regular);
 CTFontRef medium=with_weight(base,500,false);show("weight500",medium);
 CTFontRef bold=with_weight(base,700,false);show("weight700",bold);
 return 0;
}
