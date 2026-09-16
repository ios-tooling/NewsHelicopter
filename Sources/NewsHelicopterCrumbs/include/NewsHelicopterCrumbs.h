//
//  NewsHelicopterCrumbs.h
//  NewsHelicopterCrumbs
//
//  A fixed block the app writes into as it runs and the crash extension reads
//  out of the corpse. It lives in its own Mach-O section (__DATA,__helicopter) so
//  the extension can find it without symbols — a Release build strips them —
//  by walking the main executable's load commands. Plain C with fixed-size
//  fields: the reader parses the layout by offset, and a struct that Swift
//  laid out would not be a layout at all.
//

#ifndef NEWS_HELICOPTER_CRUMBS_H
#define NEWS_HELICOPTER_CRUMBS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NEWS_HELICOPTER_CRUMBS_SEGMENT "__DATA"
#define NEWS_HELICOPTER_CRUMBS_SECTION "__helicopter"
/// "NEWSHELI" — the reader trusts nothing that does not start with it.
#define NEWS_HELICOPTER_CRUMBS_MAGIC 0x494C45485357454EULL
#define NEWS_HELICOPTER_CRUMBS_VERSION 1
#define NEWS_HELICOPTER_RUN_ID_LENGTH 40
#define NEWS_HELICOPTER_SCREEN_LENGTH 128
#define NEWS_HELICOPTER_LINE_LENGTH 160
#define NEWS_HELICOPTER_LINE_COUNT 24

typedef struct {
	uint64_t magic;
	uint32_t version;
	uint32_t line_length;
	uint32_t line_count;
	/// Lines written so far; the ring holds the last `line_count` of them.
	uint32_t written;
	char run_id[NEWS_HELICOPTER_RUN_ID_LENGTH];
	char screen[NEWS_HELICOPTER_SCREEN_LENGTH];
	char lines[NEWS_HELICOPTER_LINE_COUNT][NEWS_HELICOPTER_LINE_LENGTH];
} news_helicopter_crumbs_t;

/// The block itself, in the executable that links this library, and the
/// address Swift reads it through (a global is not something Swift 6 will
/// let a caller touch directly).
extern news_helicopter_crumbs_t news_helicopter_crumbs;
const news_helicopter_crumbs_t *news_helicopter_crumbs_pointer(void);

/// Stamp this launch, so a report can be matched to the run it came from.
void news_helicopter_crumbs_set_run_id(const char *run_id);
/// Where the reader is right now; overwritten, not appended.
void news_helicopter_crumbs_set_screen(const char *screen);
/// Add a line to the ring. Safe from any thread; two writers racing may
/// interleave, which a crash report can live with.
void news_helicopter_crumbs_append(const char *line);

#ifdef __cplusplus
}
#endif

#endif
