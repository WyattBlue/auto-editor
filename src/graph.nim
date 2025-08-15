import std/strformat

import ffmpeg
import log

type
  Graph* = ref object
    graph: ptr AVFilterGraph
    nodes: seq[ptr AVFilterContext]
    configured: bool

  BlockingIOError* = object of CatchableError
  EOFError* = object of CatchableError

proc newGraph*(): Graph =
  result = Graph()
  result.nodes = @[]
  result.configured = false
  result.graph = avfilter_graph_alloc()
  if result.graph == nil:
    error "Could not allocate filter graph"

proc cleanup*(graph: Graph) =
  if graph != nil and graph.graph != nil:
    avfilter_graph_free(addr graph.graph)
    graph.graph = nil

proc add*(graph: Graph, name: string, filterArgs: string = ""): ptr AVFilterContext =
  if graph.configured:
    error "Cannot add filters after graph is configured"

  var filterCtx: ptr AVFilterContext = nil
  let args = if filterArgs.len > 0: filterArgs.cstring else: nil
  let filterName = &"filter_{graph.nodes.len}"

  let filter = avfilter_get_by_name(name.cstring)
  if filter == nil:
    error fmt"Filter '{name}' not found"

  let ret = avfilter_graph_create_filter(
    addr filterCtx,
    filter,
    filterName.cstring,
    args,
    nil,
    graph.graph
  )

  if ret < 0:
    error fmt"Cannot create filter '{name}' with args '{filterArgs}': {ret}"

  if filterCtx == nil:
    error fmt"Filter context is nil for '{name}'"

  graph.nodes.add(filterCtx)

  return filterCtx

proc linkNodes*(graph: Graph, nodes: seq[ptr AVFilterContext]): Graph =
  if graph.configured:
    error "Cannot link nodes after graph is configured"

  if nodes.len < 2:
    error "Need at least 2 nodes to link"

  # Link nodes sequentially: nodes[0] -> nodes[1] -> nodes[2] -> ...
  for i in 0..<(nodes.len - 1):
    var ret = avfilter_link(nodes[i], 0, nodes[i + 1], 0)
    if ret < 0:
      error fmt"Could not link node {i} to node {i + 1}: {ret}"

  return graph

proc configure*(graph: Graph) =
  if graph.configured:
    return

  let ret = avfilter_graph_config(graph.graph, nil)
  if ret < 0:
    error fmt"Could not configure filter graph: {ret}"

  graph.configured = true

proc findBufferSource(graph: Graph): ptr AVFilterContext =
  if not graph.configured:
    error "Graph must be configured before finding buffer source"

  if graph.graph == nil:
    error "Filter graph is nil"

  # Look for buffer filter in the graph
  for i in 0 ..< graph.graph.nb_filters:
    let ctx = graph.graph.filters[i]
    if ctx != nil and ctx.filter != nil:
      let filterName = $ctx.filter.name
      if filterName == "buffer":
        return ctx

  error "No buffer source found in graph"

proc findBufferSink(graph: Graph): ptr AVFilterContext =
  if not graph.configured:
    error "Graph must be configured before finding buffer sink"

  if graph.graph == nil:
    error "Filter graph is nil"

  # Safety check for reasonable filter count
  if graph.graph.nb_filters < 0 or graph.graph.nb_filters > 1000:
    error fmt"Invalid filter count: {graph.graph.nb_filters}"

  # Look for buffersink filter in the graph
  for i in 0 ..< graph.graph.nb_filters:
    let ctx = graph.graph.filters[i]
    if ctx != nil and ctx.filter != nil:
      let filterName = $ctx.filter.name
      if filterName == "buffersink":
        return ctx

  error "No buffer sink found in graph"

proc push*(graph: Graph, frame: ptr AVFrame) =
  if not graph.configured:
    error "Graph must be configured before pushing frames"

  if frame == nil:
    error "Frame shouldn't be nil here"

  let bufferSource = graph.findBufferSource()

  let ret = av_buffersrc_write_frame(bufferSource, frame)
  if ret < 0:
    error fmt"Error pushing frame to graph: {ret}"

proc pull*(graph: Graph): ptr AVFrame =
  # Caller responsible for freeing frames
  if not graph.configured:
    error "Graph must be configured before pulling frames"

  let bufferSink = graph.findBufferSink()

  var frame = av_frame_alloc()
  if frame == nil:
    error "Could not allocate frame for pulling"

  let ret = av_buffersink_get_frame(bufferSink, frame)
  if ret < 0:
    av_frame_free(addr frame)
    error &"Error pulling frame from graph: {ret}"

  return frame
