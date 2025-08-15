import std/tables

import ../ffmpeg

const AV_DICT_IGNORE_SUFFIX = 2

proc avdict_to_dict*(input: ptr AVDictionary): Table[string, string] =
  var element: ptr AVDictionaryEntry = nil
  while true:
    element = av_dict_get(input, "", element, AV_DICT_IGNORE_SUFFIX)
    if element == nil:
      break
    result[$(element.key)] = $(element.value)

proc dictToAvdict*(dst: ptr ptr AVDictionary, src: Table[string, string]) =
  ## Convert a Nim Table to an AVDictionary
  av_dict_free(dst)
  var ret: cint
  for key, value in src:
    ret = av_dict_set(dst, key.cstring, value.cstring, 0)
