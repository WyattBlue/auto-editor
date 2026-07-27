/*
 * WebCodecs-backed video and audio decoders for FFmpeg on Emscripten.
 *
 * This file is copied into libavcodec by auto-editor's FFmpeg build. It keeps
 * FFmpeg's ordinary AVPacket/AVFrame API and delegates only codec work to
 * src/webcodecs.js through Emscripten JSPI.
 */

#include <math.h>
#include <stdint.h>
#include <string.h>

#include "libavutil/buffer.h"
#include "libavutil/channel_layout.h"
#include "libavutil/error.h"
#include "libavutil/mem.h"
#include "libavutil/opt.h"

#include "avcodec.h"
#include "codec_internal.h"
#include "decode.h"

enum {
    WC_STATUS,
    WC_FORMAT,
    WC_WIDTH,
    WC_HEIGHT,
    WC_PLANES,
    WC_OFF0,
    WC_STRIDE0,
    WC_OFF1,
    WC_STRIDE1,
    WC_OFF2,
    WC_STRIDE2,
    WC_TS_LO,
    WC_TS_HI,
    WC_DATA_SIZE,
    WC_CHANNELS,
    WC_SAMPLE_RATE,
    WC_CTRL_SIZE,
};

enum {
    WC_KIND_H264 = 1,
    WC_KIND_AUDIO = 2,
    WC_KIND_AV1 = 3,
    WC_KIND_VP9 = 4,
    WC_KIND_HEVC = 5,
    WC_KIND_VP8 = 6,
};

enum {
    WC_CMD_PULL = 1,
    WC_CMD_DRAIN = 2,
    WC_CMD_RESET = 3,
};

typedef struct WebCodecsDecContext {
    int handle;
    int kind;
    int draining;
    int may_have_output;
    int64_t synthetic_ts;
    AVRational packet_time_base;
    int32_t *ctrl;
    AVPacket *packet;
    uint8_t *staging;
    int staging_capacity;
} WebCodecsDecContext;

static int webcodecs_is_video(const WebCodecsDecContext *s)
{
    return s->kind != WC_KIND_AUDIO;
}

extern int ae_wc_init(int kind, int32_t *ctrl,
                      const uint8_t *extradata, int extradata_size,
                      int width, int height, int sample_rate, int channels,
                      int profile, int level, int bit_depth);
extern int ae_wc_decode(int handle, const uint8_t *packet, int packet_size,
                        double timestamp, double duration, int key,
                        uint8_t *output, int output_capacity);
extern int ae_wc_command(int handle, int command,
                         uint8_t *output, int output_capacity);
extern void ae_wc_close(int handle);

static int webcodecs_wait(AVCodecContext *avctx)
{
    WebCodecsDecContext *s = avctx->priv_data;
    int status = __atomic_load_n(&s->ctrl[WC_STATUS], __ATOMIC_ACQUIRE);

    /*
     * JSPI suspends the wasm call stack until the imported async function has
     * completed, so the bridge must have published a terminal status here.
     */
    if (status == 0) {
        av_log(avctx, AV_LOG_ERROR,
               "WebCodecs bridge returned without a result\n");
        return AVERROR_EXTERNAL;
    }
    return status;
}

static int webcodecs_run_command(AVCodecContext *avctx, int command)
{
    WebCodecsDecContext *s = avctx->priv_data;

    if (ae_wc_command(s->handle, command, s->staging,
                      s->staging_capacity) < 0)
        return AVERROR_EXTERNAL;
    return webcodecs_wait(avctx);
}

static int64_t webcodecs_timestamp(const int32_t *ctrl)
{
    uint64_t lo = (uint32_t)ctrl[WC_TS_LO];
    uint64_t hi = (uint32_t)ctrl[WC_TS_HI];
    return (int64_t)((hi << 32) | lo);
}

static int webcodecs_take_staging(WebCodecsDecContext *s, AVFrame *frame)
{
    AVBufferRef *buffer;
    uint8_t *next;
    int size = s->ctrl[WC_DATA_SIZE];

    if (size <= 0 || size > s->staging_capacity)
        return AVERROR_INVALIDDATA;

    next = av_malloc(s->staging_capacity);
    if (!next)
        return AVERROR(ENOMEM);
    buffer = av_buffer_create(s->staging, s->staging_capacity,
                              av_buffer_default_free, NULL, 0);
    if (!buffer) {
        av_free(next);
        return AVERROR(ENOMEM);
    }

    s->staging = next;
    frame->buf[0] = buffer;
    return 0;
}

