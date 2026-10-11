#include <stdbool.h>
void *cvp_handlers_snapshot(void);
bool cvp_handlers_match(void *snapshot);
void cvp_handlers_free(void *snapshot);
