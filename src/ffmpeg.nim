{.passC: "-I./build/include".}
when defined(macosx):
  {.passL: "-framework VideoToolbox -framework AudioToolbox -framework CoreFoundation -framework CoreMedia -framework CoreVideo".}
when defined(linux):
  {.passL: "-L./build/lib/x86_64-linux-gnu -L./build/lib64"}
{.passL: "-L./build/lib -lavfilter -lavformat -lavcodec -lswresample -lswscale -lavutil".}
{.passL: "-lmp3lame -lopus -lvpx -lx264 -lx265 -ldav1d -lSvtAv1Enc -lm".}

when defined(macosx): # For x265
  {.passL: "-lc++"}
else:
  {.passL: "-lstdc++"}


import std/posix

type AVRational* {.importc, header: "<libavutil/rational.h>", bycopy.} = object
  num*: cint
  den*: cint

proc av_mul_q(b: AVRational, c: AVRational): AVRational {.importc,
    header: "<libavutil/rational.h>".}
proc av_div_q(b: AVRational, c: AVRational): AVRational {.importc,
    header: "<libavutil/rational.h>".}
proc av_add_q(b: AVRational, c: AVRational): AVRational {.importc,
    header: "<libavutil/rational.h>".}
proc av_sub_q(b: AVRational, c: AVRational): AVRational {.importc,
    header: "<libavutil/rational.h>".}
proc av_q2d*(a: AVRational): cdouble {.importc, header: "<libavutil/rational.h>".}
proc av_inv_q*(a: AVRational): AVRational {.importc, header: "<libavutil/rational.h>".}
proc av_parse_ratio(q: ptr AVRational, str: cstring, max: cint, log_offset: cint,
    log_ctx: pointer): cint {.importc, header: "<libavutil/parseutils.h>".}
proc av_cmp_q*(a, b: AVRational): cint {.importc, header: "<libavutil/rational.h>".}

proc `+`*(a, b: AVRational): AVRational =
  av_add_q(a, b)

proc `-`*(a, b: AVRational): AVRational =
  av_sub_q(a, b)

proc `*`*(a, b: AVRational): AVRational =
  av_mul_q(a, b)

proc `/`*(a, b: AVRational): AVRational =
  av_div_q(a, b)

proc `/`*(a: int64, b: AVRational): AVRational =
  AVRational(num: a.cint, den: 1) / b

proc `*`*(a: int64, b: AVRational): AVRational =
  AVRational(num: a.cint, den: 1) * b

func `$`*(a: AVRational): string =
  if a.den == 1:
    return $a.num
  else:
    return $a.num & "/" & $a.den

converter toDouble*(r: AVRational): cdouble =
  av_q2d(r)

converter toInt64*(r: AVRational): int64 =
  (r.num div r.den).int64

converter toAVRational*(num: int): AVRational =
  AVRational(num: num.cint, den: 1)

converter toAVRational*(s: string): AVRational =
  if s.len == 0:
    raise newException(ValueError, "Empty string cannot be converted to AVRational")

  var rational: AVRational
  let ret = av_parse_ratio(addr rational, cstring(s), cint(high(cint)), 0, nil)

  if ret < 0:
    raise newException(ValueError, "Failed to rational: " & s)

  return rational

proc av_parse_color*(rgba_color: ptr uint8, color_string: cstring, slen: cint,
    log_ctx: pointer): cint {.importc, header: "<libavutil/parseutils.h>".}

type
  AVMediaType* = cint
  AVCodecID* = cint
  AVColorRange* = cint
  AVColorPrimaries* = cint
  AVColorTransferCharacteristic* = cint
  AVColorSpace* = cint
  AVPixelFormat* = distinct cint

proc `==`*(x, y: AVPixelFormat): bool {.borrow.}
proc `$`*(a: AVPixelFormat): string {.borrow.}

const AV_PIX_FMT_NONE* = AVPixelFormat(-1)
const AV_PIX_FMT_YUV420P* = AVPixelFormat(0)
const AV_PIX_FMT_YUYV422* = AVPixelFormat(1)
const AV_PIX_FMT_RGB24* = AVPixelFormat(2)
const AV_PIX_FMT_RGB8* = AVPixelFormat(20)
const AV_PIX_FMT_YUV422P10LE* = AVPixelFormat(64)

