## Content-aware editing powered by TwelveLabs Pegasus.
##
## Unlike `audio`/`motion`, which react to low-level signal energy, this method
## asks Pegasus (a video-understanding model) a natural-language question about
## the footage and marks the time spans that match as "loud" (label 1). For
## example `--edit pegasus --pegasus-prompt "a person is speaking on camera"`
## keeps the talking-head sections and cuts everything else, regardless of how
## loud they are. (The prompt lives in its own flag because `--edit` tokens
## cannot contain spaces.)
##
## It is fully opt-in: nothing here runs unless `pegasus` appears in `--edit`.
## The local file is uploaded to TwelveLabs as an asset, segmented with the
## `time_based_metadata` analysis mode, and the returned segments are rasterized
## onto the timebase the same way `subtitle` spans are.
##
## Auth comes from the `TWELVELABS_API_KEY` environment variable. Network calls
## go through `curl` (already required transitively and present everywhere),
## mirroring how `main.nim` shells out to `yt-dlp`, so this adds no new build- or
## link-time dependency such as an SSL-linked std/httpclient.

import std/[json, math, os, osproc, strformat]

import ../[ffmpeg, log]
import ../util/rational

const
  apiBase = "https://api.twelvelabs.io/v1.3"
  pollSeconds = 5
  maxPollSeconds = 600  # Pegasus on a long clip can take several minutes.

proc apiKey(): string =
  result = getEnv("TWELVELABS_API_KEY", "")
  if result == "":
    error "pegasus: set the TWELVELABS_API_KEY environment variable.\n" &
      "Get a free key at https://twelvelabs.io"

proc curlJson(key: string, args: openArray[string]): JsonNode =
  ## Run curl with the api key header (passed as an arg, never shell-expanded or
  ## logged) and parse stdout as JSON. Args run without a shell, so the API key
  ## and JSON body need no escaping. Mirrors how `main.nim` shells out to yt-dlp.
  let full = @["-sS", "-H", "x-api-key: " & key] & @args
  let output = try:
      execProcess("curl", args = full, options = {poUsePath})
    except OSError:
      error "pegasus: `curl` must be installed and on PATH."
  try:
    result = parseJson(output)
  except JsonParsingError:
    error "pegasus: could not parse TwelveLabs response (is curl installed?)."
  # The TwelveLabs API reports HTTP errors as a JSON body of {code, message}.
  if result.kind == JObject and result.hasKey("code") and result.hasKey("message"):
    error &"pegasus: TwelveLabs API error: {result[\"message\"].getStr}"

proc uploadAsset(key, path: string): string =
  ## Upload the local file as a `direct` asset and wait until it is ready.
  let resp = curlJson(key, [apiBase & "/assets",
    "-F", "method=direct", "-F", "file=@" & path])
  let assetId = resp{"_id"}.getStr
  if assetId == "":
    error "pegasus: upload did not return an asset id."

  for _ in 0 ..< (maxPollSeconds div pollSeconds):
    let status = curlJson(key, [apiBase & "/assets/" & assetId]){"status"}.getStr
    case status
    of "ready": return assetId
    of "failed": error "pegasus: TwelveLabs failed to process the upload."
    else: sleep(pollSeconds * 1000)
  error "pegasus: timed out waiting for the upload to be processed."

proc runSegmentation(key, assetId, prompt: string, minSeg: float): JsonNode =
  ## Kick off a time-based-metadata task and poll it to completion. Returns the
  ## decoded segment object: {"match": [{start_time, end_time, metadata}, ...]}.
  let body = $(%*{
    "video": {"type": "asset_id", "asset_id": assetId},
    "model_name": "pegasus1.5",
    "analysis_mode": "time_based_metadata",
    "min_segment_duration": minSeg,
    "response_format": {
      "type": "segment_definitions",
      "segment_definitions": [{
        "id": "match",
        "description": prompt,
        "fields": [{
          "name": "relevant",
          "type": "boolean",
          "description": "true when this segment matches: " & prompt,
        }],
      }],
    },
  })
  let task = curlJson(key, [apiBase & "/analyze/tasks",
    "-H", "Content-Type: application/json", "-d", body])
  let taskId = task{"task_id"}.getStr
  if taskId == "":
    error "pegasus: segmentation task was not created."

  for _ in 0 ..< (maxPollSeconds div pollSeconds):
    let resp = curlJson(key, [apiBase & "/analyze/tasks/" & taskId])
    case resp{"status"}.getStr
    of "ready":
      # result.data is itself a JSON-encoded string of the segments.
      let dataStr = resp{"result"}{"data"}.getStr
      try:
        return parseJson(dataStr)
      except JsonParsingError:
        error "pegasus: could not parse segmentation result."
    of "failed":
      error "pegasus: segmentation task failed."
    else:
      conwrite "Analyzing with Pegasus"
      sleep(pollSeconds * 1000)
  error "pegasus: timed out waiting for the segmentation result."

proc pegasus*(path: string, tb: AVRational, prompt: string, minSeg: float,
    lengthHint: int): seq[bool] =
  ## Return a per-timebase mask where `true` marks spans Pegasus reports as
  ## matching `prompt`. `lengthHint` is the timeline length so the mask covers
  ## the whole media even when the final segment is short.
  if prompt == "":
    error "pegasus: a prompt is required (--pegasus-prompt \"...\")."

  let key = apiKey()
  let assetId = uploadAsset(key, path)
  let segments = runSegmentation(key, assetId, prompt, minSeg){"match"}

  var spans: seq[(int, int)]
  var length = lengthHint
  if segments.kind == JArray:
    for seg in segments:
      # A segment counts as a match when its `relevant` field is true. Snap the
      # span outward (floor start, ceil end) so a partially-covered frame is
      # kept, matching the subtitle analyzer's convention.
      if not seg{"metadata"}{"relevant"}.getBool(true):
        continue
      let
        startF = seg{"start_time"}.getFloat
        endF = seg{"end_time"}.getFloat
        s = floor(startF * tb).int
        e = ceil(endF * tb).int
      length = max(length, e)
      spans.add((s, e))

  result = newSeq[bool](max(length, 0))
  for (s, e) in spans:
    for i in max(s, 0) ..< min(e, result.len):
      result[i] = true
