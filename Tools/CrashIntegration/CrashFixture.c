__attribute__((noinline,visibility("default")))
void ok_crash_acceptance_fault(void) {
    volatile int *address = (volatile int *)0;
    *address = 1;
}
