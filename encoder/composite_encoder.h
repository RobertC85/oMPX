#ifndef COMPOSITE_ENCODER_H
#define COMPOSITE_ENCODER_H
#include <stdint.h>

#define COMPOSITE_RATE 192000
#define PCM_RATE 48000
#define RT_MAX 64

// State for composite encoder
typedef struct {
    // Stereo
    float pilot_amp;
    float stereo_ratio;
    // RDS
    uint16_t pi;
    char ps[9];
    char rt[RT_MAX+1];
    int ps_scroll;
    int rt_scroll;
    // Internal
    int mpx_count;
    float synth_19[192];
    float synth_38[192];
    float rds_buf[192];
} composite_state_t;

void composite_encoder_init(composite_state_t *s, uint16_t pi, const char *ps, float pilot_amp, float stereo_ratio);
void composite_encoder_set_rt(composite_state_t *s, const char *rt);
void composite_encoder_process(composite_state_t *s, const int32_t *pcm_lr, int nframes, int32_t *out);

#endif // COMPOSITE_ENCODER_H