static int webcodecs_make_video_frame(AVCodecContext *avctx, AVFrame *frame)
{
    WebCodecsDecContext *s = avctx->priv_data;
    const int32_t *c = s->ctrl;
    int width = c[WC_WIDTH];
    int height = c[WC_HEIGHT];
    int format = c[WC_FORMAT];
    int ret;

    if (width <= 0 || height <= 0)
        return AVERROR_INVALIDDATA;

    avctx->width = width;
    avctx->height = height;
    if (format == 0)
        avctx->pix_fmt = AV_PIX_FMT_YUV420P;
    else if (format == 1)
        avctx->pix_fmt = AV_PIX_FMT_NV12;
    else if (format == 2)
        avctx->pix_fmt = AV_PIX_FMT_RGBA;
    else
        return AVERROR_INVALIDDATA;

    frame->format = avctx->pix_fmt;
    frame->width = width;
    frame->height = height;
    ret = webcodecs_take_staging(s, frame);
    if (ret < 0)
        return ret;

    if (format == 0) {
        int chroma_width = (width + 1) / 2;
        int chroma_height = (height + 1) / 2;
        if (c[WC_STRIDE0] < width ||
            c[WC_STRIDE1] < chroma_width ||
            c[WC_STRIDE2] < chroma_width ||
            c[WC_OFF0] + c[WC_STRIDE0] * height > c[WC_DATA_SIZE] ||
            c[WC_OFF1] + c[WC_STRIDE1] * chroma_height > c[WC_DATA_SIZE] ||
            c[WC_OFF2] + c[WC_STRIDE2] * chroma_height > c[WC_DATA_SIZE])
            return AVERROR_INVALIDDATA;
    } else if (format == 1) {
        int chroma_width = 2 * ((width + 1) / 2);
        int chroma_height = (height + 1) / 2;
        if (c[WC_STRIDE0] < width ||
            c[WC_STRIDE1] < chroma_width ||
            c[WC_OFF0] + c[WC_STRIDE0] * height > c[WC_DATA_SIZE] ||
            c[WC_OFF1] + c[WC_STRIDE1] * chroma_height > c[WC_DATA_SIZE])
            return AVERROR_INVALIDDATA;
    } else {
        if (c[WC_STRIDE0] < width * 4 ||
            c[WC_OFF0] + c[WC_STRIDE0] * height > c[WC_DATA_SIZE])
            return AVERROR_INVALIDDATA;
    }

    for (int i = 0; i < c[WC_PLANES]; i++) {
        int offset = c[WC_OFF0 + i * 2];
        frame->data[i] = frame->buf[0]->data + offset;
        frame->linesize[i] = c[WC_STRIDE0 + i * 2];
    }

    frame->pts = av_rescale_q(webcodecs_timestamp(c),
                              (AVRational){ 1, 1000000 },
                              s->packet_time_base);
    return 0;
}

static int webcodecs_make_audio_frame(AVCodecContext *avctx, AVFrame *frame)
{
    WebCodecsDecContext *s = avctx->priv_data;
    const int32_t *c = s->ctrl;
    int channels = c[WC_CHANNELS];
    int sample_rate = c[WC_SAMPLE_RATE];
    int samples = c[WC_WIDTH];
    int plane_size = samples * (int)sizeof(float);
    int ret;

    if (channels <= 0 || channels > AV_NUM_DATA_POINTERS ||
        sample_rate <= 0 || samples <= 0 ||
        (int64_t)plane_size * channels > c[WC_DATA_SIZE])
        return AVERROR_INVALIDDATA;

    avctx->sample_fmt = AV_SAMPLE_FMT_FLTP;
    avctx->sample_rate = sample_rate;
    if (avctx->ch_layout.nb_channels != channels) {
        av_channel_layout_uninit(&avctx->ch_layout);
        av_channel_layout_default(&avctx->ch_layout, channels);
    }

    frame->format = AV_SAMPLE_FMT_FLTP;
    frame->sample_rate = sample_rate;
    frame->nb_samples = samples;
    ret = av_channel_layout_copy(&frame->ch_layout, &avctx->ch_layout);
    if (ret < 0)
        return ret;
    ret = webcodecs_take_staging(s, frame);
    if (ret < 0)
        return ret;

    frame->extended_data = frame->data;
    frame->linesize[0] = plane_size;
    for (int i = 0; i < channels; i++) {
        frame->data[i] = frame->buf[0]->data + i * plane_size;
        frame->extended_data[i] = frame->data[i];
    }

    frame->pts = av_rescale_q(webcodecs_timestamp(c),
                              (AVRational){ 1, 1000000 },
                              s->packet_time_base);
    return 0;
}

