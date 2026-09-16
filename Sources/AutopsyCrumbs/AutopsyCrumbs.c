//
//  AutopsyCrumbs.c
//  AutopsyCrumbs
//

#include "AutopsyCrumbs.h"
#include <stdatomic.h>
#include <string.h>

// `used`: nothing dereferences the block by name from Swift once the accessors
// are inlined, and the linker must not strip the section the reader looks for.
__attribute__((used, section(AUTOPSY_CRUMBS_SEGMENT "," AUTOPSY_CRUMBS_SECTION)))
autopsy_crumbs_t autopsy_crumbs = {
	.magic = AUTOPSY_CRUMBS_MAGIC,
	.version = AUTOPSY_CRUMBS_VERSION,
	.line_length = AUTOPSY_LINE_LENGTH,
	.line_count = AUTOPSY_LINE_COUNT,
	.written = 0,
};

const autopsy_crumbs_t *autopsy_crumbs_pointer(void) {
	return &autopsy_crumbs;
}

static void copy_field(char *field, size_t length, const char *value) {
	if (value == NULL) { field[0] = 0; return; }
	strlcpy(field, value, length);
}

void autopsy_crumbs_set_run_id(const char *run_id) {
	copy_field(autopsy_crumbs.run_id, AUTOPSY_RUN_ID_LENGTH, run_id);
}

void autopsy_crumbs_set_screen(const char *screen) {
	copy_field(autopsy_crumbs.screen, AUTOPSY_SCREEN_LENGTH, screen);
}

void autopsy_crumbs_append(const char *line) {
	if (line == NULL) return;
	uint32_t index = atomic_fetch_add((_Atomic uint32_t *)&autopsy_crumbs.written, 1);
	copy_field(autopsy_crumbs.lines[index % AUTOPSY_LINE_COUNT], AUTOPSY_LINE_LENGTH, line);
}
