import std/[algorithm, json, strutils]

type Lang* = array[4, char]

func `$`*(lang: Lang): string =
  for i in 0 ..< 4:
    if lang[i] == '\0':
      break
    result.add lang[i]

func `%`*(lang: Lang): JsonNode =
  %($lang)

const undLang: Lang = ['u', 'n', 'd', '\0']

# ISO 639-1 codes and their ISO 639-2/T equivalents, from FFmpeg's
# libavformat/avlanguage.c. MP4 only stores three-letter codes.
const iso639_1 = [
  ("aa", "aar"), ("ab", "abk"), ("ae", "ave"), ("af", "afr"), ("ak", "aka"), ("am", "amh"),
  ("an", "arg"), ("ar", "ara"), ("as", "asm"), ("av", "ava"), ("ay", "aym"), ("az", "aze"),
  ("ba", "bak"), ("be", "bel"), ("bg", "bul"), ("bh", "bih"), ("bi", "bis"), ("bm", "bam"),
  ("bn", "ben"), ("bo", "bod"), ("br", "bre"), ("bs", "bos"), ("ca", "cat"), ("ce", "che"),
  ("ch", "cha"), ("co", "cos"), ("cr", "cre"), ("cs", "ces"), ("cu", "chu"), ("cv", "chv"),
  ("cy", "cym"), ("da", "dan"), ("de", "deu"), ("dv", "div"), ("dz", "dzo"), ("ee", "ewe"),
  ("el", "ell"), ("en", "eng"), ("eo", "epo"), ("es", "spa"), ("et", "est"), ("eu", "eus"),
  ("fa", "fas"), ("ff", "ful"), ("fi", "fin"), ("fj", "fij"), ("fo", "fao"), ("fr", "fra"),
  ("fy", "fry"), ("ga", "gle"), ("gd", "gla"), ("gl", "glg"), ("gn", "grn"), ("gu", "guj"),
  ("gv", "glv"), ("ha", "hau"), ("he", "heb"), ("hi", "hin"), ("ho", "hmo"), ("hr", "hrv"),
  ("ht", "hat"), ("hu", "hun"), ("hy", "hye"), ("hz", "her"), ("ia", "ina"), ("id", "ind"),
  ("ie", "ile"), ("ig", "ibo"), ("ii", "iii"), ("ik", "ipk"), ("in", "ind"), ("io", "ido"),
  ("is", "isl"), ("it", "ita"), ("iu", "iku"), ("iw", "heb"), ("ja", "jpn"), ("ji", "yid"),
  ("jv", "jav"), ("jw", "jav"), ("ka", "kat"), ("kg", "kon"), ("ki", "kik"), ("kj", "kua"),
  ("kk", "kaz"), ("kl", "kal"), ("km", "khm"), ("kn", "kan"), ("ko", "kor"), ("kr", "kau"),
  ("ks", "kas"), ("ku", "kur"), ("kv", "kom"), ("kw", "cor"), ("ky", "kir"), ("la", "lat"),
  ("lb", "ltz"), ("lg", "lug"), ("li", "lim"), ("ln", "lin"), ("lo", "lao"), ("lt", "lit"),
  ("lu", "lub"), ("lv", "lav"), ("mg", "mlg"), ("mh", "mah"), ("mi", "mri"), ("mk", "mkd"),
  ("ml", "mal"), ("mn", "mon"), ("mo", "ron"), ("mr", "mar"), ("ms", "msa"), ("mt", "mlt"),
  ("my", "mya"), ("na", "nau"), ("nb", "nob"), ("nd", "nde"), ("ne", "nep"), ("ng", "ndo"),
  ("nl", "nld"), ("nn", "nno"), ("no", "nor"), ("nr", "nbl"), ("nv", "nav"), ("ny", "nya"),
  ("oc", "oci"), ("oj", "oji"), ("om", "orm"), ("or", "ori"), ("os", "oss"), ("pa", "pan"),
  ("pi", "pli"), ("pl", "pol"), ("ps", "pus"), ("pt", "por"), ("qu", "que"), ("rm", "roh"),
  ("rn", "run"), ("ro", "ron"), ("ru", "rus"), ("rw", "kin"), ("sa", "san"), ("sc", "srd"),
  ("sd", "snd"), ("se", "sme"), ("sg", "sag"), ("si", "sin"), ("sk", "slk"), ("sl", "slv"),
  ("sm", "smo"), ("sn", "sna"), ("so", "som"), ("sq", "sqi"), ("sr", "srp"), ("ss", "ssw"),
  ("st", "sot"), ("su", "sun"), ("sv", "swe"), ("sw", "swa"), ("ta", "tam"), ("te", "tel"),
  ("tg", "tgk"), ("th", "tha"), ("ti", "tir"), ("tk", "tuk"), ("tl", "tgl"), ("tn", "tsn"),
  ("to", "ton"), ("tr", "tur"), ("ts", "tso"), ("tt", "tat"), ("tw", "twi"), ("ty", "tah"),
  ("ug", "uig"), ("uk", "ukr"), ("ur", "urd"), ("uz", "uzb"), ("ve", "ven"), ("vi", "vie"),
  ("vo", "vol"), ("wa", "wln"), ("wo", "wol"), ("xh", "xho"), ("yi", "yid"), ("yo", "yor"),
  ("za", "zha"), ("zh", "zho"), ("zu", "zul")
]

# ISO 639-2/B codes and the 639-2/T codes for the same languages, so each
# language has one spelling.
const iso639_2b = [
  ("alb", "sqi"), ("arm", "hye"), ("baq", "eus"), ("bur", "mya"), ("chi", "zho"), ("cze", "ces"),
  ("dut", "nld"), ("fre", "fra"), ("geo", "kat"), ("ger", "deu"), ("gre", "ell"), ("ice", "isl"),
  ("mac", "mkd"), ("mao", "mri"), ("may", "msa"), ("per", "fas"), ("rum", "ron"), ("slo", "slk"),
  ("tib", "bod"), ("wel", "cym")
]

func cmpKey(entry: (string, string), code: string): int = cmp(entry[0], code)

func toLang*(a: string): Lang =
  ## The ISO 639-2/T code for the language `a` starts with, ignoring any
  ## region subtag as in "en-US": "eng". "und" when it isn't a language code.
  var n = 0
  while n < a.len and a[n] notin {'-', '_'}: inc n
  var code = a[0 ..< n].toLowerAscii
  if n notin 2..3 or not code.allCharsInSet({'a'..'z'}): return undLang
  if n == 2:
    let i = iso639_1.binarySearch(code, cmpKey)
    if i < 0: return undLang
    code = iso639_1[i][1]
  else:
    let i = iso639_2b.binarySearch(code, cmpKey)
    if i >= 0: code = iso639_2b[i][1]
  for i in 0 ..< 3: result[i] = code[i]

iterator iso639_1Codes*(lang: Lang): string =
  ## The ISO 639-1 codes for `lang`, deprecated ones like "iw" included.
  let code = $lang
  for (two, three) in iso639_1:
    if three == code: yield two
