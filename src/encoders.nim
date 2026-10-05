## What a library user can offer for an export, asked of the linked ffmpeg
## rather than kept in tables: the encoders a container accepts, and each
## encoder's presets and profiles with their defaults. The desktop app
## hard-codes these because it can only reach ffmpeg through a CLI process.

import std/[algorithm, sequtils, strutils]
import ./ffmpeg
import ./util/rules

{.emit: """/*INCLUDESECTION*/
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <x264.h>
#include <x265.h>
""".}

{.emit: """
static const AVOption *ae_opt(const AVCodec *c, const char *name) {
  if (!c || !c->priv_class) return NULL;
  const AVClass *cls = c->priv_class;
  /* A fake object: a pointer to the class, as av_opt_find wants. */
  return av_opt_find2(&cls, name, NULL, 0, AV_OPT_SEARCH_FAKE_OBJ, NULL);
}

/* 0 none, 1 string, 2 int-like with named constants, 3 plain int range */
static int ae_opt_kind(const AVCodec *c, const char *name) {
  const AVOption *o = ae_opt(c, name);
  if (!o) return 0;
  if (o->type == AV_OPT_TYPE_STRING) return 1;
  if (o->type == AV_OPT_TYPE_INT || o->type == AV_OPT_TYPE_INT64) return o->unit ? 2 : 3;
  return 0;
}

static const char *ae_opt_default_str(const AVCodec *c, const char *name) {
  const AVOption *o = ae_opt(c, name);
  return o && o->type == AV_OPT_TYPE_STRING ? o->default_val.str : NULL;
}

static long long ae_opt_default_int(const AVCodec *c, const char *name) {
  const AVOption *o = ae_opt(c, name);
  return o ? o->default_val.i64 : 0;
}

static double ae_opt_min(const AVCodec *c, const char *name) {
  const AVOption *o = ae_opt(c, name);
  return o ? o->min : 0;
}

static double ae_opt_max(const AVCodec *c, const char *name) {
  const AVOption *o = ae_opt(c, name);
  return o ? o->max : 0;
}

/* The k-th named constant in `name`'s unit, or NULL past the end. */
static const char *ae_opt_const(const AVCodec *c, const char *name, int k,
    long long *value) {
  const AVOption *o = ae_opt(c, name);
  if (!o || !o->unit) return NULL;
  const AVClass *cls = c->priv_class;
  const AVOption *it = NULL;
  int n = 0;
  while ((it = av_opt_next(&cls, it))) {
    if (it->type == AV_OPT_TYPE_CONST && it->unit && !strcmp(it->unit, o->unit)) {
      if (n++ == k) { *value = it->default_val.i64; return it->name; }
    }
  }
  return NULL;
}

static int ae_codec_caps(const AVCodec *c) { return c->capabilities; }
/* The codec's profiles as its descriptor names them: what render's
   setProfileOrErr matches against. */
static const char *ae_codec_profile(const AVCodec *c, int k) {
  const AVCodecDescriptor *d = avcodec_descriptor_get(c->id);
  if (!d || !d->profiles) return NULL;
  for (int i = 0; d->profiles[i].profile != AV_PROFILE_UNKNOWN; i++)
    if (i == k) return d->profiles[i].name;
  return NULL;
}
static const char *ae_x264_preset(int k) { return x264_preset_names[k]; }
static const char *ae_x264_profile(int k) { return x264_profile_names[k]; }
static const char *ae_x265_preset(int k) { return x265_preset_names[k]; }
static const char *ae_x265_profile(int k) { return x265_profile_names[k]; }
""".}

proc ae_opt_kind(c: ptr AVCodec, name: cstring): cint {.importc, nodecl.}
proc ae_opt_default_str(c: ptr AVCodec, name: cstring): cstring {.importc, nodecl.}
proc ae_opt_default_int(c: ptr AVCodec, name: cstring): clonglong {.importc, nodecl.}
proc ae_opt_min(c: ptr AVCodec, name: cstring): cdouble {.importc, nodecl.}
proc ae_opt_max(c: ptr AVCodec, name: cstring): cdouble {.importc, nodecl.}
proc ae_opt_const(c: ptr AVCodec, name: cstring, k: cint,
  value: ptr clonglong): cstring {.importc, nodecl.}
