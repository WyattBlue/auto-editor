## The kinds of edit-point transitions, after Premiere Pro's own (its Film
## Impact, Morph Cut and Immersive Video sets, and its audio crossfades).

type
  TransitionKind* = enum
    tkDissolve # Cross Dissolve on video, Constant Gain on audio
    # Animation
    tkBlockMotion, tkFlipMotion, tkFoldMotion, tkPopMotion, tkPullMotion,
    tkSpinMotion, tkSpringMotion, tkTravelMotion,
    # Dissolve
    tkAdditiveDissolve, tkBlurDissolve, tkBurnAlpha, tkDipToBlack, tkDipToColor,
    tkDipToWhite, tkFilmDissolve, tkLumaFade, tkMorphCut, tkMosaic,
    # Grunge & Distort
    tkChaos, tkEarthquake, tkFlicker, tkGlass, tkGlitch, tkGrunge,
    tkKaleidoscope, tkLiquidDistortion, tkTvPower, tkVhsDamage,
    # Immersive Video
    tkVrChromaLeaks, tkVrGradientWipe, tkVrIrisWipe, tkVrLightLeaks,
    tkVrLightRays, tkVrMobiusZoom, tkVrRandomBlocks, tkVrSphericalBlur,
    # Lights & Blurs
    tkBurnChroma, tkChromaLeak, tkCrossZoom, tkDirectionalBlur, tkFlare,
    tkFlash, tkGlow, tkLensBlur, tkLightLeak, tkLightSweep, tkPhosphor,
    tkRadialBlur, tkRay, tkSolarize, tkStripe, tkZoomBlur,
    # Slide
    tk3dRoll, tkFilmRoll, tkPush, tkRoll, tkSlide, tkSplit, tkStretch, tkWhip,
    # Smart Tools
    tkMotionCamera, tkMotionTween, tkShapeDissolve, tkShapeFlow,
    # Text
    tkTextAnimator, tkTypewriter,
    # Transformers
    tk3dSpin, tk3dSpinback, tkFrame, tkLouver, tkMirror, tkPagePeel, tkSlice,
    tkWave,
    # Wipe
    tkClockWipe, tkLinearWipe, tkNeonWipe, tkPanelWipe, tkPlateauWipe,
    tkRadialWipe, tkSoftWipe, tkStarWipe, tkStretchWipe,
    # Legacy
    tkAdditiveDissolveLegacy, tkBarnDoors, tkCenterSplit, tkClockWipeLegacy,
    tkCrossDissolveLegacy, tkCrossZoomLegacy, tkDipToBlackLegacy,
    tkDipToWhiteLegacy, tkFilmDissolveLegacy, tkInset, tkIrisBox, tkIrisCross,
    tkIrisDiamond, tkIrisRound, tkNonAdditiveDissolve, tkPushLegacy,
    tkRadialWipeLegacy, tkSlideLegacy, tkSplitLegacy, tkWhipLegacy, tkWipe,
    # Audio crossfades
    tkConstantPower, tkExponentialFade

  TransitionInfo* = object
    id*: string        # the name in v3 files and on the command line
    name*: string      # Premiere's name
    matchName*: string # Premiere's internal name, as its OTIO files carry it

const audioKinds* = {tkDissolve, tkConstantPower, tkExponentialFade}
const videoKinds* = {low(TransitionKind) .. high(TransitionKind)} -
  {tkConstantPower, tkExponentialFade}

func ti(id, name, matchName: string): TransitionInfo =
  TransitionInfo(id: id, name: name, matchName: matchName)

