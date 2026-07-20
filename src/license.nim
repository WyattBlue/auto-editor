import std/[envvars, json, strformat, strutils, times]

import ./log
import ./util/fun
import vendor/libp2p/ed25519

const PUBLIC_KEY_HEX = "aa8512235f1e329522c00b23e473a810a31ec8ee9c727cda91c779c9db6aae0f"
const LICENSE_PERIOD_YEARS = 3
const LICENSE_EXPIRY_YEARS = 4
let buildDate = parse(CompileDate, "yyyy-MM-dd")

proc validateKey*(val: string): (bool, string) =
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

proc addYears(issued: DateTime, years: int): DateTime =
  let expiresYear = issued.year + years
  let expiresDay = min(issued.monthday, getDaysInMonth(issued.month, expiresYear))
  dateTime(expiresYear, issued.month, expiresDay, zone = local())

proc warnIfOutOfPeriod(payload: JsonNode) =
  let issuedText = payload{"issued"}.getStr
  if issuedText == "":
    return

  let issued =
    try:
      parse(issuedText, "yyyy-MM-dd")
    except TimeParseError:
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
    warning &"License update period ended on {expires.format(\"yyyy-MM-dd\")}. " &
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