proc ae_codec_caps(c: ptr AVCodec): cint {.importc, nodecl.}
proc ae_codec_profile(c: ptr AVCodec, k: cint): cstring {.importc, nodecl.}
proc ae_x264_preset(k: cint): cstring {.importc, nodecl.}
proc ae_x264_profile(k: cint): cstring {.importc, nodecl.}
proc ae_x265_preset(k: cint): cstring {.importc, nodecl.}
proc ae_x265_profile(k: cint): cstring {.importc, nodecl.}

const
  capExperimental = 1'i32 shl 9 # AV_CODEC_CAP_EXPERIMENTAL
  capHardware = 1'i32 shl 18    # AV_CODEC_CAP_HARDWARE

type
  EncoderChoice* = object
    encoder*: string ## what render takes, e.g. "libx264"
    label*: string ## e.g. "h264 (libx264)", "hevc (VideoToolbox)"
    hardware*: bool

  EncoderSetting* = object
    values*: seq[string] ## empty when the encoder has none to choose
    default*: string ## the value used when none is set; "" if automatic

  EncoderInfo* = object
    presets*, profiles*: EncoderSetting

proc hardwareLabel(encoder: string): string =
  for (suffix, name) in [("_videotoolbox", "VideoToolbox"), ("_nvenc", "NVENC"),
      ("_qsv", "Quick Sync"), ("_amf", "AMF"), ("_vaapi", "VA-API"),
      ("_mf", "Media Foundation"), ("_vulkan", "Vulkan")]:
    if encoder.endsWith(suffix): return name

proc isHardware(c: ptr AVCodec): bool =
  (ae_codec_caps(c) and capHardware) != 0 or hardwareLabel($c.name).len > 0

proc formatEncoders*(ext: string): tuple[video, audio: seq[EncoderChoice]] =
  ## The encoders this build has for codecs the `ext` container can hold, as
  ## auto-editor's render rules judge them. The container's default codec
  ## comes first, then well-known codecs, software before hardware.
  let name = "x." & ext.strip(chars = {'.'})
  let ofmt = av_guess_format(nil, name.cstring, nil)
  if ofmt == nil: return
  let rules = initRules(name)
  let video = holdsVideo(name)
  const known = ["h264", "hevc", "av1", "vp9", "vp8", "prores", "dnxhd",
    "mpeg4", "aac", "opus", "flac", "mp3", "alac", "ac3", "vorbis"]
  var found: seq[(int, bool, string, EncoderChoice, bool)]
  var opaque: pointer = nil
  while true:
    let c = av_codec_iterate(addr opaque)
    if c == nil: break
    if av_codec_is_encoder(c) == 0 or (ae_codec_caps(c) and capExperimental) != 0:
      continue
    let isVideo = c.`type` == AVMEDIA_TYPE_VIDEO
    if not isVideo and c.`type` != AVMEDIA_TYPE_AUDIO: continue
    if isVideo and not video: continue
    # Render's tag-table check, or the muxer's own say for muxers without a
    # tag table (webm, mp3, gif), which render accepts an explicit codec for.
    if not rules.allowsCodec(c.id) and
        avformat_query_codec(ofmt, c.id, FF_COMPLIANCE_NORMAL) != 1:
      continue
    let enc = $c.name
    # Not useful choices: an internal passthrough, an RGB-only H.264 twin,
    # and still-image codecs outside an image format.
    if enc in ["wrapped_avframe", "libx264rgb"]: continue
    if enc in ["png", "gif"] and ext.strip(chars = {'.'}) != "gif": continue
    let codec = $avcodec_get_name(c.id)
    let hw = c.isHardware
    let impl = if hw: hardwareLabel(enc)
               elif enc.endsWith("_at"): "AudioToolbox" # macOS's own, not a GPU
               else: enc
    let label = if impl.len == 0 or impl == codec: codec else: codec & " (" & impl & ")"
    let isDefault = c.id == (if isVideo: rules.defaultVid else: rules.defaultAud)
    let rank = if isDefault: -1
               elif codec in known: known.find(codec)
               else: known.len
    found.add (rank, hw, label,
      EncoderChoice(encoder: enc, label: label, hardware: hw), isVideo)
  found.sort(proc (a, b: (int, bool, string, EncoderChoice, bool)): int =
    result = cmp(a[0], b[0])
    if result == 0: result = cmp(a[1], b[1])
    if result == 0: result = cmp(a[2], b[2]))
  for f in found:
    if f[4]: result.video.add f[3] else: result.audio.add f[3]

