#ifndef UF_PRESETS_H
#define UF_PRESETS_H
#include <stddef.h>
typedef struct { const char *name; float bass, mid, treble, trim; const char *note; } UFPreset;
/* Moderate subjective starting points. No model-specific measured correction. */
static const UFPreset UF_PRESETS[] = {
    {"Neutral", 0, 0, 0, 0, "Flat tone and zero trim; processing can still be on"},
    {"Everyday", -1, 0.5f, -0.5f, 0, "Gentle balance for mixed listening"},
    {"Podcast / Speech", -2.5f, 1.5f, 0.5f, 0, "Less low-end weight, a little more voice presence"},
    {"Gaming", -1, 1, 1, -1, "Modest detail and presence; no positional enhancement"},
    {"Music", 1, -0.5f, 0.5f, -1, "A mild warmth and detail curve"},
    {"Clearer voices", -3, 1, 1, 0, "Less bass weight with a gentle presence lift"},
    {"Less boom", -4, 0, 1, 0, "Reduce bass weight without a large high-frequency boost"},
    {"Softer treble", 0, -1, -3, 0, "Reduce brightness and edge"}
};
#define UF_PRESET_COUNT (sizeof(UF_PRESETS) / sizeof(UF_PRESETS[0]))
#endif