const transitionInfo*: array[TransitionKind, TransitionInfo] = [
  tkDissolve: ti("dissolve", "Cross Dissolve", "AE.AE_Impact_Dissolve"),
  tkBlockMotion: ti("block-motion", "Block Motion", "AE.AE_Impact_3D_Block"),
  tkFlipMotion: ti("flip-motion", "Flip Motion", "AE.AE_Impact_3D_Flip"),
  tkFoldMotion: ti("fold-motion", "Fold Motion", "AE.AE_Impact_Fold"),
  tkPopMotion: ti("pop-motion", "Pop Motion", "AE.AE_Impact_Pop"),
  tkPullMotion: ti("pull-motion", "Pull Motion", "AE.AE_Impact_Pull"),
  tkSpinMotion: ti("spin-motion", "Spin Motion", "AE.AE_Impact_Spin"),
  tkSpringMotion: ti("spring-motion", "Spring Motion", "AE.AE_Impact_Spring"),
  tkTravelMotion: ti("travel-motion", "Travel Motion", "AE.AE_Impact_C-Push"),
  tkAdditiveDissolve: ti("additive-dissolve", "Additive Dissolve",
    "AE.Impact_Additive_Dissolve"),
  tkBlurDissolve: ti("blur-dissolve", "Blur Dissolve", "AE.AE_Impact_Blur_dissolve"),
  tkBurnAlpha: ti("burn-alpha", "Burn Alpha", "AE.AE_Impact_Burn_Alpha"),
  tkDipToBlack: ti("dip-to-black", "Dip to Black", "AE.AE_Impact_Dip_To_Black"),
  tkDipToColor: ti("dip-to-color", "Dip to Color", "AE.AE_Impact_Blur_To_Color"),
  tkDipToWhite: ti("dip-to-white", "Dip to White", "AE.AE_Impact_Dip_To_White"),
  tkFilmDissolve: ti("film-dissolve", "Film Dissolve", "AE.Impact_Film_Dissolve"),
  tkLumaFade: ti("luma-fade", "Luma Fade", "AE.AE_Impact_Luma_Fade"),
  tkMorphCut: ti("morph-cut", "Morph Cut", "AE.ADBE MorphCut"),
  tkMosaic: ti("mosaic", "Mosaic", "AE.AE_Impact_Mosaic"),
  tkChaos: ti("chaos", "Chaos", "AE.AE_Impact_Chaos"),
  tkEarthquake: ti("earthquake", "Earthquake", "AE.AE_Impact_Earthquake"),
  tkFlicker: ti("flicker", "Flicker", "AE.AE_Impact_Flicker"),
  tkGlass: ti("glass", "Glass", "AE.AE_Impact_Glass"),
  tkGlitch: ti("glitch", "Glitch", "AE.AE_Impact_Glitch"),
  tkGrunge: ti("grunge", "Grunge", "AE.AE_Impact_Grunge"),
  tkKaleidoscope: ti("kaleidoscope", "Kaleidoscope", "AE.AE_Impact_Kaleido"),
  tkLiquidDistortion: ti("liquid-distortion", "Liquid Distortion",
    "AE.AE_Impact_Liquid_Distortion"),
  tkTvPower: ti("tv-power", "TV Power", "AE.AE_Impact_TV_Power"),
  tkVhsDamage: ti("vhs-damage", "VHS Damage", "AE.AE_Impact_VHS_Damage"),
  tkVrChromaLeaks: ti("vr-chroma-leaks", "VR Chroma Leaks",
    "AE.Mettle SkyBox Chroma Leaks"),
  tkVrGradientWipe: ti("vr-gradient-wipe", "VR Gradient Wipe",
    "AE.Mettle SkyBox Gradient Wipe"),
  tkVrIrisWipe: ti("vr-iris-wipe", "VR Iris Wipe", "AE.Mettle SkyBox Iris Wipe"),
  tkVrLightLeaks: ti("vr-light-leaks", "VR Light Leaks",
    "AE.Mettle SkyBox Light Leaks"),
  tkVrLightRays: ti("vr-light-rays", "VR Light Rays", "AE.Mettle SkyBox Rays"),
  tkVrMobiusZoom: ti("vr-mobius-zoom", "VR Mobius Zoom",
    "AE.Mettle SkyBox Mobius Zoom"),
  tkVrRandomBlocks: ti("vr-random-blocks", "VR Random Blocks",
    "AE.Mettle SkyBox Random Blocks"),
  tkVrSphericalBlur: ti("vr-spherical-blur", "VR Spherical Blur",
    "AE.Mettle SkyBox Radial Blur"),
  tkBurnChroma: ti("burn-chroma", "Burn Chroma", "AE.AE_Impact_Burn_White"),
  tkChromaLeak: ti("chroma-leak", "Chroma Leak", "AE.AE_Impact_Chroma_Leaks"),
  tkCrossZoom: ti("cross-zoom", "Cross Zoom", "AE.Impact_Cross_Zoom"),
  tkDirectionalBlur: ti("directional-blur", "Directional Blur",
    "AE.AE_Impact_Directional_Blur"),
  tkFlare: ti("flare", "Flare", "AE.AE_Impact_Flare"),
  tkFlash: ti("flash", "Flash", "AE.AE_Impact_Flash"),
  tkGlow: ti("glow", "Glow", "AE.AE_Impact_Glow"),
  tkLensBlur: ti("lens-blur", "Lens Blur", "AE.AE_Impact_Lens_Blur"),
  tkLightLeak: ti("light-leak", "Light Leak", "AE.AE_Impact_Light_Leaks"),
  tkLightSweep: ti("light-sweep", "Light Sweep", "AE.AE_Impact_Light_Sweep"),
  tkPhosphor: ti("phosphor", "Phosphor", "AE.AE_Impact_Phosphore"),
  tkRadialBlur: ti("radial-blur", "Radial Blur", "AE.AE_Impact_Radial_Blur"),
  tkRay: ti("ray", "Ray", "AE.AE_Impact_Rays"),
  tkSolarize: ti("solarize", "Solarize", "AE.AE_Impact_Solarize"),
  tkStripe: ti("stripe", "Stripe", "AE.AE_Impact_Stripes"),
  tkZoomBlur: ti("zoom-blur", "Zoom Blur", "AE.AE_Impact_Zoom_Blur"),
  tk3dRoll: ti("3d-roll", "3D Roll", "AE.AE_Impact_3D_Roll"),
  tkFilmRoll: ti("film-roll", "Film Roll", "AE.AE_Impact_Film_Roll"),
  tkPush: ti("push", "Push", "AE.AE_Impact_Push"),
  tkRoll: ti("roll", "Roll", "AE.AE_Impact_Roll"),
  tkSlide: ti("slide", "Slide", "AE.AE_Custom_Impact_Fall"),
  tkSplit: ti("split", "Split", "AE.AE_Impact_Split"),
  tkStretch: ti("stretch", "Stretch", "AE.AE_Impact_Stretch"),
  tkWhip: ti("whip", "Whip", "AE.Impact_Whip"),
  tkMotionCamera: ti("motion-camera", "Motion Camera", "AE.AE_Impact_Warp"),
  tkMotionTween: ti("motion-tween", "Motion Tween", "AE.AE_Impact_Animate"),
  tkShapeDissolve: ti("shape-dissolve", "Shape Dissolve",
    "AE.AE_Impact_Shape_Dissolve"),
  tkShapeFlow: ti("shape-flow", "Shape Flow", "AE.AE_Impact_Shape_Flow"),
  tkTextAnimator: ti("text-animator", "Text Animator", "AE.AE_Impact_Text_Animator"),
  tkTypewriter: ti("typewriter", "Typewriter", "AE.AE_Impact_Typewriter"),
  tk3dSpin: ti("3d-spin", "3D Spin", "AE.AE_Impact_3D_Rotate"),
  tk3dSpinback: ti("3d-spinback", "3D Spinback", "AE.AE_Custom_Impact_Spinback_3D"),
  tkFrame: ti("frame", "Frame", "AE.AE_Impact_Frame"),
  tkLouver: ti("louver", "Louver", "AE.AE_Impact_3D_Blinds"),
  tkMirror: ti("mirror", "Mirror", "AE.AE_Impact_Mirror"),
  tkPagePeel: ti("page-peel", "Page Peel", "AE.AE_Impact_Page_Peel"),
  tkSlice: ti("slice", "Slice", "AE.AE_Impact_Slice"),
  tkWave: ti("wave", "Wave", "AE.AE_Impact_Wave"),
  tkClockWipe: ti("clock-wipe", "Clock Wipe", "AE.AE_Impact_Clock_Wipe"),
  tkLinearWipe: ti("linear-wipe", "Linear Wipe", "AE.AE_Impact_Linear_Wipe"),
  tkNeonWipe: ti("neon-wipe", "Neon Wipe", "AE.AE_Impact_Copy_Machine"),
  tkPanelWipe: ti("panel-wipe", "Panel Wipe", "AE.AE_Impact_PanelWipe"),
  tkPlateauWipe: ti("plateau-wipe", "Plateau Wipe", "AE.AE_Impact_Plateau_Wipe"),
  tkRadialWipe: ti("radial-wipe", "Radial Wipe", "AE.Impact_Radial_Wipe"),
  tkSoftWipe: ti("soft-wipe", "Soft Wipe", "AE.AE_Impact_Wipe"),
  tkStarWipe: ti("star-wipe", "Star Wipe", "AE.AE_Impact_Star_Wipe"),
  tkStretchWipe: ti("stretch-wipe", "Stretch Wipe", "AE.AE_Impact_Stretch_Wipe"),
  tkAdditiveDissolveLegacy: ti("additive-dissolve-legacy",
    "Additive Dissolve (Legacy)", "ADBE Additive Dissolve"),
  tkBarnDoors: ti("barn-doors", "Barn Doors", "AE.ADBE Barn Doors"),
  tkCenterSplit: ti("center-split", "Center Split", "AE.ADBE Center Split"),
  tkClockWipeLegacy: ti("clock-wipe-legacy", "Clock Wipe (Legacy)", "AE.ADBE Clock Wipe"),
  tkCrossDissolveLegacy: ti("cross-dissolve-legacy", "Cross Dissolve (Legacy)",
    "AE.ADBE Cross Dissolve New"),
  tkCrossZoomLegacy: ti("cross-zoom-legacy", "Cross Zoom (Legacy)", "ADBE Cross Zoom"),
  tkDipToBlackLegacy: ti("dip-to-black-legacy", "Dip to Black (Legacy)",
    "AE.ADBE Dip To Black"),
  tkDipToWhiteLegacy: ti("dip-to-white-legacy", "Dip to White (Legacy)",
    "AE.ADBE Dip To White"),
  tkFilmDissolveLegacy: ti("film-dissolve-legacy", "Film Dissolve (Legacy)",
    "ADBE Film Dissolve"),
  tkInset: ti("inset", "Inset", "AE.ADBE Inset"),
  tkIrisBox: ti("iris-box", "Iris Box", "ADBE Iris Square"),
  tkIrisCross: ti("iris-cross", "Iris Cross", "ADBE Iris Cross"),
  tkIrisDiamond: ti("iris-diamond", "Iris Diamond", "ADBE Iris Diamond"),
  tkIrisRound: ti("iris-round", "Iris Round", "ADBE Iris Round"),
  tkNonAdditiveDissolve: ti("non-additive-dissolve", "Non-Additive Dissolve",
    "AE.ADBE Non-Additive Dissolve"),
  tkPushLegacy: ti("push-legacy", "Push (Legacy)", "ADBE Push"),
  tkRadialWipeLegacy: ti("radial-wipe-legacy", "Radial Wipe (Legacy)",
    "AE.ADBE Radial Wipe"),
  tkSlideLegacy: ti("slide-legacy", "Slide (Legacy)", "ADBE Slide"),
  tkSplitLegacy: ti("split-legacy", "Split (Legacy)", "AE.ADBE Split"),
  tkWhipLegacy: ti("whip-legacy", "Whip (Legacy)", "AE.ADBE Whip"),
  tkWipe: ti("wipe", "Wipe", "ADBE Wipe"),
  tkConstantPower: ti("constant-power", "Constant Power", "Custom Fade"),
  tkExponentialFade: ti("exponential-fade", "Exponential Fade", "Exponential Fade"),
]

