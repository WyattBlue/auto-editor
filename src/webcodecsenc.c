/*
 * WebCodecs-backed video and audio encoders for FFmpeg on Emscripten.
 *
 * The encoders retain FFmpeg's AVFrame/AVPacket API while JSPI suspends the
 * calling pthread until the browser has produced an encoded chunk.
 */

#include <limits.h>
#include <stdint.h>
#include <string.h>

#include "libavutil/buffer.h"
#include "libavutil/error.h"
#include "libavutil/mem.h"

#include "avcodec.h"
#include "codec_internal.h"
#include "encode.h"

enum {
    WE_STATUS,
    WE_PACKET_SIZE,
    WE_FLAGS,
    WE_TS_LO,
    WE_TS_HI,
    WE_DURATION_LO,
    WE_DURATION_HI,
    WE_DESC_OFFSET,
    WE_DESC_SIZE,
    WE_MORE,
    WE_CTRL_SIZE,
};

enum {
    WE_KIND_H264 = 1,
    WE_KIND_AAC = 2,
    WE_KIND_AV1 = 3,
    WE_KIND_VP9 = 4,
    WE_KIND_HEVC = 5,
    WE_KIND_VP8 = 6,
};

enum {
    WE_CMD_PULL = 1,
    WE_CMD_DRAIN = 2,
};

#define WE_STATUS_RESIZE 4
#define WE_MIN_OUTPUT_CAPACITY (64 * 1024)

typedef struct WebEncContext {
    int handle;
    int kind;
    int draining;
    int may_have_output;
    int64_t frame_count;
    int32_t *ctrl;
    AVFrame *frame;
    uint8_t *input;
    int input_capacity;
    uint8_t *output;
    int output_capacity;
} WebEncContext;

extern int ae_we_init(int kind, int32_t *ctrl,
                      int width, int height,
                      int sample_rate, int channels,
                      double frame_rate, double bit_rate,
                      int profile, int level,
                      uint8_t *output, int output_capacity);
extern int ae_we_encode(int handle, const uint8_t *input, int input_size,
                        int width, int height, int samples,
                        double timestamp, double duration, int key,
                        uint8_t *output, int output_capacity);
extern int ae_we_command(int handle, int command,
                         uint8_t *output, int output_capacity);
extern void ae_we_close(int handle);

static int64_t webenc_i64(const int32_t *ctrl, int lo_index)
{
    uint64_t lo = (uint32_t)ctrl[lo_index];
    uint64_t hi = (uint32_t)ctrl[lo_index + 1];
    return (int64_t)((hi << 32) | lo);
}

static int webenc_wait(AVCodecContext *avctx)
{
    WebEncContext *s = avctx->priv_data;
    int status = __atomic_load_n(&s->ctrl[WE_STATUS], __ATOMIC_ACQUIRE);

    if (!status) {
        av_log(avctx, AV_LOG_ERROR,
               "WebCodecs encoder bridge returned without a result\n");
        return AVERROR_EXTERNAL;
    }
    return status;
}

static int webenc_pack_video(AVCodecContext *avctx, const AVFrame *frame)
{
    WebEncContext *s = avctx->priv_data;
    int width = avctx->width;
    int height = avctx->height;
    int chroma_width = (width + 1) / 2;
    int chroma_height = (height + 1) / 2;
    int offsets[3] = {
        0,
        width * height,
        width * height + chroma_width * chroma_height,
    };
    int widths[3] = { width, chroma_width, chroma_width };
    int heights[3] = { height, chroma_height, chroma_height };
    int size = width * height + 2 * chroma_width * chroma_height;

    if (frame->format != AV_PIX_FMT_YUV420P || size > s->input_capacity)
        return AVERROR(EINVAL);

    for (int plane = 0; plane < 3; plane++) {
        if (!frame->data[plane] || frame->linesize[plane] < widths[plane])
            return AVERROR_INVALIDDATA;
        for (int y = 0; y < heights[plane]; y++)
            memcpy(s->input + offsets[plane] + y * widths[plane],
                   frame->data[plane] + y * frame->linesize[plane],
                   widths[plane]);
    }
    return size;
}

