import std/[os, strutils, strformat, httpclient, json, base64]
import ../[cli, log, wavutil]
import ../util/[fun, term]

proc printHelp(opts: seq[OptDef]) =
  let termWidth = max(terminalWidth(), 40)
  let optWidth = min(36, termWidth div 3)
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

proc buildTranscriptPrompt(language, format: string): string =
  let langHint = if language == "tr" or language == "tur":
    "Ses Türkçe'dir. "
  elif language != "" and language != "auto":
    &"The audio language is '{language}'. "
  else:
    ""

  if format == "srt":
    result = langHint & "Transcribe the audio in SRT subtitle format. Return ONLY the SRT content with no markdown code fences, starting from index 1."
  elif format == "text":
    result = langHint & "Transcribe the audio in plain text. Return ONLY the transcribed text with no extra commentary."
  else: # json
    result = langHint & "Transcribe the audio and output a JSON array of objects with 'start', 'end' (HH:MM:SS format) and 'text' keys. Return ONLY the JSON array."

proc buildTopicPrompt(language, transcript: string): string =
  if language == "tr" or language == "tur":
    result = """Aşağıdaki Türkçe transkripte dayanarak videodaki konu değişim noktalarını belirle.

Her konu için başlangıç zamanı, bitiş zamanı ve Türkçe kısa bir başlık üret.
SADECE aşağıdaki formatta geçerli bir JSON döndür, başka hiçbir şey ekleme:

{
  "topics": [
    { "start": "HH:MM:SS", "end": "HH:MM:SS", "title": "Konu başlığı" }
  ]
}

Transkript:
""" & transcript
  else:
    result = """Based on the following transcript, identify the topic boundaries in the video.

For each topic, produce a start time, end time, and a short title.
Return ONLY valid JSON in the exact format below, nothing else:

{
  "topics": [
    { "start": "HH:MM:SS", "end": "HH:MM:SS", "title": "Topic title" }
  ]
}

Transcript:
""" & transcript

proc callGroqOpenAITranscribe(client: HttpClient, provider, model, apiKey, language, format: string, audioBytes: string): string =
  let endpoint = if provider == "groq":
    "https://api.groq.com/openai/v1/audio/transcriptions"
  else:
    "https://api.openai.com/v1/audio/transcriptions"

  client.headers = newHttpHeaders({"Authorization": "Bearer " & apiKey})

  let mp = newMultipartData()
  mp.add("model", model)
  mp.add("file", audioBytes, filename = "audio.mp3", contentType = "audio/mpeg")
  mp.add("response_format", format)
  if language != "" and language != "auto":
    mp.add("language", language)

  let response = client.post(endpoint, multipart = mp)
  if not response.code.is2xx:
    error &"Transcription API request failed ({response.code}): {response.body}"
  return response.body

proc callGroqOpenAIChat(client: HttpClient, provider, chatModel, apiKey, prompt: string): string =
  let endpoint = if provider == "groq":
    "https://api.groq.com/openai/v1/chat/completions"
  else:
    "https://api.openai.com/v1/chat/completions"

  client.headers = newHttpHeaders({
    "Authorization": "Bearer " & apiKey,
    "Content-Type": "application/json"
  })

  let reqJson = %*{
    "model": chatModel,
    "messages": [
      {"role": "system", "content": "You are an expert transcript analyst. Always respond with valid JSON only."},
      {"role": "user", "content": prompt}
    ],
    "temperature": 0.2
  }

  let response = client.post(endpoint, $reqJson)
  if not response.code.is2xx:
    error &"Chat API request failed ({response.code}): {response.body}"

  let respJson = parseJson(response.body)
  return respJson["choices"][0]["message"]["content"].getStr()

proc callGemini(client: HttpClient, model, apiKey, language, format: string, audioBytes: string, detectTopics: bool): string =
  let endpoint = &"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}"
  client.headers = newHttpHeaders({"Content-Type": "application/json"})

  let base64Audio = encode(audioBytes)

  var prompt: string
  if detectTopics:
    let langHint = if language == "tr" or language == "tur": "Ses Türkçe'dir. " else: ""
    if language == "tr" or language == "tur":
      prompt = langHint & """Bu Türkçe sesi önce transkribe et, ardından içerikteki konu değişim noktalarını tespit et.
SADECE aşağıdaki JSON formatında yanıt ver, başka hiçbir şey ekleme:

{
  "topics": [
    { "start": "HH:MM:SS", "end": "HH:MM:SS", "title": "Konu başlığı" }
  ]
}"""
    else:
      prompt = """First transcribe this audio, then detect topic boundaries in the content.
Return ONLY valid JSON in this format, nothing else:

{
  "topics": [
    { "start": "HH:MM:SS", "end": "HH:MM:SS", "title": "Topic title" }
  ]
}"""
  else:
    prompt = buildTranscriptPrompt(language, format)

  let reqJson = %*{
    "contents": [{
      "parts": [
        {"text": prompt},
        {"inlineData": {"mimeType": "audio/mp3", "data": base64Audio}}
      ]
    }],
    "generationConfig": {"temperature": 0.1}
  }

  let response = client.post(endpoint, $reqJson)
  if not response.code.is2xx:
    error &"Gemini API request failed ({response.code}): {response.body}"

  let respJson = parseJson(response.body)
  if respJson.hasKey("candidates") and respJson["candidates"].len > 0:
    let candidate = respJson["candidates"][0]
    if candidate.hasKey("content") and
       candidate["content"].hasKey("parts") and
       candidate["content"]["parts"].len > 0:
      return stripCodeFences(candidate["content"]["parts"][0]["text"].getStr())
  error "Invalid response structure from Gemini API"

