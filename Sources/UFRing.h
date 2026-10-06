#ifndef UF_RING_H
#define UF_RING_H

#include <stddef.h>
#include <stdint.h>

/* Stereo single producer / single consumer buffer. The producer is the tap
   callback; the consumer is the output Audio Unit callback. No allocation or
   locking takes place in write/read/reset. Both endpoints must have the same
   nominal sample rate. Interpolation corrects only small clock drift. */
typedef struct UFRing UFRing;

UFRing *ufring_create(size_t capacity_frames, size_t target_backlog_frames);
void ufring_destroy(UFRing *ring);

size_t ufring_write_stereo(UFRing *ring,
    const float *left, size_t left_stride,
    const float *right, size_t right_stride, size_t frames);

/* Always fills both output channels. Returns the frames supplied from the
   buffer, with any remaining frames filled with silence. */
size_t ufring_read_stereo(UFRing *ring,
    float *left, size_t left_stride,
    float *right, size_t right_stride, size_t frames);

/* Only the consumer callback may reset. Capture may continue concurrently. */
void ufring_reset_consumer(UFRing *ring);
size_t ufring_available(const UFRing *ring);
uint64_t ufring_underruns(const UFRing *ring); /* events after initial priming */
uint64_t ufring_overruns(const UFRing *ring);  /* dropped input frames */

#endif