static int webenc_pack_audio(AVCodecContext *avctx, const AVFrame *frame)
{
    WebEncContext *s = avctx->priv_data;
    int channels = avctx->ch_layout.nb_channels;
    int plane_size = frame->nb_samples * (int)sizeof(float);
    int size = plane_size * channels;

    if (frame->format != AV_SAMPLE_FMT_FLTP ||
        channels <= 0 || channels > AV_NUM_DATA_POINTERS ||
        frame->nb_samples <= 0 || size > s->input_capacity)
        return AVERROR(EINVAL);

    for (int channel = 0; channel < channels; channel++) {
        if (!frame->extended_data[channel])
            return AVERROR_INVALIDDATA;
        memcpy(s->input + channel * plane_size,
               frame->extended_data[channel], plane_size);
    }
    return size;
}

static int webenc_update_extradata(AVCodecContext *avctx)
{
    WebEncContext *s = avctx->priv_data;
    int offset = s->ctrl[WE_DESC_OFFSET];
    int size = s->ctrl[WE_DESC_SIZE];
    uint8_t *extra;

    if (!size)
        return 0;
    if (size < 0 || offset < 0 ||
        (int64_t)offset + size > s->output_capacity)
        return AVERROR_INVALIDDATA;
    if (avctx->extradata_size == size && avctx->extradata &&
        !memcmp(avctx->extradata, s->output + offset, size))
        return 0;

    extra = av_mallocz(size + AV_INPUT_BUFFER_PADDING_SIZE);
    if (!extra)
        return AVERROR(ENOMEM);
    memcpy(extra, s->output + offset, size);
    av_freep(&avctx->extradata);
    avctx->extradata = extra;
    avctx->extradata_size = size;
    return 0;
}

static int webenc_make_packet(AVCodecContext *avctx, AVPacket *pkt)
{
    WebEncContext *s = avctx->priv_data;
    AVBufferRef *buffer;
    uint8_t *next;
    int size = s->ctrl[WE_PACKET_SIZE];
    int ret;

    if (size <= 0 || size > s->output_capacity)
        return AVERROR_INVALIDDATA;
    ret = webenc_update_extradata(avctx);
    if (ret < 0)
        return ret;

    next = av_malloc(s->output_capacity);
    if (!next)
        return AVERROR(ENOMEM);
    buffer = av_buffer_create(s->output, s->output_capacity,
                              av_buffer_default_free, NULL, 0);
    if (!buffer) {
        av_free(next);
        return AVERROR(ENOMEM);
    }

    s->output = next;
    pkt->buf = buffer;
    pkt->data = buffer->data;
    pkt->size = size;
    pkt->pts = av_rescale_q(webenc_i64(s->ctrl, WE_TS_LO),
                            (AVRational){ 1, 1000000 }, avctx->time_base);
    pkt->dts = pkt->pts;
    pkt->duration = av_rescale_q(webenc_i64(s->ctrl, WE_DURATION_LO),
                                 (AVRational){ 1, 1000000 },
                                 avctx->time_base);
    if (s->ctrl[WE_FLAGS] & 1)
        pkt->flags |= AV_PKT_FLAG_KEY;
    s->may_have_output = s->ctrl[WE_MORE];
    return 0;
}

static int webenc_grow_output(AVCodecContext *avctx)
{
    WebEncContext *s = avctx->priv_data;
    int packet_size = s->ctrl[WE_PACKET_SIZE];
    int extra_size = s->ctrl[WE_DESC_SIZE];
    int64_t required = (int64_t)packet_size + extra_size;
    int64_t capacity = s->output_capacity;
    uint8_t *output;

    if (packet_size < 0 || extra_size < 0 ||
        required <= s->output_capacity || required > INT_MAX)
        return AVERROR_INVALIDDATA;
    while (capacity < required && capacity <= INT_MAX / 2)
        capacity *= 2;
    if (capacity < required)
        capacity = required;

    output = av_realloc(s->output, capacity);
    if (!output)
        return AVERROR(ENOMEM);
    s->output = output;
    s->output_capacity = capacity;
    return 0;
}

static int webenc_command(AVCodecContext *avctx, AVPacket *pkt, int command)
{
    WebEncContext *s = avctx->priv_data;
    int status;
    int ret;

    for (;;) {
        if (ae_we_command(s->handle, command, s->output,
                          s->output_capacity) < 0)
            return AVERROR_EXTERNAL;
        status = webenc_wait(avctx);
        if (status != WE_STATUS_RESIZE)
            break;
        ret = webenc_grow_output(avctx);
        if (ret < 0)
            return ret;
        command = WE_CMD_PULL;
    }
    if (status < 0)
        return AVERROR_EXTERNAL;
    if (status == 1)
        return webenc_make_packet(avctx, pkt);
    return status == 3 ? AVERROR_EOF : AVERROR(EAGAIN);
}