proc names(get: proc (k: cint): cstring): seq[string] =
  var k = 0'i32
  while true:
    let n = get(k)
    if n == nil: break
    result.add $n
    inc k

proc setting(c: ptr AVCodec, opt: string): EncoderSetting =
  ## A preset/profile-style option: its named constants, or an int range.
  case ae_opt_kind(c, opt.cstring)
  of 2:
    let def = ae_opt_default_int(c, opt.cstring)
    var k = 0'i32
    while true:
      var v: clonglong
      let n = ae_opt_const(c, opt.cstring, k, addr v)
      if n == nil: break
      result.values.add $n
      if v == def: result.default = $n
      inc k
  of 3:
    let lo = max(ae_opt_min(c, opt.cstring), 0).int
    let hi = ae_opt_max(c, opt.cstring).int
    if hi - lo in 1 .. 64:
      for v in lo .. hi: result.values.add $v
      let def = ae_opt_default_int(c, opt.cstring)
      if def >= lo: result.default = $def
  of 1:
    let d = ae_opt_default_str(c, opt.cstring)
    if d != nil: result.default = $d
  else: discard

proc squash(s: string): string =
  for ch in s.toLowerAscii:
    if ch notin {' ', '_', '-'}:
      result.add ch

proc suits8bit420(profile: string, id: AVCodecID): bool =
  ## Render keeps an 8-bit source 8-bit 4:2:0, so a profile that needs more
  ## (10/12-bit, 4:2:2, 4:4:4) makes the encoder refuse to open: VideoToolbox
  ## rejects "main 10" outright. ProRes is always 10-bit and render converts
  ## for it, so its profiles are spared by the caller.
  let p = squash(profile)
  for needs in ["10", "12", "422", "444", "rext"]:
    if needs in p: return false
  let codec = $avcodec_get_name(id)
  if codec == "av1": return p == "main" # high is 4:4:4, professional 4:2:2/12-bit
  if codec == "vp9": return p == "profile0" # 1-3 are 4:4:4 or high depth
  true

proc encoderInfo*(encoder: string): EncoderInfo =
  ## The presets and profiles `encoder` offers, with its defaults.
  let c = avcodec_find_encoder_by_name(encoder.cstring)
  if c == nil: return
  result.presets = c.setting("preset")
  # x264 and x265 take free-form preset strings, which ffmpeg can't list;
  # their own headers can.
  if encoder == "libx264": result.presets.values = names(ae_x264_preset)
  elif encoder == "libx265": result.presets.values = names(ae_x265_preset)
  if encoder in ["libx264", "libx265"] and result.presets.default.len == 0:
    result.presets.default = "medium"

  # Render sets a profile by its codec-descriptor name, so offer those,
  # narrowed to what this encoder supports where it says.
  let supported =
    if encoder == "libx264": names(ae_x264_profile)
    elif encoder == "libx265": names(ae_x265_profile)
    elif ae_opt_kind(c, "profile") == 2: c.setting("profile").values
    else: @[]
  let ok = supported.mapIt(squash(it))
  var k = 0'i32
  while true:
    let n = ae_codec_profile(c, k)
    if n == nil: break
    let name = ($n).toLowerAscii
    # Intra-only and still-picture profiles don't suit a video edit.
    if (ok.len == 0 or squash(name) in ok) and "intra" notin name and
        "still" notin name and (encoder.startsWith("prores") or suits8bit420(name, c.id)):
      result.profiles.values.add name
    inc k
