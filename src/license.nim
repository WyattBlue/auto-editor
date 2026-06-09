import std/[envvars, strformat, strutils]

import ./log
import ./util/fun
import vendor/libp2p/ed25519

const PUBLIC_KEY_HEX = "aa8512235f1e329522c00b23e473a810a31ec8ee9c727cda91c779c9db6aae0f"

proc validateKey*(val: string): (bool, string) =
  if val == "":
    return (false, "")

  let parts = val.split('.')
  if parts.len != 2:
    return (false, "bfmt")

  let payloadBytes = b64urlDecode(parts[0])
  let sigBytes = b64urlDecode(parts[1])

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

proc requireLicense*(args: mainArgs, feature: string) =
  ## Gate a paid feature behind a valid license key. The key comes from
  ## `-k`/`--license-key` (stored on `args`) or the `AE_PRIVATE_LK` env var.
  ## Errors (and exits) with a feature-specific message when no valid key is set.
  var key = args.licenseKey
  if key == "":
    key = getEnv("AE_PRIVATE_LK", "")

  let (isValid, reason) = validateKey(key)
  if isValid:
    return

  if reason == "":
    error &"You must provide a license key to {feature}.\n" &
      "Set one with -k/--license-key. You can get a key at https://app.auto-editor.com"
  elif reason == "bfmt":
    error "License key is in a bad format.\nYou can get a key at https://app.auto-editor.com"
  else:
    error reason