type
  AVDictionary* {.importc, header: "<libavutil/dict.h>".} = object
  AVDictionaryEntry* {.importc, header: "<libavutil/dict.h>".} = object
    key*: cstring
    value*: cstring

  AVChannelLayout* {.importc, header: "<libavutil/channel_layout.h>",
      bycopy.} = object
    order*: cint
    nb_channels*: cint
    u*: AVChannelLayoutMask
    opaque*: pointer

  AVChannelLayoutMask* {.union.} = object
    mask*: uint64
    map*: array[64, uint8]

  AVOutputFormat* {.importc, header: "<libavformat/avformat.h>".} = object
    name*: cstring
    long_name*: cstring
    mime_type*: cstring
    extensions*: cstring
    audio_codec*: AVCodecID
    video_codec*: AVCodecID
    subtitle_codec*: AVCodecID
    flags*: cint

  AVFormatContext* {.importc, header: "<libavformat/avformat.h>".} = object
    av_class*: pointer
    iformat*: pointer
    oformat*: ptr AVOutputFormat
    priv_data*: pointer
    pb*: pointer
    ctx_flags*: cint
    nb_streams*: cuint
    streams*: ptr UncheckedArray[ptr AVStream]
    filename*: array[1024, char]
    url*: cstring
    start_time*: int64
    duration*: int64
    bit_rate*: int64
    packet_size*: cuint
    max_delay*: cint
    flags*: cint
    probesize*: int64
    max_analyze_duration*: int64
    metadata*: ptr AVDictionary

    # ... other fields omitted for brevity

  AVStream* {.importc, header: "<libavformat/avformat.h>".} = object
    index*: cint
    id*: cint
    codecpar*: ptr AVCodecParameters
    time_base*: AVRational
    start_time*: int64
    duration*: int64
    nb_frames*: int64
    disposition*: cint
    sample_aspect_ratio*: AVRational
    metadata*: ptr AVDictionary
    avg_frame_rate*: AVRational

  AVCodec* {.importc, header: "<libavcodec/codec.h>", bycopy.} = object
    name*: cstring
    `type`*: AVMediaType
    id*: AVCodecID
    capabilities*: cint
    max_lowres*: uint8
    supported_framerates*: ptr AVRational
    pix_fmts*: ptr UncheckedArray[AVPixelFormat]
    supported_samplerates*: ptr cint
    sample_fmts*: ptr UncheckedArray[AVSampleFormat]

  AVCodecParameters* {.importc, header: "<libavcodec/avcodec.h>".} = object
    codec_type*: AVMediaType
    codec_id*: AVCodecID
    codec_tag*: cuint
    extradata*: ptr uint8
    extradata_size*: cint
    format*: cint
    bit_rate*: int64
    bits_per_coded_sample*: cint
    bits_per_raw_sample*: cint
    profile*: cint
    level*: cint
    width*: cint
    height*: cint
    sample_aspect_ratio*: AVRational
    field_order*: cint
    color_range*: AVColorRange
    color_primaries*: AVColorPrimaries
    color_trc*: AVColorTransferCharacteristic
    color_space*: AVColorSpace
    chroma_location*: cint
    video_delay*: cint
    ch_layout*: AVChannelLayout
    sample_rate*: cint
    block_align*: cint
    frame_size*: cint
    initial_padding*: cint
    trailing_padding*: cint
    seek_preroll*: cint

  AVSampleFormat* {.importc: "enum AVSampleFormat",
      header: "<libavutil/samplefmt.h>".} = enum
    AV_SAMPLE_FMT_NONE = -1,
    AV_SAMPLE_FMT_U8,
    AV_SAMPLE_FMT_S16,
    AV_SAMPLE_FMT_S32,
    AV_SAMPLE_FMT_FLT,
    AV_SAMPLE_FMT_DBL,
    AV_SAMPLE_FMT_U8P,
    AV_SAMPLE_FMT_S16P,
    AV_SAMPLE_FMT_S32P,
    AV_SAMPLE_FMT_FLTP,
    AV_SAMPLE_FMT_DBLP

  AVCodecContext* {.importc, header: "<libavcodec/avcodec.h>".} = object
    av_class*: pointer
    log_level_offset*: cint
    codec_type*: AVMediaType
    codec*: ptr AVCodec
    codec_id*: AVCodecID
    codec_tag*: cuint
    priv_data*: pointer
    internal*: pointer
    opaque*: pointer
    bit_rate*: int64
    bit_rate_tolerance*: cint
    global_quality*: cint
    compression_level*: cint
    flags*: cint
    flags2*: cint
    extradata*: ptr uint8
    extradata_size*: cint
    time_base*: AVRational
    delay*: cint
    width*, height*: cint
    coded_width*, coded_height*: cint
    ch_layout*: AVChannelLayout
    gop_size*: cint
    frame_size*: cint
    framerate*: AVRational
    pix_fmt*: AVPixelFormat
    sample_rate*: cint
    sample_fmt*: AVSampleFormat
    sample_aspect_ratio*: AVRational
    thread_type*: cint
    thread_count*: cint
    color_range*: AVColorRange
    color_primaries*: AVColorPrimaries
    color_trc*: AVColorTransferCharacteristic
    colorspace*: AVColorSpace
    chroma_sample_location*: cint
    max_b_frames*: cint
    profile*: cint
    # ... other fields omitted for brevity

