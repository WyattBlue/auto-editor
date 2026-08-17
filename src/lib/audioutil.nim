const audioChannelNames* = [
  ("left", "FL"), ("right", "FR"), ("center", "FC"), ("lfe", "LFE"),
  ("back-left", "BL"), ("back-right", "BR"),
  ("front-left-of-center", "FLC"), ("front-right-of-center", "FRC"),
  ("back-center", "BC"), ("side-left", "SL"), ("side-right", "SR"),
  ("top-center", "TC"), ("top-front-left", "TFL"),
  ("top-front-center", "TFC"), ("top-front-right", "TFR"),
  ("top-back-left", "TBL"), ("top-back-center", "TBC"),
  ("top-back-right", "TBR"), ("stereo-left", "DL"),
  ("stereo-right", "DR"), ("wide-left", "WL"), ("wide-right", "WR"),
  ("surround-direct-left", "SDL"), ("surround-direct-right", "SDR"),
  ("lfe-2", "LFE2"), ("top-side-left", "TSL"),
  ("top-side-right", "TSR"), ("bottom-front-center", "BFC"),
  ("bottom-front-left", "BFL"), ("bottom-front-right", "BFR"),
]

func audioChannelCode*(name: string): string {.raises: [].} =
  for (friendly, code) in audioChannelNames:
    if name == friendly:
      return code
