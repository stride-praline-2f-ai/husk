/* SPDX-License-Identifier: GPL-2.0-or-later
 * Verify the actual library containing the FG entrypoint against the signed
 * app's build contract. Optional FG refuses before changing the source FPS if
 * the reviewed model is missing/stale. No environment or guest-CVar bypass.
 */
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <mach-o/loader.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

static NSString *fg_code_digest(NSData *data) {
    if(data.length<sizeof(struct mach_header_64))return nil;
    const uint8_t *bytes=data.bytes;const struct mach_header_64 *h=(const void*)bytes;
    if(h->magic!=MH_MAGIC_64||h->ncmds>4096||(uint64_t)sizeof(*h)+h->sizeofcmds>data.length)return nil;
    size_t offset=sizeof(*h),end=offset+h->sizeofcmds;
    for(unsigned n=0;n<h->ncmds;n++){
        if(offset+sizeof(struct load_command)>end)return nil;
        const struct load_command *lc=(const void*)(bytes+offset);
        if(lc->cmdsize<sizeof(*lc)||offset+lc->cmdsize>end)return nil;
        if(lc->cmd==LC_SEGMENT_64){
            if(lc->cmdsize<sizeof(struct segment_command_64))return nil;
            const struct segment_command_64 *segment=(const void*)lc;
            if((uint64_t)sizeof(*segment)+(uint64_t)segment->nsects*sizeof(struct section_64)>lc->cmdsize)return nil;
            const struct section_64 *sections=(const void*)(segment+1);
            for(unsigned s=0;s<segment->nsects;s++){
                const struct section_64 *section=sections+s;
                if(strncmp(section->sectname,"__text",16)||strncmp(section->segname,"__TEXT",16))continue;
                if(!section->size||section->size>(64ULL<<20)||(uint64_t)section->offset+section->size>data.length)return nil;
                unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes+section->offset,(CC_LONG)section->size,digest);
                char hex[65];for(unsigned i=0;i<sizeof digest;i++)snprintf(hex+2*i,3,"%02x",digest[i]);return [NSString stringWithUTF8String:hex];
            }
        }
        offset+=lc->cmdsize;
    }
    return nil;
}
bool tl_fg_contract_verify(void *entrypoint,const char *contract_path,const char *app_source) {
    @autoreleasepool {
        if(!entrypoint||!contract_path||!app_source)return false;
        NSData *record=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:contract_path]];
        if(!record||record.length>128*1024)return false;
        id parsed=[NSJSONSerialization JSONObjectWithData:record options:0 error:nil];
        if(![parsed isKindOfClass:NSDictionary.class])return false;
        NSDictionary *contract=parsed;NSString *source=[NSString stringWithUTF8String:app_source];
        if([source hasSuffix:@"-dirty"])source=[source substringToIndex:source.length-6];
        if(![contract[@"schema"] isKindOfClass:NSNumber.class]||![contract[@"model"] isKindOfClass:NSNumber.class]||![contract[@"app_source"] isKindOfClass:NSString.class])return false;
        if([contract[@"schema"] intValue]!=1||[contract[@"model"] intValue]!=3||![contract[@"app_source"] isEqual:source])return false;
        Dl_info info={0};if(!dladdr(entrypoint,&info)||!info.dli_fname)return false;
        NSString *path=[NSString stringWithUTF8String:info.dli_fname],*name=path.lastPathComponent;
        id libraries=contract[@"libraries"];if(![libraries isKindOfClass:NSDictionary.class])return false;
        id entry=libraries[name];if(![entry isKindOfClass:NSDictionary.class])return false;
        NSString *expected=entry[@"code_sha256"];if(![expected isKindOfClass:NSString.class]||expected.length!=64)return false;
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        if(!attrs||[attrs[NSFileSize] unsignedLongLongValue]>(128ULL<<20))return false;
        NSData *image=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];NSString *actual=fg_code_digest(image);
        if(!actual||![actual isEqual:expected])return false;
        fprintf(stderr,"[M9-FG-CONTRACT] enforced model3 for %s; actual loaded entrypoint code SHA256 %s verified; no game-CVar/environment bypass\n",name.UTF8String,actual.UTF8String);
        return true;
    }
}