const
  AVMEDIA_TYPE_UNKNOWN* = AVMediaType(-1)
  AVMEDIA_TYPE_VIDEO* = AVMediaType(0)
  AVMEDIA_TYPE_AUDIO* = AVMediaType(1)
  AVMEDIA_TYPE_DATA* = AVMediaType(2)
  AVMEDIA_TYPE_SUBTITLE* = AVMediaType(3)
  AVMEDIA_TYPE_ATTACHMENT* = AVMediaType(4)
  AVFMT_GLOBALHEADER* = 0x0040
  AV_CODEC_FLAG_GLOBAL_HEADER* = 4194304 # 1 << 22
  AV_TIME_BASE* = 1000000
  AV_NOPTS_VALUE* = -9223372036854775807'i64 - 1
  FF_THREAD_FRAME* = 1
  FF_THREAD_SLICE* = 2
  AV_CODEC_FLAG2_FAST* = 1

const
  AV_LOG_QUIET* = -8   # Print no output
  AV_LOG_PANIC* = 0    # Something went really wrong
  AV_LOG_FATAL* = 8    # Something went wrong and recovery is not possible
  AV_LOG_ERROR* = 16   # Something went wrong and cannot losslessly be recovered
  AV_LOG_WARNING* = 24 # Something somehow does not look correct
  AV_LOG_INFO* = 32    # Standard information
  AV_LOG_VERBOSE* = 40 # Detailed information
  AV_LOG_DEBUG* = 48   # Stuff which is only useful for libav* developers
  AV_LOG_TRACE* = 56   # Extremely verbose debugging

proc av_log_set_level*(level: cint) {.importc, header: "<libavutil/log.h>".}

proc av_samples_set_silence*(audio_data: ptr ptr uint8, offset: cint, nb_samples: cint,
                            nb_channels: cint,
                                sample_fmt: AVSampleFormat): cint {.importc,
    header: "<libavutil/samplefmt.h>".}
# Procedure declarations remain the same
proc avformat_open_input*(ps: ptr ptr AVFormatContext, filename: cstring,
    fmt: pointer, options: pointer): cint {.importc,
    header: "<libavformat/avformat.h>".}
proc avformat_find_stream_info*(ic: ptr AVFormatContext,
    options: pointer): cint {.importc, header: "<libavformat/avformat.h>".}
proc avformat_close_input*(s: ptr ptr AVFormatContext) {.importc,
    header: "<libavformat/avformat.h>".}
