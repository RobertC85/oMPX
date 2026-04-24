#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "mpx_stereo_rds.c"

#define SAMPLE_RATE 192000
#define DURATION_SEC 2

int main() {
    size_t n = SAMPLE_RATE * DURATION_SEC;
    float *left = malloc(n * sizeof(float));
    float *right = malloc(n * sizeof(float));
    float *out = malloc(n * sizeof(float));
    if (!left || !right || !out) {
        fprintf(stderr, "Memory allocation failed\n");
        return 1;
    }
    // Generate test tones: left = 1 kHz, right = 2 kHz
    for (size_t i = 0; i < n; ++i) {
        double t = (double)i / SAMPLE_RATE;
        left[i] = 0.7f * sin(2 * M_PI * 1000.0 * t);
        right[i] = 0.7f * sin(2 * M_PI * 2000.0 * t);
    }
    generate_mpx_rds(left, right, out, n, SAMPLE_RATE);
    // Write output as raw 32-bit float PCM
    FILE *f = fopen("mpx_test_output.f32", "wb");
    if (!f) {
        fprintf(stderr, "Failed to open output file\n");
        return 1;
    }
    fwrite(out, sizeof(float), n, f);
    fclose(f);
    free(left); free(right); free(out);
    printf("Wrote %zu samples to mpx_test_output.f32\n", n);
    return 0;
}