func `$`*(kind: TransitionKind): string = transitionInfo[kind].id

func parseTransitionKind*(id: string, kind: var TransitionKind): bool =
  ## "constant-gain" names the audio side of a dissolve.
  if id == "constant-gain":
    kind = tkDissolve
    return true
  for k in TransitionKind:
    if transitionInfo[k].id == id:
      kind = k
      return true
  false

func kindFromMatchName*(matchName: string, kind: var TransitionKind): bool =
  ## Premiere's Constant Gain is a dissolve too.
  if matchName == "Constant Gain":
    kind = tkDissolve
    return true
  # Premiere writes some with an "AE." in front and some without, and the
  # same transition both ways in different files.
  func bare(s: string): string =
    if s.len > 3 and s[0 .. 2] == "AE.": s[3 .. ^1] else: s
  for k in TransitionKind:
    if bare(transitionInfo[k].matchName) == bare(matchName):
      kind = k
      return true
  false

func normalized(name: string): string =
  for ch in name:
    if ch in {'A' .. 'Z'}: result.add chr(ord(ch) + 32)
    elif ch in {'a' .. 'z', '0' .. '9', '+'}: result.add ch

func kindFromName*(name: string, video: bool, kind: var TransitionKind): bool =
  ## The kind an editor's transition name stands for: Premiere's names, and
  ## the names FCP7 XML and FCPXML give their counterparts.
  let n = normalized(name)
  if video:
    case n
    of "crossdissolve": kind = tkDissolve
    of "diptocolordissolve", "fadetocolor": kind = tkDipToBlackLegacy
    of "additivedissolve": kind = tkAdditiveDissolve
    of "clock", "clockwipe": kind = tkClockWipe
    of "edgewipe", "wipe": kind = tkWipe
    of "ovaliris", "circle": kind = tkIrisRound
    of "rectangleiris": kind = tkIrisBox
    of "diamondiris": kind = tkIrisDiamond
    of "crossiris": kind = tkIrisCross
    of "insetwipe": kind = tkInset
    of "star", "stariris": kind = tkStarWipe
    of "pushslide": kind = tkPush
    of "splitslide", "centersplitslide": kind = tkSplit
    of "pagecurl": kind = tkPagePeel
    of "crossstretch": kind = tkStretch
    of "venetianblindwipe": kind = tkLouver
    of "smoothcut": kind = tkMorphCut
    else:
      for k in videoKinds:
        if normalized(transitionInfo[k].name) == n:
          kind = k
          return true
      return false
    return true
  case n
  of "crossfade0db", "constantgain", "kgaudiotranscrossfade0db": kind = tkDissolve
  of "crossfade+3db", "constantpower", "customfade": kind = tkConstantPower
  of "exponentialfade": kind = tkExponentialFade
  else: return false
  true