static int webenc_receive_packet(AVCodecContext *avctx, AVPacket *pkt)
{
    WebEncContext *s = avctx->priv_data;
    AVFrame *frame = s->frame;
    int input_size;
    int status;
    int ret;

    if (s->may_have_output) {
        ret = webenc_command(avctx, pkt, WE_CMD_PULL);
        if (ret != AVERROR(EAGAIN))
            return ret;
        s->may_have_output = 0;
    }
    if (s->draining)
        return AVERROR_EOF;

    ret = ff_encode_get_frame(avctx, frame);
    if (ret == AVERROR_EOF) {
        s->draining = 1;
        return webenc_command(avctx, pkt, WE_CMD_DRAIN);
    }
    if (ret < 0)
        return ret;

    input_size = s->kind != WE_KIND_AAC
        ? webenc_pack_video(avctx, frame)
        : webenc_pack_audio(avctx, frame);
    if (input_size < 0) {
        av_frame_unref(frame);
        return input_size;
    }

    int64_t pts = frame->pts;
    if (pts == AV_NOPTS_VALUE)
        pts = s->frame_count;
    int64_t duration = frame->duration > 0 ? frame->duration :
        (s->kind != WE_KIND_AAC ? 1 : frame->nb_samples);
    double timestamp_us = av_q2d(avctx->time_base) * pts * 1000000.0;
    double duration_us = av_q2d(avctx->time_base) * duration * 1000000.0;
    int key = s->kind != WE_KIND_AAC &&
        (s->frame_count == 0 ||
         (avctx->gop_size > 0 && s->frame_count % avctx->gop_size == 0));

    ret = ae_we_encode(s->handle, s->input, input_size,
                       avctx->width, avctx->height, frame->nb_samples,
                       timestamp_us, duration_us, key,
                       s->output, s->output_capacity);
    av_frame_unref(frame);
    s->frame_count++;
    if (ret < 0)
        return AVERROR_EXTERNAL;

    status = webenc_wait(avctx);
    if (status < 0)
        return AVERROR_EXTERNAL;
    if (status == WE_STATUS_RESIZE) {
        ret = webenc_grow_output(avctx);
        if (ret < 0)
            return ret;
        return webenc_command(avctx, pkt, WE_CMD_PULL);
    }
    if (status == 1)
        return webenc_make_packet(avctx, pkt);
    return AVERROR(EAGAIN);
}

static av_cold int webenc_init(AVCodecContext *avctx)
{
    WebEncContext *s = avctx->priv_data;
    int64_t raw_capacity;
    double frame_rate = avctx->framerate.num && avctx->framerate.den
        ? av_q2d(avctx->framerate) : 30.0;
    int status;

    if (avctx->codec_id == AV_CODEC_ID_H264)
        s->kind = WE_KIND_H264;
    else if (avctx->codec_id == AV_CODEC_ID_AV1)
        s->kind = WE_KIND_AV1;
    else if (avctx->codec_id == AV_CODEC_ID_VP9)
        s->kind = WE_KIND_VP9;
    else if (avctx->codec_id == AV_CODEC_ID_HEVC)
        s->kind = WE_KIND_HEVC;
    else if (avctx->codec_id == AV_CODEC_ID_VP8)
        s->kind = WE_KIND_VP8;
    else
        s->kind = WE_KIND_AAC;
    s->ctrl = av_mallocz(WE_CTRL_SIZE * sizeof(*s->ctrl));
    s->frame = av_frame_alloc();
    if (!s->ctrl || !s->frame)
        return AVERROR(ENOMEM);

    if (s->kind != WE_KIND_AAC) {
        if (avctx->width <= 0 || avctx->height <= 0)
            return AVERROR(EINVAL);
        raw_capacity = (int64_t)avctx->width * avctx->height * 4;
        avctx->pix_fmt = AV_PIX_FMT_YUV420P;
        avctx->max_b_frames = 0;
    } else {
        int channels = avctx->ch_layout.nb_channels;
        if (avctx->sample_rate <= 0 || channels <= 0)
            return AVERROR(EINVAL);
        raw_capacity = (int64_t)channels * 8192 * sizeof(float);
        avctx->sample_fmt = AV_SAMPLE_FMT_FLTP;
        avctx->frame_size = 1024;
    }
    if (raw_capacity <= 0 || raw_capacity > INT_MAX)
        return AVERROR(EINVAL);

    s->input_capacity = raw_capacity;
    s->output_capacity = FFMAX(raw_capacity, WE_MIN_OUTPUT_CAPACITY);
    s->input = av_malloc(s->input_capacity);
    s->output = av_malloc(s->output_capacity);
    if (!s->input || !s->output)
        return AVERROR(ENOMEM);

    s->handle = ae_we_init(s->kind, s->ctrl,
                           avctx->width, avctx->height,
                           avctx->sample_rate,
                           avctx->ch_layout.nb_channels,
                           frame_rate, avctx->bit_rate,
                           avctx->profile, avctx->level,
                           s->output, s->output_capacity);
    if (!s->handle)
        return AVERROR(ENOSYS);
    status = webenc_wait(avctx);
    if (status != 1)
        return AVERROR(ENOSYS);
    status = webenc_update_extradata(avctx);
    if (status < 0)
        return status;
    return 0;
}