static int webcodecs_output_frame(AVCodecContext *avctx, AVFrame *frame)
{
    WebCodecsDecContext *s = avctx->priv_data;
    int status;

    if (s->may_have_output) {
        status = webcodecs_run_command(avctx, WC_CMD_PULL);
        if (status < 0)
            return AVERROR_EXTERNAL;
        if (status == 1)
            return webcodecs_is_video(s)
                ? webcodecs_make_video_frame(avctx, frame)
                : webcodecs_make_audio_frame(avctx, frame);
        s->may_have_output = 0;
    }

    while (!s->draining) {
        int ret = ff_decode_get_packet(avctx, s->packet);
        if (ret == AVERROR_EOF) {
            s->draining = 1;
            status = webcodecs_run_command(avctx, WC_CMD_DRAIN);
            if (status < 0)
                return AVERROR_EXTERNAL;
            if (status == 1) {
                s->may_have_output = 1;
                return webcodecs_is_video(s)
                    ? webcodecs_make_video_frame(avctx, frame)
                    : webcodecs_make_audio_frame(avctx, frame);
            }
            return AVERROR_EOF;
        }
        if (ret < 0)
            return ret;

        AVRational packet_time_base = s->packet->time_base;
        if (packet_time_base.num <= 0 || packet_time_base.den <= 0)
            packet_time_base = avctx->pkt_timebase;
        if (packet_time_base.num <= 0 || packet_time_base.den <= 0)
            packet_time_base = (AVRational){ 1, 1000000 };
        s->packet_time_base = packet_time_base;

        int64_t pts = s->packet->pts;
        if (pts == AV_NOPTS_VALUE)
            pts = s->packet->dts;
        double timestamp;
        if (pts == AV_NOPTS_VALUE) {
            timestamp = s->synthetic_ts++;
        } else {
            timestamp = av_q2d(packet_time_base) * pts * 1000000.0;
        }
        double duration = s->packet->duration > 0
            ? av_q2d(packet_time_base) * s->packet->duration * 1000000.0
            : 0.0;

        ret = ae_wc_decode(s->handle, s->packet->data, s->packet->size,
                           timestamp, duration,
                           !!(s->packet->flags & AV_PKT_FLAG_KEY),
                           s->staging, s->staging_capacity);
        av_packet_unref(s->packet);
        if (ret < 0)
            return AVERROR_EXTERNAL;

        status = webcodecs_wait(avctx);
        if (status < 0)
            return AVERROR_EXTERNAL;
        if (status == 1) {
            s->may_have_output = 1;
            return webcodecs_is_video(s)
                ? webcodecs_make_video_frame(avctx, frame)
                : webcodecs_make_audio_frame(avctx, frame);
        }
    }

    return AVERROR_EOF;
}

