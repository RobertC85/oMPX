#include <math.h>
#include <stdint.h>
#include <stdlib.h>

#define M_PI 3.14159265358979323846

// Generate a single sample of a sine wave at a given frequency and sample rate
static inline float sine_wave(double freq, double t) {
    return (float)sin(2.0 * M_PI * freq * t);
}

// Generate FM stereo MPX signal (L+R, 19kHz pilot, (L-R)@38kHz)
// left, right: input audio samples (normalized -1.0 to 1.0)
// t: time in seconds
// Returns: MPX sample
float mpx_stereo_sample(float left, float right, double t) {
    float lpr = left + right;   // L+R (mono)
    float lmr = left - right;   // L-R (stereo diff)
    float pilot = 0.1f * sine_wave(19000.0, t); // 19 kHz pilot, scaled
    float stereo = 0.45f * lmr * sine_wave(38000.0, t); // DSB-SC at 38 kHz
    return 0.55f * lpr + pilot + stereo;
}

// Generate 57 kHz RDS subcarrier (for demonstration, no BPSK data)
float rds_carrier_sample(double t) {
    return 0.05f * sine_wave(57000.0, t);
}

// Example: generate a buffer of MPX+RDS samples
void generate_mpx_rds(float* left, float* right, float* out, size_t n, double sample_rate) {
    for (size_t i = 0; i < n; ++i) {
        double t = (double)i / sample_rate;
        float mpx = mpx_stereo_sample(left[i], right[i], t);
        float rds = rds_carrier_sample(t); // Replace with real RDS modulation
        out[i] = mpx + rds;
    }
}

// Usage: fill left[] and right[] with audio, call generate_mpx_rds()
// For real RDS, modulate data using BPSK at 1187.5 baud on 57 kHz
