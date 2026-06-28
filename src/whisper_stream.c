#include <whisper.h>
#include <ggml.h>
#include <ggml-backend.h>
#include <stdlib.h>
#include <stdbool.h>

static void quiet_log(enum ggml_log_level level, const char *text, void *user) {
    (void) level; (void) text; (void) user;
}

void *ae_whisper_init(const char *model_path, int use_gpu, int verbose) {
    // whisper.cpp/ggml log straight to stderr; mute unless debugging.
    if (!verbose) {
        whisper_log_set(quiet_log, NULL);
        ggml_log_set(quiet_log, NULL);
    }

    static int loaded = 0;
    if (!loaded) { ggml_backend_load_all(); loaded = 1; }

    struct whisper_context_params cp = whisper_context_default_params();
    cp.use_gpu = use_gpu != 0;
    cp.flash_attn = true;
    return whisper_init_from_file_with_params(model_path, cp);
}

typedef void (*ae_seg_cb)(void *user, const char *text, int64_t t0_ms, int64_t t1_ms);

// Transcribe one segment of mono f32 16kHz samples. on_segment is called once per
// resulting text segment, synchronously, on the caller's thread. t0/t1 are in ms,
// relative to the start of `samples`. Returns 0 on success.
int ae_whisper_run(void *ctx, const float *samples, int n_samples,
                   const char *language, int translate, int n_threads,
                   const char *initial_prompt, int max_len,
                   ae_seg_cb on_segment, void *user) {
    struct whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.print_special = false;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_timestamps = false;
    p.translate = translate != 0;
    p.language = language;          // "auto" or an ISO code
    p.n_threads = n_threads;
    // Carry the previous segment(s) as context. whisper keeps prior tokens in the
    // context's prompt_past (capped to ~recent), so reusing the same ctx across
    // calls conditions each utterance on the last — better continuity/spelling.
    p.no_context = false;
    p.initial_prompt = (initial_prompt && initial_prompt[0]) ? initial_prompt : NULL;
    if (max_len > 0) {
        p.max_len = max_len;
        p.token_timestamps = true;
        p.split_on_word = true;
    }

    if (whisper_full((struct whisper_context *) ctx, p, samples, n_samples) != 0)
        return -1;

    int n = whisper_full_n_segments((struct whisper_context *) ctx);
    for (int i = 0; i < n; i++) {
        const char *text = whisper_full_get_segment_text((struct whisper_context *) ctx, i);
        int64_t t0 = whisper_full_get_segment_t0((struct whisper_context *) ctx, i) * 10;
        int64_t t1 = whisper_full_get_segment_t1((struct whisper_context *) ctx, i) * 10;
        on_segment(user, text, t0, t1);
    }
    return 0;
}

void ae_whisper_free(void *ctx) {
    if (ctx) whisper_free((struct whisper_context *) ctx);
}