static av_cold int webenc_close(AVCodecContext *avctx)
{
    WebEncContext *s = avctx->priv_data;

    if (s->handle)
        ae_we_close(s->handle);
    av_frame_free(&s->frame);
    av_freep(&s->input);
    av_freep(&s->output);
    av_freep(&s->ctrl);
    return 0;
}

const FFCodec ff_h264_web_encoder = {
    .p.name         = "h264_web",
    CODEC_LONG_NAME("H.264 WebCodecs encoder"),
    .p.type         = AVMEDIA_TYPE_VIDEO,
    .p.id           = AV_CODEC_ID_H264,
    .priv_data_size = sizeof(WebEncContext),
    .init           = webenc_init,
    FF_CODEC_RECEIVE_PACKET_CB(webenc_receive_packet),
    .close          = webenc_close,
    .p.capabilities = AV_CODEC_CAP_DELAY,
    .caps_internal  = FF_CODEC_CAP_INIT_CLEANUP |
                      FF_CODEC_CAP_NOT_INIT_THREADSAFE,
    CODEC_PIXFMTS(AV_PIX_FMT_YUV420P),
    .p.wrapper_name = "webcodecs",
};

const FFCodec ff_aac_web_encoder = {
    .p.name         = "aac_web",
    CODEC_LONG_NAME("AAC WebCodecs encoder"),
    .p.type         = AVMEDIA_TYPE_AUDIO,
    .p.id           = AV_CODEC_ID_AAC,
    .priv_data_size = sizeof(WebEncContext),
    .init           = webenc_init,
    FF_CODEC_RECEIVE_PACKET_CB(webenc_receive_packet),
    .close          = webenc_close,
    .p.capabilities = AV_CODEC_CAP_DELAY,
    .caps_internal  = FF_CODEC_CAP_INIT_CLEANUP |
                      FF_CODEC_CAP_NOT_INIT_THREADSAFE,
    CODEC_SAMPLEFMTS(AV_SAMPLE_FMT_FLTP),
    CODEC_SAMPLERATES(8000, 11025, 12000, 16000, 22050, 24000,
                      32000, 44100, 48000),
    .p.wrapper_name = "webcodecs",
};

#define WEB_VIDEO_ENCODER(short_name, long_name, codec_id)        \
const FFCodec ff_##short_name##_web_encoder = {                   \
    .p.name         = #short_name "_web",                         \
    CODEC_LONG_NAME(long_name " WebCodecs encoder"),              \
    .p.type         = AVMEDIA_TYPE_VIDEO,                          \
    .p.id           = codec_id,                                   \
    .priv_data_size = sizeof(WebEncContext),                      \
    .init           = webenc_init,                                \
    FF_CODEC_RECEIVE_PACKET_CB(webenc_receive_packet),            \
    .close          = webenc_close,                               \
    .p.capabilities = AV_CODEC_CAP_DELAY,                         \
    .caps_internal  = FF_CODEC_CAP_INIT_CLEANUP |                 \
                      FF_CODEC_CAP_NOT_INIT_THREADSAFE,           \
    CODEC_PIXFMTS(AV_PIX_FMT_YUV420P),                            \
    .p.wrapper_name = "webcodecs",                                \
};

WEB_VIDEO_ENCODER(av1, "AV1", AV_CODEC_ID_AV1)
WEB_VIDEO_ENCODER(vp8, "VP8", AV_CODEC_ID_VP8)
WEB_VIDEO_ENCODER(vp9, "VP9", AV_CODEC_ID_VP9)
WEB_VIDEO_ENCODER(hevc, "HEVC", AV_CODEC_ID_HEVC)
