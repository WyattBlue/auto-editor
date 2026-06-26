## Auto-Editor GUI Module
## Web-based interface for video editing

import std/[os, strutils, asynchttpserver, asyncdispatch]

type
  App* = object
    title*: string
    port*: int
    currentLang*: string

proc newApp*(): App =
  App(
    title: "Auto-Editor",
    port: 8080,
    currentLang: "tr"
  )

proc startServer*(app: App) =
  ## Start the GUI server
  echo "=========================================="
  echo "  Auto-Editor GUI v2.6.2-dev"
  echo "=========================================="
  echo ""
  echo "  Starting web server on port " & $app.port & "..."
  echo ""
  echo "  Open your browser and go to:"
  echo "  http://localhost:" & $app.port
  echo ""
  echo "  Press Ctrl+C to stop"
  echo "=========================================="
  
  let webDir = getCurrentDir() / "web"
  
  if not dirExists(webDir):
    echo "Error: web/ directory not found"
    echo "Please run from the project root directory"
    quit(1)
  
  echo "Serving files from: " & webDir
  
  var server = newAsyncHttpServer()
  
  proc handler(req: Request) {.async.} =
    let path = req.url.path
    var filePath = ""
    
    case path
    of "/":
      filePath = webDir / "index.html"
    else:
      filePath = webDir / path
    
    if fileExists(filePath):
      let content = readFile(filePath)
      var contentType = "text/plain"
      
      if filePath.endsWith(".html"):
        contentType = "text/html"
      elif filePath.endsWith(".css"):
        contentType = "text/css"
      elif filePath.endsWith(".js"):
        contentType = "application/javascript"
      elif filePath.endsWith(".json"):
        contentType = "application/json"
      
      let headers = newHttpHeaders([("Content-Type", contentType)])
      await req.respond(Http200, content, headers)
    else:
      await req.respond(Http404, "File not found: " & path)
  
  waitFor server.serve(Port(app.port), handler)

proc main*() =
  let app = newApp()
  app.startServer()

when isMainModule:
  main()
