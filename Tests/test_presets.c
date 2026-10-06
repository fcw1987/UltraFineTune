#include "UFPresets.h"
#include "UFEQ.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    float in[256] = {0}, out[256];
    for (size_t i = 0; i < UF_PRESET_COUNT; i++) {
        const UFPreset *p = &UF_PRESETS[i];
        assert(p->name && p->note && strlen(p->note));
        assert(isfinite(p->bass) && fabsf(p->bass) <= 6);
        assert(isfinite(p->mid) && fabsf(p->mid) <= 6);
        assert(isfinite(p->treble) && fabsf(p->treble) <= 6);
        assert(isfinite(p->trim) && p->trim >= -12 && p->trim <= 0);
        for (size_t j = 0; j < i; j++) assert(strcmp(p->name, UF_PRESETS[j].name));
        UFEQ *eq = ufeq_create(48000); assert(eq);
        ufeq_set_controls(eq, p->bass, p->mid, p->treble, p->trim, false);
        for (int n = 0; n < 200; n++) ufeq_process_stereo(eq, in, 2, in + 1, 2, out, 2, out + 1, 2, 128);
        UFEQMeters normal; ufeq_get_meters(eq, &normal);
        assert(isfinite(normal.headroom_db) && normal.headroom_db >= 0 && normal.headroom_db <= 20);
        if (p->bass || p->mid || p->treble) assert(normal.headroom_db >= 0.99f);
        else assert(normal.headroom_db == 0);
        ufeq_set_controls(eq, p->bass, p->mid, p->treble, p->trim, true);
        for (int n = 0; n < 200; n++) ufeq_process_stereo(eq, in, 2, in + 1, 2, out, 2, out + 1, 2, 128);
        UFEQMeters bypass; ufeq_get_meters(eq, &bypass);
        assert(fabsf(normal.headroom_db - bypass.headroom_db) < 0.01f);
        ufeq_destroy(eq);
    }
    printf("PASS: %zu presets; finite bounds, unique names, flat/boost headroom and comparison retention\n", UF_PRESET_COUNT);
}
