#include <stdbool.h>
void *ok_diagnostic_handlers_snapshot(void);
bool ok_diagnostic_handlers_match(void *snapshot);
void ok_diagnostic_handlers_free(void *snapshot);
