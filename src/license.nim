import std/[envvars, json, strformat, strutils]

import ./log
import ./util/fun
import vendor/libp2p/ed25519

const PUBLIC_KEY_HEX = "aa8512235f1e329522c00b23e473a810a31ec8ee9c727cda91c779c9db6aae0f"
const LICENSE_PERIOD_YEARS = 3
const LICENSE_EXPIRY_YEARS = 4
const buildDate = CompileDate  # in "yyyy-MM-dd" text so `<` is chronological.
const
  FREE_RENDER_LONG_SIDE* = 3200'i32
  FREE_RENDER_SHORT_SIDE* = 1800'i32
  FREE_MULTI_SOURCE_LONG_SIDE* = 720'i32
  FREE_MULTI_SOURCE_SHORT_SIDE* = 576'i32

func fitsFreeRenderResolution*(width, height: int32): bool {.raises: [].} =
  max(width, height) <= FREE_RENDER_LONG_SIDE and
    min(width, height) <= FREE_RENDER_SHORT_SIDE

func fitsFreeMultiSourceResolution*(width, height: int32): bool {.raises: [].} =
  max(width, height) <= FREE_MULTI_SOURCE_LONG_SIDE and
    min(width, height) <= FREE_MULTI_SOURCE_SHORT_SIDE

func freeMultiSourceScale*(width, height: int32): float64 {.raises: [].} =
  ## Return the largest non-upscaling factor that fits inside an SD frame.
  ## Compare long and short sides so portrait renders get the rotated limit.
  if width <= 0 or height <= 0:
    return 1.0
  min(1.0, min(
    FREE_MULTI_SOURCE_LONG_SIDE.float64 / max(width, height).float64,
    FREE_MULTI_SOURCE_SHORT_SIDE.float64 / min(width, height).float64,
  ))

proc validateKey*(val: string): (bool, string) {.raises: [].} =
  if val == "":
    return (false, "")

  let parts = val.split('.')
  if parts.len != 2:
    return (false, "bfmt")

  let (payloadBytes, sigBytes) = (
    try: (b64urlDecode(parts[0]), b64urlDecode(parts[1]))
    except ValueError: return (false, "bfmt")
  )

  if sigBytes.len != EdSignatureSize:
    return (false, "Bad signature length")

  var pubKey: EdPublicKey
  if not init(pubKey, PUBLIC_KEY_HEX):
    return (false, "Failed to load public key")

  var sig: EdSignature
  if not init(sig, sigBytes):
    return (false, "Bad signature length")

  if verify(sig, payloadBytes, pubKey):
    return (true, cast[string](payloadBytes))
  return (false, "Incorrect key")

func addYears*(issued: string, years: int): string =
  ## `issued` must be a valid "yyyy-MM-dd". Feb 29 lands on Feb 28 in non-leap years.
  let year = parseInt(issued[0 ..< 4]) + years
  let isLeap = year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0)
  let monthDay = if issued[4 .. ^1] == "-02-29" and not isLeap: "-02-28"
                 else: issued[4 .. ^1]
  &"{year:04}{monthDay}"

func isDate*(s: string): bool =
  if s.len != 10 or s[4] != '-' or s[7] != '-':
    return false
  for i in [0, 1, 2, 3, 5, 6, 8, 9]:
    if s[i] notin '0' .. '9':
      return false
  true

proc warnIfOutOfPeriod(payload: JsonNode) =
  let issued = payload{"issued"}.getStr
  if not issued.isDate:
    return

  let expires = issued.addYears(LICENSE_PERIOD_YEARS)
  let hardExpires = issued.addYears(LICENSE_EXPIRY_YEARS)
  if buildDate >= hardExpires:
    stderr.writeLine(
      "This license is expired, you must buy or renew your license. " &
        "https://app.auto-editor.com/upgrade?from=cli\n\n" &
        "Alternatively, you may use this program without a license key.\n"
    )
    error "License is expired."
  if buildDate >= expires:
    warning &"License update period ended on {expires}. " &
      "Newer auto-editor releases may require a renewal."

proc requireLicense*(args: mainArgs, feature: string) =
  ## Gate a paid feature behind a valid license key. The key comes from
  ## `-k`/`--license-key` (stored on `args`) or the `AE_PRIVATE_LK` env var.
  ## Errors (and exits) with a feature-specific message when no valid key is set.
  var key = args.licenseKey
  if key == "":
    key = getEnv("AE_PRIVATE_LK", "")

  let (isValid, reason) = validateKey(key)
  if isValid:
    let payload = parseJson(reason)
    # Subscription tiers must be server validated.
    if payload{"tier"}.getStr == "sub":
      # Just print an error for now
      error "Update auto-editor to a newer version"
    warnIfOutOfPeriod(payload)
    return

  if reason == "":
    error &"You must provide a license key to {feature}.\n" &
      "Set one with -k/--license-key. You can get a key at https://app.auto-editor.com"
  elif reason == "bfmt":
    error "License key is in a bad format.\nYou can get a key at https://app.auto-editor.com"
  else:
    error reason

proc licenseKeyProvided*(args: mainArgs): bool {.raises: [].} =
  args.licenseKey != "" or getEnv("AE_PRIVATE_LK", "") != ""
