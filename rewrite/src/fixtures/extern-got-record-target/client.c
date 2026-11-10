#define _GNU_SOURCE
#include <dlfcn.h>
#include <link.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
struct big { uint64_t a,b,c; };
extern void *m04_source(void);
extern int m04_provider(void);
extern struct big run_record_early(const void *);
struct mapping { uintptr_t address; int found; };
static int locate(struct dl_phdr_info *info, size_t size, void *opaque) {
 (void)size;
 struct mapping *m=opaque;
 for (ElfW(Half) i=0;i<info->dlpi_phnum;i++) {
  const ElfW(Phdr) *p=&info->dlpi_phdr[i];
  if (p->p_type != PT_LOAD || (p->p_flags & (PF_R|PF_X)) != (PF_R|PF_X)) continue;
  uintptr_t start=(uintptr_t)info->dlpi_addr+p->p_vaddr;
  if (m->address>=start && m->address-start<=p->p_memsz && p->p_memsz-(m->address-start)>=16) m->found=1;
 }
 return 0;
}
int main(int argc, char **argv) {
 if (argc!=2) return 90;
 int base=atoi(argv[1]);
 void *wrong=dlsym(RTLD_DEFAULT,"m04_wrong");
 if (!wrong || wrong!=m04_source() || m04_provider()!=base) return 20;
 Dl_info info; void *extra=NULL;
 if (!dladdr1(wrong,&info,&extra,RTLD_DL_SYMENT) || !extra || info.dli_saddr!=wrong || ((ElfW(Sym) *)extra)->st_size<16 || ELF64_ST_TYPE(((ElfW(Sym) *)extra)->st_info)!=STT_FUNC) return 23;
 struct mapping mapping={(uintptr_t)wrong,0}; dl_iterate_phdr(locate,&mapping);
 if (!mapping.found) return 24;
 /* The subject reads 16 raw bytes from a verified readable/executable segment.
  * The possible mutant target is a callable same-signature function. */
 struct big out=run_record_early(wrong);
 if (out.a==0 && out.b==0 && out.c==0) return 21;
 if (out.a!=(uint64_t)base+51 || out.b!=(uint64_t)base+52 || out.c!=(uint64_t)base+53) return 22;
 puts("record target check passed"); return 0;
}