static av_cold int webcodecs_init(AVCodecContext *avctx)
{
    WebCodecsDecContext *s = avctx->priv_data;
    int64_t capacity;
    int status;

    if (avctx->codec_id == AV_CODEC_ID_H264)
        s->kind = WC_KIND_H264;
    else if (avctx->codec_id == AV_CODEC_ID_AV1)
        s->kind = WC_KIND_AV1;
    else if (avctx->codec_id == AV_CODEC_ID_VP9)
        s->kind = WC_KIND_VP9;
    else if (avctx->codec_id == AV_CODEC_ID_VP8)
        s->kind = WC_KIND_VP8;
    else if (avctx->codec_id == AV_CODEC_ID_HEVC)
        s->kind = WC_KIND_HEVC;
    else
        s->kind = WC_KIND_AUDIO;
    s->packet_time_base = (AVRational){ 1, 1000000 };
    s->ctrl = av_mallocz(WC_CTRL_SIZE * sizeof(*s->ctrl));
    s->packet = av_packet_alloc();
    if (!s->ctrl || !s->packet)
        return AVERROR(ENOMEM);

    if (webcodecs_is_video(s)) {
        if (avctx->width <= 0 || avctx->height <= 0)
            return AVERROR(EINVAL);
        capacity = (int64_t)avctx->width * avctx->height * 4;
    } else {
        int channels = FFMAX(avctx->ch_layout.nb_channels, 2);
        capacity = (int64_t)channels * 8192 * sizeof(float);
    }
    if (capacity <= 0 || capacity > INT_MAX)
        return AVERROR(EINVAL);

    s->staging_capacity = capacity;
    s->staging = av_malloc(s->staging_capacity);
    if (!s->staging)
        return AVERROR(ENOMEM);

    s->handle = ae_wc_init(s->kind, s->ctrl,
                           avctx->extradata, avctx->extradata_size,
                           avctx->width, avctx->height,
                           avctx->sample_rate,
                           avctx->ch_layout.nb_channels,
                           avctx->profile, avctx->level,
                           avctx->bits_per_raw_sample);
    if (!s->handle)
        return AVERROR(ENOSYS);

    status = webcodecs_wait(avctx);
    if (status != 1) {
        av_log(avctx, AV_LOG_VERBOSE,
               "WebCodecs does not support this codec configuration\n");
        return AVERROR(ENOSYS);
    }
    return 0;
}

static av_cold void webcodecs_flush(AVCodecContext *avctx)
{
    WebCodecsDecContext *s = avctx->priv_data;

    if (s->handle)
        webcodecs_run_command(avctx, WC_CMD_RESET);
    av_packet_unref(s->packet);
    s->draining = 0;
    s->may_have_output = 0;
    s->synthetic_ts = 0;
}

static av_cold int webcodecs_close(AVCodecContext *avctx)
{
    WebCodecsDecContext *s = avctx->priv_data;

    if (s->handle)
        ae_wc_close(s->handle);
    av_packet_free(&s->packet);
    av_freep(&s->staging);
    av_freep(&s->ctrl);
    return 0;
}

#define WEBCODECS_DECODER(short_name, long_name, media_type, codec_id) \
const FFCodec ff_##short_name##_webcodecs_decoder = {                  \
    .p.name         = #short_name "_webcodecs",                        \
    CODEC_LONG_NAME(long_name " WebCodecs decoder"),                   \
    .p.type         = media_type,                                      \
    .p.id           = codec_id,                                        \
    .p.capabilities = AV_CODEC_CAP_DELAY | AV_CODEC_CAP_AVOID_PROBING, \
    .priv_data_size = sizeof(WebCodecsDecContext),                     \
    .init           = webcodecs_init,                                  \
    FF_CODEC_RECEIVE_FRAME_CB(webcodecs_output_frame),                 \
    .flush          = webcodecs_flush,                                 \
    .close          = webcodecs_close,                                 \
    .caps_internal  = FF_CODEC_CAP_INIT_CLEANUP |                      \
                      FF_CODEC_CAP_NOT_INIT_THREADSAFE,                \
    .p.wrapper_name = "webcodecs",                                     \
};

WEBCODECS_DECODER(h264, "H.264", AVMEDIA_TYPE_VIDEO, AV_CODEC_ID_H264)
WEBCODECS_DECODER(aac, "AAC", AVMEDIA_TYPE_AUDIO, AV_CODEC_ID_AAC)
WEBCODECS_DECODER(av1, "AV1", AVMEDIA_TYPE_VIDEO, AV_CODEC_ID_AV1)
WEBCODECS_DECODER(vp8, "VP8", AVMEDIA_TYPE_VIDEO, AV_CODEC_ID_VP8)
WEBCODECS_DECODER(vp9, "VP9", AVMEDIA_TYPE_VIDEO, AV_CODEC_ID_VP9)
WEBCODECS_DECODER(hevc, "HEVC", AVMEDIA_TYPE_VIDEO, AV_CODEC_ID_HEVC)
