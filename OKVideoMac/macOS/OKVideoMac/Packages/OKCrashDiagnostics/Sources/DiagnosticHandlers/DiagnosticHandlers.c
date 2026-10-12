#include "DiagnosticHandlers.h"
#include <mach/mach.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
// Read-only probe. Keep send rights until comparison: deallocating them between
// queries lets macOS rename an unchanged port, producing a false mismatch.
typedef struct {
    uintptr_t signals[6];
    exception_mask_t masks[EXC_TYPES_COUNT];
    mach_port_t ports[EXC_TYPES_COUNT];
    exception_behavior_t behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t count;
} Snapshot;
void ok_diagnostic_handlers_free(void *opaque) {
    Snapshot *s=opaque; if(!s)return;
    for(unsigned i=0;i<s->count;i++)if(MACH_PORT_VALID(s->ports[i]))mach_port_deallocate(mach_task_self(),s->ports[i]);
    free(s);
}
void *ok_diagnostic_handlers_snapshot(void) {
    Snapshot *s=calloc(1,sizeof(*s)); if(!s)return NULL;
    const int signals[]={SIGABRT,SIGBUS,SIGFPE,SIGILL,SIGSEGV,SIGTRAP};
    for(unsigned i=0;i<6;i++) { struct sigaction a={0};if(sigaction(signals[i],NULL,&a)!=0){free(s);return NULL;}s->signals[i]=(uintptr_t)a.sa_sigaction; }
    s->count=EXC_TYPES_COUNT;
    if(task_get_exception_ports(mach_task_self(),EXC_MASK_ALL,s->masks,&s->count,s->ports,s->behaviors,s->flavors)!=KERN_SUCCESS){free(s);return NULL;}
    return s;
}
bool ok_diagnostic_handlers_match(void *opaque) {
    Snapshot *a=opaque,*b=ok_diagnostic_handlers_snapshot(); bool equal=false;
    if(a&&b&&a->count==b->count) {
        equal=memcmp(a->signals,b->signals,sizeof(a->signals))==0;
        for(unsigned i=0;i<a->count&&equal;i++)equal=a->masks[i]==b->masks[i]&&a->ports[i]==b->ports[i]&&a->behaviors[i]==b->behaviors[i]&&a->flavors[i]==b->flavors[i];
    }
    ok_diagnostic_handlers_free(b);return equal;
}
