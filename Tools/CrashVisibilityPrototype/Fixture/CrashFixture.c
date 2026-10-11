#include <sys/mman.h>
#include <unistd.h>
#include <stdlib.h>

__attribute__((noinline)) static void cvp_faulting_write(volatile unsigned char *page) {
    *page = 42; // Deliberately access a PROT_NONE guard page in this prototype only.
}
__attribute__((visibility("default"), noinline)) void cvp_crash_fixture(void) {
    long pageSize = sysconf(_SC_PAGESIZE);
    void *page = mmap(NULL, (size_t)pageSize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED) abort();
    cvp_faulting_write(page);
    munmap(page, (size_t)pageSize); // Prevent a tail call from removing this frame.
}