proc main*(cArgs: seq[string]) =
  var inputPath   = ""
  var provider    = "groq"
  var apiKey      = ""
  var model       = ""
  var chatModel   = ""
  var language    = "auto"
  var format      = "srt"
  var formatExplicit = false
  var output      = "-"
  var detectTopics = false

  var expecting = ""
  for key in cArgs:
    if expecting != "":
      case expecting
      of "provider":   provider   = key.toLowerAscii()
      of "apiKey":     apiKey     = key
      of "model":      model      = key
      of "chatModel":  chatModel  = key
      of "language":   language   = key
      of "format":
        format = key.toLowerAscii()
        formatExplicit = true
      of "output":     output     = key
      expecting = ""
      continue

    if key in ["-h", "--help"]:
      printHelp(transcribeOptions)

    case key
    of "--provider":       expecting = "provider"
    of "--api-key":        expecting = "apiKey"
    of "--model":          expecting = "model"
    of "--chat-model":     expecting = "chatModel"
    of "-l", "--language": expecting = "language"
    of "-f", "--format":   expecting = "format"
    of "-o", "--output":   expecting = "output"
    of "--detect-topics":  detectTopics = true
    else:
      if key.startsWith("-"):
        error "Unknown option: " & key
      elif inputPath == "":
        inputPath = key
      else:
        error "Got too many arguments\nUsage: <file> [options]"

  if expecting != "":
    error "Option needs an argument."

  if inputPath == "":
    error "A media file is needed"

  if provider notin ["groq", "openai", "gemini"]:
    error &"Invalid provider: {provider}. Choices: groq, openai, gemini"

  # When detecting topics with Gemini, output is always JSON
  if detectTopics and not formatExplicit:
    format = "json"
  elif format notin ["srt", "text", "json"]:
    error &"Invalid format: {format}. Choices: srt, text, json"

  # Default models
  if model == "":
    case provider
    of "groq":   model = "whisper-large-v3"
    of "openai": model = "whisper-1"
    of "gemini": model = "gemini-1.5-flash"

  # Default chat models for topic detection (Groq/OpenAI)
  if chatModel == "" and detectTopics:
    case provider
    of "groq":   chatModel = "llama-3.3-70b-versatile"
    of "openai": chatModel = "gpt-4o-mini"
    else: discard

  # Find API Key from environment if not provided
  if apiKey == "":
    case provider
    of "groq":   apiKey = getEnv("GROQ_API_KEY")
    of "openai": apiKey = getEnv("OPENAI_API_KEY")
    of "gemini": apiKey = getEnv("GEMINI_API_KEY")

  if apiKey == "":
    error &"API Key required for {provider}. Set {provider.toUpperAscii()}_API_KEY or pass --api-key"

  # Auto-detect output format from file extension
  if output != "-" and not formatExplicit:
    case output.splitFile.ext.toLowerAscii
    of ".srt":          format = "srt"
    of ".json":         format = "json"
    of ".txt", ".text": format = "text"
    else: discard

  # Extract audio to a temporary MP3 file
  let tempMp3Path = getTempDir() / ("ae_transcribe_" & $getCurrentProcessId() & ".mp3")

  conwrite("Extracting audio stream...")
  try:
    transcodeAudio(inputPath, tempMp3Path, 0.int32)
  except Exception as e:
    error "Failed to transcode audio: " & e.msg

  if not fileExists(tempMp3Path) or getFileSize(tempMp3Path) == 0:
    error "Failed to extract audio from the media file"

  defer:
    if fileExists(tempMp3Path):
      try: removeFile(tempMp3Path) except: discard

  let audioBytes = readFile(tempMp3Path)
  var result = ""

  let client = newHttpClient()
  client.timeout = 120_000 # 2 minutes for large files
  defer: client.close()

  if provider == "gemini":
    let action = if detectTopics: "transcribing & detecting topics" else: "transcribing"
    conwrite(&"Sending audio to Gemini ({action})...")
    result = callGemini(client, model, apiKey, language, format, audioBytes, detectTopics)

  elif provider in ["groq", "openai"]:
    if detectTopics:
      # Step 1: Transcribe with Whisper to get plain text
      conwrite(&"Sending audio to {provider.toUpperAscii()} Whisper for transcription...")
      let transcript = callGroqOpenAITranscribe(client, provider, model, apiKey, language, "text", audioBytes)

      # Step 2: Send transcript to chat model for topic analysis
      conwrite(&"Analyzing topics with {chatModel}...")
      let topicPrompt = buildTopicPrompt(language, transcript)
      let rawResult = callGroqOpenAIChat(client, provider, chatModel, apiKey, topicPrompt)
      result = stripCodeFences(rawResult)
    else:
      conwrite(&"Sending audio to {provider.toUpperAscii()} Whisper...")
      result = callGroqOpenAITranscribe(client, provider, model, apiKey, language, format, audioBytes)

  if output == "-":
    echo result
  else:
    try:
      writeFile(output, result)
      let action = if detectTopics: "Topic JSON" else: "Transcription"
      conwrite(&"{action} saved to {output}")
    except Exception as e:
      error &"Failed to write output file {output}: {e.msg}"
