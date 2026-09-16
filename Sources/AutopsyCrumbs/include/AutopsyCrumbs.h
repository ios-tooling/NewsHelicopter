//
//  AutopsyCrumbs.h
//  AutopsyCrumbs
//
//  A fixed block the app writes into as it runs and the crash extension reads
//  out of the corpse. It lives in its own Mach-O section (__DATA,__autopsy) so
//  the extension can find it without symbols — a Release build strips them —
//  by walking the main executable's load commands. Plain C with fixed-size
//  fields: the reader parses the layout by offset, and a struct that Swift
//  laid out would not be a layout at all.
//

#ifndef AUTOPSY_CRUMBS_H
#define AUTOPSY_CRUMBS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AUTOPSY_CRUMBS_SEGMENT "__DATA"
#define AUTOPSY_CRUMBS_SECTION "__autopsy"
/// "AUTOPSY!" — the reader trusts nothing that does not start with it.
#define AUTOPSY_CRUMBS_MAGIC 0x2159535054554121ULL
#define AUTOPSY_CRUMBS_VERSION 1
#define AUTOPSY_RUN_ID_LENGTH 40
#define AUTOPSY_SCREEN_LENGTH 128
#define AUTOPSY_LINE_LENGTH 160
#define AUTOPSY_LINE_COUNT 24

typedef struct {
	uint64_t magic;
	uint32_t version;
	uint32_t line_length;
	uint32_t line_count;
	/// Lines written so far; the ring holds the last `line_count` of them.
	uint32_t written;
	char run_id[AUTOPSY_RUN_ID_LENGTH];
	char screen[AUTOPSY_SCREEN_LENGTH];
	char lines[AUTOPSY_LINE_COUNT][AUTOPSY_LINE_LENGTH];
} autopsy_crumbs_t;

/// The block itself, in the executable that links this library, and the
/// address Swift reads it through (a global is not something Swift 6 will
/// let a caller touch directly).
extern autopsy_crumbs_t autopsy_crumbs;
const autopsy_crumbs_t *autopsy_crumbs_pointer(void);

/// Stamp this launch, so a report can be matched to the run it came from.
void autopsy_crumbs_set_run_id(const char *run_id);
/// Where the reader is right now; overwritten, not appended.
void autopsy_crumbs_set_screen(const char *screen);
/// Add a line to the ring. Safe from any thread; two writers racing may
/// interleave, which a crash report can live with.
void autopsy_crumbs_append(const char *line);

#ifdef __cplusplus
}
#endif

#endif
