//
//  NewsHelicopterCrumbs.c
//  NewsHelicopterCrumbs
//

#include "NewsHelicopterCrumbs.h"
#include <stdatomic.h>
#include <string.h>

// `used`: nothing dereferences the block by name from Swift once the accessors
// are inlined, and the linker must not strip the section the reader looks for.
__attribute__((used, section(NEWS_HELICOPTER_CRUMBS_SEGMENT "," NEWS_HELICOPTER_CRUMBS_SECTION)))
news_helicopter_crumbs_t news_helicopter_crumbs = {
	.magic = NEWS_HELICOPTER_CRUMBS_MAGIC,
	.version = NEWS_HELICOPTER_CRUMBS_VERSION,
	.line_length = NEWS_HELICOPTER_LINE_LENGTH,
	.line_count = NEWS_HELICOPTER_LINE_COUNT,
	.written = 0,
};

const news_helicopter_crumbs_t *news_helicopter_crumbs_pointer(void) {
	return &news_helicopter_crumbs;
}

static void copy_field(char *field, size_t length, const char *value) {
	if (value == NULL) { field[0] = 0; return; }
	strlcpy(field, value, length);
}

void news_helicopter_crumbs_set_run_id(const char *run_id) {
	copy_field(news_helicopter_crumbs.run_id, NEWS_HELICOPTER_RUN_ID_LENGTH, run_id);
}

void news_helicopter_crumbs_set_screen(const char *screen) {
	copy_field(news_helicopter_crumbs.screen, NEWS_HELICOPTER_SCREEN_LENGTH, screen);
}

void news_helicopter_crumbs_append(const char *line) {
	if (line == NULL) return;
	uint32_t index = atomic_fetch_add((_Atomic uint32_t *)&news_helicopter_crumbs.written, 1);
	copy_field(news_helicopter_crumbs.lines[index % NEWS_HELICOPTER_LINE_COUNT], NEWS_HELICOPTER_LINE_LENGTH, line);
}
