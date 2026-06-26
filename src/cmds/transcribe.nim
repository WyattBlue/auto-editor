import std/[os, strutils, strformat, httpclient, json, base64]
import ../[cli, log, wavutil]
import ../util/[fun, term]

proc printHelp(opts: seq[OptDef]) =
  let termWidth = max(terminalWidth(), 40)
  let optWidth = min(32, termWidth div 3)
  let helpWidth = termWidth - optWidth - 4

  echo "Usage: <file> [options]\n"
  echo "Options:"

  for opt in opts:
    if opt.hidden:
      continue
    var optStr = "    " & opt.names
    if opt.metavar != "":
      optStr &= " " & opt.metavar

    if optStr.len >= optWidth:
      echo optStr
      let wrapped = wrapText(opt.help, helpWidth, 0)
      for line in wrapped.split("\n"):
        echo " ".repeat(optWidth) & line
    else:
      let padding = optWidth - optStr.len
      let wrapped = wrapText(opt.help, helpWidth, optWidth)
      let helpLines = wrapped.split("\n")
      echo optStr & " ".repeat(padding) & helpLines[0]
      for i in 1 ..< helpLines.len:
        echo helpLines[i]

  echo "\n    -h, --help" & " ".repeat(optWidth - 14) &
    wrapText("Show info about this program then exit", helpWidth, optWidth)
  echo ""
  quit(0)

proc stripCodeFences(s: string): string =
  var lines = s.splitLines()
  if lines.len > 0 and lines[0].strip().startsWith("```"):
    lines.delete(0)
  if lines.len > 0 and lines[^1].strip().startsWith("```"):
    lines.delete(lines.len - 1)
  return lines.join("\n").strip()

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var provider: string = "groq"
  var apiKey: string = ""
  var model: string = ""
  var language: string = "auto"
  var format: string = "srt"
  var formatExplicit = false
  var output: string = "-"

  var expecting: string = ""
  for key in cArgs:
    if expecting != "":
      case expecting
      of "provider": provider = key.toLowerAscii()
      of "apiKey": apiKey = key
      of "model": model = key
      of "language": language = key
      of "format":
        format = key.toLowerAscii()
        formatExplicit = true
      of "output": output = key
      expecting = ""
      continue

    if key in ["-h", "--help"]:
      printHelp(transcribeOptions)
    
    case key
    of "--provider": expecting = "provider"
    of "--api-key": expecting = "apiKey"
    of "--model": expecting = "model"
    of "-l", "--language": expecting = "language"
    of "-f", "--format": expecting = "format"
    of "-o", "--output": expecting = "output"
    else:
      if key.startsWith("-"):
        error "Unknown option: " & key
      elif inputPath == "":
        inputPath = key
      else:
        error "Got too many arguments\nUsage: <file> [options]"

  if expecting != "":
    error &"Option needs an argument after it."

  if inputPath == "":
    error "A media file is needed"

  if provider notin ["groq", "openai", "gemini"]:
    error &"Invalid provider: {provider}. Choices: groq, openai, gemini"

  if format notin ["srt", "text", "json"]:
    error &"Invalid format: {format}. Choices: srt, text, json"

  # Determine default models
  if model == "":
    case provider
    of "groq": model = "whisper-large-v3"
    of "openai": model = "whisper-1"
    of "gemini": model = "gemini-1.5-flash"

  # Find API Key
  if apiKey == "":
    case provider
    of "groq": apiKey = getEnv("GROQ_API_KEY")
    of "openai": apiKey = getEnv("OPENAI_API_KEY")
    of "gemini": apiKey = getEnv("GEMINI_API_KEY")

  if apiKey == "":
    error &"API Key is required for {provider}. Set the {provider.toUpperAscii()}_API_KEY environment variable or pass --api-key <key>"

  if output != "-" and not formatExplicit:
    case output.splitFile.ext.toLowerAscii
    of ".srt": format = "srt"
    of ".json": format = "json"
    of ".txt", ".text": format = "text"
    else: discard

  # Extract audio to a temporary MP3 file
  let tempMp3Path = getTempDir() / ("ae_transcribe_" & $getCurrentProcessId() & ".mp3")
  
  conwrite("Extracting and encoding audio stream...")
  try:
    transcodeAudio(inputPath, tempMp3Path, 0.int32)
  except Exception as e:
    error "Failed to transcode audio: " & e.msg

  if not fileExists(tempMp3Path) or getFileSize(tempMp3Path) == 0:
    error "Failed to extract audio from the media file"

  defer:
    if fileExists(tempMp3Path):
      try:
        removeFile(tempMp3Path)
      except:
        discard

  conwrite(&"Sending audio to {provider.toUpperAscii()} API...")
  
  let audioBytes = readFile(tempMp3Path)
  var transcriptionResult = ""

  let client = newHttpClient()
  defer: client.close()

  if provider in ["groq", "openai"]:
    let endpoint = if provider == "groq":
      "https://api.groq.com/openai/v1/audio/transcriptions"
    else:
      "https://api.openai.com/v1/audio/transcriptions"

    client.headers = newHttpHeaders({
      "Authorization": "Bearer " & apiKey
    })

    let mp = newMultipartData()
    mp.add("model", model)
    mp.add("file", audioBytes, filename = "audio.mp3", contentType = "audio/mpeg")
    mp.add("response_format", format)
    if language != "" and language != "auto":
      mp.add("language", language)

    try:
      let response = client.post(endpoint, multipart = mp)
      if not response.code.is2xx:
        error &"API request failed with code {response.code}: {response.body}"
      transcriptionResult = response.body
    except Exception as e:
      error "HTTP request failed: " & e.msg

  elif provider == "gemini":
    let endpoint = &"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}"
    client.headers = newHttpHeaders({
      "Content-Type": "application/json"
    })

    let base64Audio = encode(audioBytes)
    var prompt = ""
    if format == "srt":
      prompt = "Transcribe the audio in SRT format. Return ONLY the SRT content without markdown formatting block, beginning with 1."
    elif format == "text":
      prompt = "Transcribe the audio in plain text. Return ONLY the transcribed text."
    else: # json
      prompt = "Transcribe the audio and format the output as a JSON transcript with timestamps. Return ONLY the JSON content."

    let reqJson = %*{
      "contents": [{
        "parts": [
          { "text": prompt },
          {
            "inlineData": {
              "mimeType": "audio/mp3",
              "data": base64Audio
            }
          }
        ]
      }]
    }

    try:
      let response = client.post(endpoint, $reqJson)
      if not response.code.is2xx:
        error &"API request failed with code {response.code}: {response.body}"
      
      let respJson = parseJson(response.body)
      if respJson.hasKey("candidates") and respJson["candidates"].len > 0:
        let candidate = respJson["candidates"][0]
        if candidate.hasKey("content") and candidate["content"].hasKey("parts") and candidate["content"]["parts"].len > 0:
          let rawText = candidate["content"]["parts"][0]["text"].getStr()
          transcriptionResult = stripCodeFences(rawText)
        else:
          error "Invalid response structure from Gemini API: candidate content missing"
      else:
        error "Invalid response structure from Gemini API: candidates empty"
    except Exception as e:
      error "HTTP request failed: " & e.msg

  if output == "-":
    echo transcriptionResult
  else:
    try:
      writeFile(output, transcriptionResult)
      conwrite(&"Successfully saved transcription to {output}")
    except Exception as e:
      error &"Failed to write to output file {output}: {e.msg}"