proc avcodec_parameters_to_context*(codec_ctx: ptr AVCodecContext,
    par: ptr AVCodecParameters): cint {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_alloc_context3*(codec: pointer): ptr AVCodecContext {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_free_context*(avctx: ptr ptr AVCodecContext) {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_get_name*(id: AVCodecID): cstring {.importc,
    header: "<libavcodec/avcodec.h>".}
proc av_get_channel_layout_string*(buf: cstring, buf_size: cint,
    nb_channels: cint, channel_layout: uint64): cstring {.importc,
    header: "<libavutil/channel_layout.h>".}
proc av_get_pix_fmt_name*(pix_fmt: AVPixelFormat): cstring {.importc, cdecl.}
proc avformat_query_codec*(ofmt: ptr AVOutputFormat, codec_id: AVCodecID,
  std_compliance: cint): cint {.importc, header: "<libavformat/avformat.h>".}

proc av_codec_iterate*(opaque: ptr pointer): ptr AVCodec {.importc, header: "<libavcodec/avcodec.h>".}


const FF_COMPLIANCE_STRICT*: cint = 1
const FF_COMPLIANCE_NORMAL*: cint = 0
const FF_COMPLIANCE_INOFFICIAL*: cint = -1
const FF_COMPLIANCE_EXPERIMENTAL*: cint = -2

# https://www.ffmpeg.org/doxygen/7.0/group__lavu__dict.html#gae67f143237b2cb2936c9b147aa6dfde3
proc av_dict_get*(m: ptr AVDictionary, key: cstring,
    prev: ptr AVDictionaryEntry, flags: cint): ptr AVDictionaryEntry {.importc,
    header: "<libavutil/dict.h>".}

proc av_dict_set*(pm: ptr ptr AVDictionary, key: cstring, value: cstring,
                  flags: cint): cint {.importc, header: "<libavutil/dict.h>".}
proc av_dict_free*(m: ptr ptr AVDictionary) {.importc,
    header: "<libavutil/dict.h>".}

proc av_channel_layout_describe*(ch_layout: ptr AVChannelLayout, buf: cstring,
    buf_size: csize_t): cint {.importc, header: "<libavutil/channel_layout.h>".}

proc av_channel_layout_default*(ch_layout: ptr AVChannelLayout,
    nb_channels: cint) {.importc, header: "<libavutil/channel_layout.h>".}
proc av_channel_layout_from_string*(channel_layout: ptr AVChannelLayout,
    char: cstring): cint {.importc, header: "<libavutil/channel_layout.h>".}

type
  AVPacket* {.importc, header: "<libavcodec/packet.h>", bycopy.} = object
    buf*: pointer          # reference counted buffer holding the data
    pts*: int64            # presentation timestamp in time_base units
    dts*: int64            # decompression timestamp in time_base units
    data*: ptr uint8       # data pointer
    size*: cint            # size of data in bytes
    stream_index*: cint    # stream index this packet belongs to
    flags*: cint
    side_data*: pointer    # pointer to array of side data
    side_data_elems*: cint # number of side data elements
    duration*: int64       # duration of this packet in time_base units, 0 if unknown
    pos*: int64            # byte position in stream, -1 if unknown
    opaque*: pointer       # time when packet is created
    opaque_ref*: pointer   # reference to opaque
    time_base*: AVRational # time base of the packet

  # https://ffmpeg.org/doxygen/7.0/structAVFrame.html
  AVFrame* {.importc: "AVFrame", header: "<libavutil/frame.h>",
      bycopy.} = object
    data*: array[8, ptr uint8]
    linesize*: array[8, cint]
    extended_data*: ptr ptr uint8
    width*, height*: cint
    nb_samples*: cint
    format*: cint
    pict_type*: AVPictureType
    sample_aspect_ratio*: AVRational
    pts*: int64
    pkt_dts*: int64
    time_base*: AVRational
    quality*: cint
    opaque*: pointer
    repeat_pict*: cint
    sample_rate*: cint
    # buf*: array[8, ptr AVBufferRef]
    # extended_buf*: ptr ptr AVBufferRef
    nb_extended_buf*: cint
    # side_data*: ptr ptr AVFrameSideData
    # nb_side_data*: cint
    flags*: cint
    color_range*: AVColorRange
    color_primaries*: AVColorPrimaries
    color_trc*: AVColorTransferCharacteristic
    colorspace*: AVColorSpace
    best_effort_timestamp*: int64
    metadata*: ptr AVDictionary
    decode_error_flags*: cint
    crop_top*: csize_t
    crop_bottom*: csize_t
    crop_left*: csize_t
    crop_right*: csize_t
    ch_layout*: AVChannelLayout

  AVPictureType* {.importc: "enum AVPictureType",
      header: "<libavutil/avutil.h>".} = enum
    AV_PICTURE_TYPE_NONE = 0,
    AV_PICTURE_TYPE_I,
    AV_PICTURE_TYPE_P,
    AV_PICTURE_TYPE_B,
    AV_PICTURE_TYPE_S,
    AV_PICTURE_TYPE_SI,
    AV_PICTURE_TYPE_SP,
    AV_PICTURE_TYPE_BI

  # AVBufferRef* {.importc: "AVBufferRef", header: "<libavutil/buffer.h>", bycopy.} = object
  #   buffer*: ptr AVBuffer
  #   data*: ptr uint8
  #   size*: cint

  AVFrameSideData* {.importc: "AVFrameSideData", header: "<libavutil/frame.h>",
      bycopy.} = object
    `type`*: AVFrameSideDataType
    data*: ptr uint8
    size*: cint
    metadata*: ptr AVDictionary

  AVFrameSideDataType* {.importc: "enum AVFrameSideDataType",
      header: "<libavutil/frame.h>".} = enum
    AV_FRAME_DATA_PANSCAN,
    AV_FRAME_DATA_A53_CC,
    AV_FRAME_DATA_STEREO3D,
    AV_FRAME_DATA_MATRIXENCODING,
    AV_FRAME_DATA_DOWNMIX_INFO,
    AV_FRAME_DATA_REPLAYGAIN,
    AV_FRAME_DATA_DISPLAYMATRIX,
    AV_FRAME_DATA_AFD,
    AV_FRAME_DATA_MOTION_VECTORS,
    AV_FRAME_DATA_SKIP_SAMPLES,
    AV_FRAME_DATA_AUDIO_SERVICE_TYPE,
    AV_FRAME_DATA_MASTERING_DISPLAY_METADATA,
    AV_FRAME_DATA_GOP_TIMECODE,
    AV_FRAME_DATA_SPHERICAL,
    AV_FRAME_DATA_CONTENT_LIGHT_LEVEL,
    AV_FRAME_DATA_ICC_PROFILE,
    AV_FRAME_DATA_QP_TABLE_PROPERTIES,
    AV_FRAME_DATA_QP_TABLE_DATA,
    AV_FRAME_DATA_S12M_TIMECODE,
    AV_FRAME_DATA_DYNAMIC_HDR_PLUS,
    AV_FRAME_DATA_REGIONS_OF_INTEREST,
    AV_FRAME_DATA_VIDEO_ENC_PARAMS,
    AV_FRAME_DATA_SEI_UNREGISTERED,
    AV_FRAME_DATA_FILM_GRAIN_PARAMS,
    AV_FRAME_DATA_DETECTION_BBOXES,
    AV_FRAME_DATA_DOVI_RPU_BUFFER,
    AV_FRAME_DATA_DOVI_METADATA,
    AV_FRAME_DATA_DYNAMIC_HDR_VIVID

# Packets
proc av_packet_alloc*(): ptr AVPacket {.importc,
    header: "<libavcodec/packet.h>".}
proc av_packet_free*(pkt: ptr ptr AVPacket) {.importc,
    header: "<libavcodec/packet.h>".}
proc av_init_packet*(pkt: ptr AVPacket) {.importc,
    header: "<libavcodec/packet.h>".}
proc av_packet_unref*(pkt: ptr AVPacket) {.importc, cdecl.}
proc av_packet_ref*(dst: ptr AVPacket, src: ptr AVPacket): cint {.importc,
    header: "<libavcodec/packet.h>".}

# Frames
proc avcodec_send_packet*(avctx: ptr AVCodecContext,
    avpkt: ptr AVPacket): cint {.importc, header: "<libavcodec/avcodec.h>".}
proc avcodec_receive_frame*(avctx: ptr AVCodecContext,
    frame: ptr AVFrame): cint {.importc, header: "<libavcodec/avcodec.h>".}
proc av_read_frame*(s: ptr AVFormatContext, pkt: ptr AVPacket): cint {.importc, cdecl.}
proc av_frame_alloc*(): ptr AVFrame {.importc, header: "<libavutil/frame.h>".}
proc av_frame_free*(frame: ptr ptr AVFrame) {.importc,
    header: "<libavutil/frame.h>".}
proc av_frame_ref*(dst: ptr AVFrame, src: ptr AVFrame): cint {.importc,
    header: "<libavutil/frame.h>".}
proc av_frame_unref*(frame: ptr AVFrame) {.importc,
    header: "<libavutil/frame.h>".}
proc av_frame_get_buffer*(frame: ptr AVFrame, align: cint): cint {.importc,
    header: "<libavutil/frame.h>".}
proc av_frame_is_writable*(frame: ptr AVFrame): cint {.importc,
    header: "<libavutil/frame.h>".}
proc av_frame_make_writable*(frame: ptr AVFrame): cint {.importc,
    header: "<libavutil/frame.h>".}
proc av_frame_clone*(src: ptr AVFrame): ptr AVFrame {.importc,
    header: "<libavutil/frame.h>".}

# Codec
proc avcodec_find_decoder*(codec_id: AVCodecID): ptr AVCodec {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_open2*(avctx: ptr AVCodecContext, codec: ptr AVCodec,
    options: ptr ptr AVDictionary): cint {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_close*(avctx: ptr AVCodecContext): cint {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_flush_buffers*(avctx: ptr AVCodecContext) {.importc,
    header: "<libavcodec/avcodec.h>".}

# Error
func MKTAG*(a, b, c, d: char): cint {.inline.} =
  cast[cint]((a.uint32) or (b.uint32 shl 8) or (c.uint32 shl 16) or (d.uint32 shl 24))

func AVERROR*(e: cint): cint {.inline.} = (-e)
const AVERROR_EOF* = AVERROR(MKTAG('E','O','F',' '))
let AVERROR_EAGAIN* = AVERROR(EAGAIN)

const AV_ERROR_MAX_STRING_SIZE* = 64

proc av_make_error_string*(errbuf: cstring, errbuf_size: csize_t,
    errnum: cint): cstring {.importc, header: "<libavutil/error.h>".}

proc av_err2str*(errnum: cint): string =
  var errbuf = newString(AV_ERROR_MAX_STRING_SIZE)
  discard av_make_error_string(errbuf.cstring, AV_ERROR_MAX_STRING_SIZE.csize_t, errnum)
  return errbuf

# Audio FIFO function declarations
type AVAudioFifo* {.importc, header: "<libavutil/audio_fifo.h>".} = object

proc av_audio_fifo_alloc*(sample_fmt: AVSampleFormat, channels: cint,
    nb_samples: cint): ptr AVAudioFifo {.importc, cdecl,
    header: "<libavutil/audio_fifo.h>".}
proc av_audio_fifo_free*(af: ptr AVAudioFifo) {.importc, cdecl.}
proc av_audio_fifo_write*(af: ptr AVAudioFifo, data: pointer,
    nb_samples: cint): cint {.importc, cdecl, header: "<libavutil/audio_fifo.h>".}
proc av_audio_fifo_read*(af: ptr AVAudioFifo, data: pointer,
    nb_samples: cint): cint {.importc, cdecl,
    header: "<libavutil/audio_fifo.h>".}
proc av_audio_fifo_size*(af: ptr AVAudioFifo): cint {.importc, cdecl.}
proc av_audio_fifo_drain*(af: ptr AVAudioFifo, nb_samples: cint): cint {.importc, cdecl.}
proc av_audio_fifo_reset*(af: ptr AVAudioFifo) {.importc, cdecl.}

proc av_get_bytes_per_sample*(sample_fmt: AVSampleFormat): cint {.importc, cdecl.}
proc av_samples_get_buffer_size*(linesize: ptr cint, nb_channels: cint,
    nb_samples: cint, sample_fmt: AVSampleFormat, align: cint): cint {.importc,
    header: "<libavutil/samplefmt.h>".}

# Audio sample allocation and conversion utilities
proc av_samples_alloc*(audio_data: ptr ptr uint8, linesize: ptr cint,
    nb_channels: cint, nb_samples: cint, sample_fmt: AVSampleFormat,
    align: cint): cint {.importc, header: "<libavutil/samplefmt.h>".}

proc av_freep*(`ptr`: pointer) {.importc, header: "<libavutil/mem.h>".}

type SwrContext* {.importc, header: "<libswresample/swresample.h>".} = object

proc swr_alloc*(): ptr SwrContext {.importc, header: "<libswresample/swresample.h>".}
proc swr_init*(s: ptr SwrContext): cint {.importc,
    header: "<libswresample/swresample.h>".}
proc swr_free*(s: ptr ptr SwrContext) {.importc,
    header: "<libswresample/swresample.h>".}
proc swr_convert*(s: ptr SwrContext, output: ptr ptr uint8, out_count: cint,
    input: ptr ptr uint8, in_count: cint): cint {.importc,
    header: "<libswresample/swresample.h>".}
proc swr_get_delay*(s: ptr SwrContext, base: int64): int64 {.importc,
    header: "<libswresample/swresample.h>".}

# SwrContext option setting
proc av_opt_set_int*(obj: pointer, name: cstring, val: int64,
    search_flags: cint): cint {.importc, header: "<libavutil/opt.h>".}
proc av_opt_set_sample_fmt*(obj: pointer, name: cstring, fmt: AVSampleFormat,
    search_flags: cint): cint {.importc, header: "<libavutil/opt.h>".}
proc av_opt_set_chlayout*(obj: pointer, name: cstring, layout: ptr AVChannelLayout,
    search_flags: cint): cint {.importc, header: "<libavutil/opt.h>".}
proc av_opt_set*(obj: pointer, name: cstring, val: cstring,
    search_flags: cint): cint {.importc, header: "<libavutil/opt.h>".}

# Subtitles
type
  AVSubtitleType* {.importc: "enum AVSubtitleType",
      header: "<libavcodec/avcodec.h>".} = enum
    SUBTITLE_NONE,
    SUBTITLE_BITMAP,
    SUBTITLE_TEXT,
    SUBTITLE_ASS

  AVSubtitleRect* {.importc, header: "<libavcodec/avcodec.h>".} = object
    x*: cint
    y*: cint
    w*: cint
    h*: cint
    nb_colors*: cint
    text*: cstring
    ass*: cstring
    flags*: cint
    `type`*: AVSubtitleType

  AVSubtitle* {.importc, header: "<libavcodec/avcodec.h>".} = object
    format*: uint16
    start_display_time*: uint32 # relative to packet pts, in ms
    end_display_time*: uint32   # relative to packet pts, in ms
    num_rects*: cuint
    rects*: ptr UncheckedArray[ptr AVSubtitleRect]
    pts*: int64

proc avcodec_decode_subtitle2*(avctx: ptr AVCodecContext, sub: ptr AVSubtitle,
    got_sub_ptr: ptr cint, avpkt: ptr AVPacket): cint {.importc,
    header: "<libavcodec/avcodec.h>".}

proc avsubtitle_free*(sub: ptr AVSubtitle) {.importc, header: "<libavcodec/avcodec.h>".}
proc av_get_sample_fmt_name*(sample_fmt: cint): cstring {.importc,
    header: "<libavutil/samplefmt.h>".}

const
  AV_CODEC_ID_NONE* = AVCodecID(0)
  AV_CODEC_ID_AV1* = AVCodecID(225)
  AV_CODEC_ID_PCM_S16LE* = AVCodecID(65536)
  AVFMT_NOFILE* = 0x0001
  AVIO_FLAG_WRITE* = 2

type AVProfile* {.importc, header: "<libavcodec/avcodec.h>".} = object
  profile*: cint
  name*: cstring

type AVCodecDescriptor* {.importc, header: "<libavcodec/avcodec.h>".} = object
  id*: AVCodecID
  `type`*: AVMediaType
  profiles*: ptr AVProfile

proc avformat_alloc_output_context2*(ctx: ptr ptr AVFormatContext,
    oformat: pointer, format_name: cstring, filename: cstring): cint {.importc,
    header: "<libavformat/avformat.h>".}
proc avformat_new_stream*(s: ptr AVFormatContext,
    c: ptr AVCodec): ptr AVStream {.importc, header: "<libavformat/avformat.h>".}
proc avcodec_find_encoder*(id: AVCodecID): ptr AVCodec {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_find_encoder_by_name*(name: cstring): ptr AVCodec {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_descriptor_get_by_name*(name: cstring): ptr AVCodecDescriptor {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_descriptor_get*(id: AVCodecID): ptr AVCodecDescriptor {.importc,
    header: "<libavcodec/avcodec.h>".}
proc avcodec_parameters_from_context*(par: ptr AVCodecParameters,
    codec: ptr AVCodecContext): cint {.importc,
        header: "<libavcodec/avcodec.h>".}
proc avio_open*(s: ptr pointer, filename: cstring, flags: cint): cint {.importc,
    header: "<libavformat/avio.h>".}
proc avio_closep*(s: ptr pointer): cint {.importc,
    header: "<libavformat/avio.h>".}
proc avformat_write_header*(s: ptr AVFormatContext,
    options: pointer): cint {.importc, header: "<libavformat/avformat.h>".}
proc av_write_trailer*(s: ptr AVFormatContext): cint {.importc,
    header: "<libavformat/avformat.h>".}
proc av_guess_format*(short_name: cstring, filename: cstring, mime_type: cstring): ptr AVOutputFormat {.importc,
    header: "<libavformat/avformat.h>".}
proc avformat_free_context*(s: ptr AVFormatContext) {.importc,
    header: "<libavformat/avformat.h>".}
proc avcodec_send_frame*(avctx: ptr AVCodecContext,
    frame: ptr AVFrame): cint {.importc, header: "<libavcodec/avcodec.h>".}
proc avcodec_receive_packet*(avctx: ptr AVCodecContext,
    avpkt: ptr AVPacket): cint {.importc, header: "<libavcodec/avcodec.h>".}
proc av_interleaved_write_frame*(s: ptr AVFormatContext,
    pkt: ptr AVPacket): cint {.importc, header: "<libavformat/avformat.h>".}
proc av_packet_rescale_ts*(pkt: ptr AVPacket, tb_src: AVRational,
    tb_dst: AVRational) {.importc, header: "<libavcodec/packet.h>".}

# Filters
type
  AVFilterGraph* {.importc, header: "<libavfilter/avfilter.h>".} = object
    filters*: ptr UncheckedArray[ptr AVFilterContext]
    nb_filters*: cuint
    scale_sws_opts*: cstring
    thread_type*: cint
    nb_threads*: cint

  AVFilterContext* {.importc, header: "<libavfilter/avfilter.h>".} = object
    av_class*: pointer
    filter*: ptr AVFilter
    name*: cstring
    input_pads*: pointer
    inputs*: ptr UncheckedArray[ptr AVFilterLink]
    nb_inputs*: cuint
    output_pads*: pointer
    outputs*: ptr UncheckedArray[ptr AVFilterLink]
    nb_outputs*: cuint
    priv*: pointer
    graph*: ptr AVFilterGraph

  AVFilter* {.importc, header: "<libavfilter/avfilter.h>".} = object
    name*: cstring
    description*: cstring
    inputs*: pointer
    outputs*: pointer
    priv_class*: pointer
    flags*: cint

  AVFilterLink* {.importc, header: "<libavfilter/avfilter.h>".} = object
    src*: ptr AVFilterContext
    srcpad*: pointer
    dst*: ptr AVFilterContext
    dstpad*: pointer
    `type`*: AVMediaType
    w*: cint
    h*: cint
    sample_aspect_ratio*: AVRational
    channel_layout*: uint64
    sample_rate*: cint
    format*: cint
    time_base*: AVRational
    ch_layout*: AVChannelLayout

  AVFilterInOut* {.importc, header: "<libavfilter/avfilter.h>".} = object
    name*: cstring
    filter_ctx*: ptr AVFilterContext
    pad_idx*: cint
    next*: ptr AVFilterInOut

# Constants
const
  AV_BUFFERSRC_FLAG_NO_CHECK_FORMAT* = 1
  AV_BUFFERSRC_FLAG_PUSH* = 4

# Filter graph management
proc avfilter_graph_alloc*(): ptr AVFilterGraph {.importc,
    header: "<libavfilter/avfilter.h>".}
proc avfilter_graph_free*(graph: ptr ptr AVFilterGraph) {.importc,
    header: "<libavfilter/avfilter.h>".}
proc avfilter_graph_create_filter*(filt_ctx: ptr ptr AVFilterContext,
    filt: ptr AVFilter, name: cstring, args: cstring, opaque: pointer,
    graph_ctx: ptr AVFilterGraph): cint {.importc,
    header: "<libavfilter/avfilter.h>".}
proc avfilter_graph_parse_ptr*(graph: ptr AVFilterGraph, filters: cstring,
    inputs: ptr ptr AVFilterInOut, outputs: ptr ptr AVFilterInOut,
    log_ctx: pointer): cint {.importc, header: "<libavfilter/avfilter.h>".}
proc avfilter_graph_parse2*(graph: ptr AVFilterGraph, filters: cstring,
    inputs: ptr ptr AVFilterInOut, outputs: ptr ptr AVFilterInOut): cint {.importc,
    header: "<libavfilter/avfilter.h>".}
proc avfilter_graph_config*(graphctx: ptr AVFilterGraph,
    log_ctx: pointer): cint {.importc, header: "<libavfilter/avfilter.h>".}
proc avfilter_link*(src: ptr AVFilterContext, srcpad: cuint,
    dst: ptr AVFilterContext, dstpad: cuint): cint {.importc,
    header: "<libavfilter/avfilter.h>".}

# Filter lookup
proc avfilter_get_by_name*(name: cstring): ptr AVFilter {.importc,
    header: "<libavfilter/avfilter.h>".}

# Filter input/output management
proc avfilter_inout_alloc*(): ptr AVFilterInOut {.importc,
    header: "<libavfilter/avfilter.h>".}
proc avfilter_inout_free*(inout: ptr ptr AVFilterInOut) {.importc,
    header: "<libavfilter/avfilter.h>".}

# Buffer source/sink operations
proc av_buffersrc_write_frame*(ctx: ptr AVFilterContext,
    frame: ptr AVFrame): cint {.importc, header: "<libavfilter/buffersrc.h>".}
proc av_buffersrc_add_frame*(ctx: ptr AVFilterContext,
    frame: ptr AVFrame): cint {.importc, header: "<libavfilter/buffersrc.h>".}
proc av_buffersink_get_frame*(ctx: ptr AVFilterContext,
    frame: ptr AVFrame): cint {.importc, header: "<libavfilter/buffersink.h>".}
proc av_buffersink_get_frame_flags*(ctx: ptr AVFilterContext,
    frame: ptr AVFrame, flags: cint): cint {.importc,
    header: "<libavfilter/buffersink.h>".}


# String utilities for filters
proc av_strdup*(s: cstring): cstring {.importc, header: "<libavutil/mem.h>".}

# Seeking
const
  AVSEEK_FLAG_BACKWARD* = 1
  AVSEEK_FLAG_BYTE* = 2
  AVSEEK_FLAG_ANY* = 4
  AVSEEK_FLAG_FRAME* = 8

proc av_seek_frame*(s: ptr AVFormatContext, stream_index: cint, timestamp: int64,
    flags: cint): cint {.importc, header: "<libavformat/avformat.h>".}
proc avformat_seek_file*(s: ptr AVFormatContext, stream_index: cint, min_ts: int64,
    ts: int64, max_ts: int64, flags: cint): cint {.importc,
    header: "<libavformat/avformat.h>".}

# SwScale context and functions
type SwsContext* {.importc: "struct SwsContext", header: "<libswscale/swscale.h>".} = object

proc sws_getCachedContext*(context: ptr SwsContext, srcW: cint, srcH: cint,
    srcFormat: AVPixelFormat, dstW: cint, dstH: cint, dstFormat: AVPixelFormat,
    flags: cint, srcFilter: pointer, dstFilter: pointer,
    param: pointer): ptr SwsContext {.importc, header: "<libswscale/swscale.h>".}

proc sws_scale*(c: ptr SwsContext, srcSlice: ptr ptr uint8, srcStride: ptr cint,
    srcSliceY: cint, srcSliceH: cint, dst: ptr ptr uint8,
    dstStride: ptr cint): cint {.importc, header: "<libswscale/swscale.h>".}

proc sws_freeContext*(swsContext: ptr SwsContext) {.importc,
    header: "<libswscale/swscale.h>".}

# SwScale constants
const
  SWS_BILINEAR* = 2
  SWS_BICUBIC* = 4
  SWS_LANCZOS* = 512
