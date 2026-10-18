import ./ffmpeg

type
  ASS_Library* {.importc, header: "<ass/ass.h>", incompleteStruct.} = object
  ASS_Renderer* {.importc, header: "<ass/ass.h>", incompleteStruct.} = object
  ASS_Track* {.importc, header: "<ass/ass.h>".} = object
    PlayResX*, PlayResY*: cint
    YCbCrMatrix*: cint
  ASS_Image* {.importc, header: "<ass/ass.h>".} = object
    w*, h*, stride*: cint
    bitmap*: ptr UncheckedArray[uint8] ## coverage, 255 for full
    color*: uint32                     ## 0xRRGGBBAA, its alpha counting transparency
    dst_x*, dst_y*: cint
    next*: ptr ASS_Image
  ASS_MessageCallback* =
    proc(level: cint, fmt: ConstCString, args: VaList, data: pointer) {.cdecl.}

let
  ASS_FONTPROVIDER_AUTODETECT* {.importc, header: "<ass/ass.h>".}: cint
  ASS_FEATURE_WRAP_UNICODE* {.importc, header: "<ass/ass.h>".}: cint

const
  YCBCR_NONE* = 2.cint
  YCBCR_BT601_PC* = 4.cint
  YCBCR_BT709_TV* = 5.cint
  YCBCR_BT709_PC* = 6.cint
  YCBCR_SMPTE240M_TV* = 7.cint
  YCBCR_SMPTE240M_PC* = 8.cint
  YCBCR_FCC_TV* = 9.cint
  YCBCR_FCC_PC* = 10.cint

{.push importc, header: "<ass/ass.h>".}
proc ass_library_init*(): ptr ASS_Library
proc ass_library_done*(lib: ptr ASS_Library)
proc ass_set_message_cb*(lib: ptr ASS_Library, cb: ASS_MessageCallback, data: pointer)
proc ass_set_extract_fonts*(lib: ptr ASS_Library, extract: cint)
proc ass_set_style_overrides*(lib: ptr ASS_Library, list: cstringArray)
proc ass_add_font*(lib: ptr ASS_Library, name, data: cstring, size: cint)

proc ass_renderer_init*(lib: ptr ASS_Library): ptr ASS_Renderer
proc ass_renderer_done*(r: ptr ASS_Renderer)
proc ass_set_frame_size*(r: ptr ASS_Renderer, w, h: cint)
proc ass_set_storage_size*(r: ptr ASS_Renderer, w, h: cint)
proc ass_set_fonts*(r: ptr ASS_Renderer, defaultFont, defaultFamily: cstring,
    provider: cint, config: cstring, update: cint)
proc ass_render_frame*(r: ptr ASS_Renderer, track: ptr ASS_Track, now: clonglong,
    changed: ptr cint): ptr ASS_Image

proc ass_new_track*(lib: ptr ASS_Library): ptr ASS_Track
proc ass_read_memory*(lib: ptr ASS_Library, buf: cstring, size: csize_t,
    codepage: cstring): ptr ASS_Track
proc ass_free_track*(track: ptr ASS_Track)
proc ass_track_set_feature*(track: ptr ASS_Track, feature, enable: cint): cint
proc ass_process_codec_private*(track: ptr ASS_Track, data: cstring, size: cint)
proc ass_process_chunk*(track: ptr ASS_Track, data: cstring, size: cint,
    timecode, duration: clonglong)
proc ass_process_force_style*(track: ptr ASS_Track)
{.pop.}
