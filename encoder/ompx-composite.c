#include "composite_encoder.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#define BLOCK 1024

// Read RT from file (first 64 bytes)
void read_rt_file(const char *fname, char *rt_out) {
    FILE *f = fopen(fname, "rb");
    if (!f) { rt_out[0] = 0; return; }
    size_t n = fread(rt_out, 1, RT_MAX, f);
    rt_out[n] = 0;
    fclose(f);
}

int main(int argc, char **argv) {
    uint16_t pi = 0x5717; // Default PI code
    char ps[9] = "oMPX";
    float pilot_amp = 0.15f;
    float stereo_ratio = 0.3f;
    const char *rtfile = "songtitle.txt";
    if (argc > 1) pi = (uint16_t)strtol(argv[1], NULL, 0);
    if (argc > 2) strncpy(ps, argv[2], 8);
    if (argc > 3) rtfile = argv[3];

    composite_state_t state;
    composite_encoder_init(&state, pi, ps, pilot_amp, stereo_ratio);

    int32_t pcm_lr[BLOCK*2];
    int32_t out[BLOCK*2*4];
    char last_rt[RT_MAX+1] = "";
    while (1) {
        size_t n = fread(pcm_lr, sizeof(int32_t), BLOCK*2, stdin);
        if (n == 0) break;
        // Update RT if changed
        char rt[RT_MAX+1];
        read_rt_file(rtfile, rt);
        if (strcmp(rt, last_rt) != 0) {
            composite_encoder_set_rt(&state, rt);
            strncpy(last_rt, rt, RT_MAX);
        }
        composite_encoder_process(&state, pcm_lr, n/2, out);
        fwrite(out, sizeof(int32_t), (n/2)*4, stdout);
    }
    return 0;
}
