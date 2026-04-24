#include "composite_encoder.h"
#include <string.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

// --- Simple RDS encoder (group 0A: PS, group 2A: RT) ---
static void rds_group_0A(uint16_t pi, const char *ps, int ps_scroll, uint16_t *out) {
    char ps_buf[9] = {0};
    int len = strlen(ps);
    int offset = ps_scroll % (len > 8 ? len : 1);
    for (int i = 0; i < 8; ++i) ps_buf[i] = ps[(offset + i) % len];
    out[0] = pi;
    out[1] = 0x0000;
    out[2] = 0x0000;
    out[3] = (ps_buf[0] << 8) | ps_buf[1];
}
static void rds_group_2A(uint16_t pi, const char *rt, int rt_scroll, uint16_t *out) {
    char rt_buf[RT_MAX+1] = {0};
    int len = strlen(rt);
    int offset = rt_scroll % (len > RT_MAX ? len : 1);
    for (int i = 0; i < RT_MAX; ++i) rt_buf[i] = rt[(offset + i) % len];
    out[0] = pi;
    out[1] = (2 << 12);
    out[2] = (rt_buf[0] << 8) | rt_buf[1];
    out[3] = (rt_buf[2] << 8) | rt_buf[3];
}
static float rds_bpsk_bit(int bit, double phase) {
    return (bit ? 1.0f : -1.0f) * sinf(2 * M_PI * 57000.0f * phase / COMPOSITE_RATE);
}

void composite_encoder_init(composite_state_t *s, uint16_t pi, const char *ps, float pilot_amp, float stereo_ratio) {
    memset(s, 0, sizeof(*s));
    s->pi = pi;
    strncpy(s->ps, ps, 8); s->ps[8] = 0;
    s->pilot_amp = pilot_amp;
    s->stereo_ratio = stereo_ratio;
    // Precompute pilot and 38kHz
    long double shifter_19 = (19000.0 / (COMPOSITE_RATE)) * 2 * M_PI;
    long double shifter_38 = shifter_19 * 2;
    for (int i = 0; i < 192; ++i) {
        s->synth_19[i] = sinl(shifter_19 * i);
        s->synth_38[i] = sinl(shifter_38 * i);
    }
}
void composite_encoder_set_rt(composite_state_t *s, const char *rt) {
    strncpy(s->rt, rt, RT_MAX);
    s->rt[RT_MAX] = 0;
}
void composite_encoder_process(composite_state_t *s, const int32_t *pcm_lr, int nframes, int32_t *out) {
    // nframes: number of stereo PCM frames at 48kHz
    // out: 4x as many composite samples at 192kHz
    for (int i = 0; i < nframes; ++i) {
        int32_t l = pcm_lr[2*i];
        int32_t r = pcm_lr[2*i+1];
        float mono = (l + r) * 0.5f;
        float stereo = (l - r) * 0.5f * s->stereo_ratio;
        for (int j = 0; j < 4; ++j) {
            int mpx_idx = (s->mpx_count + j) % 192;
            float w19 = s->synth_19[mpx_idx];
            float w38 = s->synth_38[mpx_idx];
            // RDS: update every 192 samples
            if (mpx_idx == 0) {
                uint16_t group[4];
                if ((i/8) % 2 == 0)
                    rds_group_0A(s->pi, s->ps, s->ps_scroll++, group);
                else
                    rds_group_2A(s->pi, s->rt, s->rt_scroll++, group);
                for (int k = 0; k < 192; ++k) {
                    int bit = (group[(k/48)%4] >> (15 - (k%16))) & 1;
                    s->rds_buf[k] = rds_bpsk_bit(bit, k);
                }
            }
            float rds = s->rds_buf[mpx_idx] * 0.05f * (float)(1<<27);
            float sample = mono + w19 * s->pilot_amp * (float)(1<<27) + w38 * stereo + rds;
            out[(i*4)+j] = (int32_t)sample;
        }
        s->mpx_count = (s->mpx_count + 4) % 192;
    }
}
