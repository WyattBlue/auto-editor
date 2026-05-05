import std/strformat

import ffmpeg
import log

type Graph* = ref object
  # nodes[0] is the buffer/abuffer source; nodes[^1] is the buffer/abuffer sink.
  nodes: seq[ptr AVFilterContext]
  graph: ptr AVFilterGraph
  recvFrame: ptr AVFrame
  configured: bool = false

proc newGraph*(): Graph =
  result = Graph()
  result.graph = avfilter_graph_alloc()
  if result.graph == nil:
    error "Could not allocate filter graph"

proc cleanup*(graph: Graph) =
  if graph == nil:
    return
  if graph.recvFrame != nil:
    av_frame_free(addr graph.recvFrame)
  if graph.graph != nil:
    avfilter_graph_free(addr graph.graph)
    graph.nodes.setLen(0)

proc add*(graph: Graph, name: string, filterArgs: string = ""): ptr AVFilterContext =
  if graph.configured:
    error "Cannot add filters after graph is configured"

  var filterCtx: ptr AVFilterContext = nil
  let args = if filterArgs.len > 0: filterArgs.cstring else: nil
  let filterName = &"filter_{graph.nodes.len}"

  let filter = avfilter_get_by_name(name.cstring)
  if filter == nil:
    error &"Filter '{name}' not found"

  let ret = avfilter_graph_create_filter(
    addr filterCtx, filter, filterName.cstring, args, nil, graph.graph
  )
  if ret < 0:
    error &"Cannot create filter '{name}' with args '{filterArgs}': {ret}"
  if filterCtx == nil:
    error &"Filter context is nil for '{name}'"

  graph.nodes.add(filterCtx)
  return filterCtx

proc linkNodes*(graph: Graph, nodes: seq[ptr AVFilterContext]): Graph =
  if graph.configured:
    error "Cannot link nodes after graph is configured"
  if nodes.len < 2:
    error "Need at least 2 nodes to link"

  # Link nodes sequentially: nodes[0] -> nodes[1] -> nodes[2] -> ...
  for i in 0 ..< (nodes.len - 1):
    let ret = avfilter_link(nodes[i], 0, nodes[i + 1], 0)
    if ret < 0:
      error &"Could not link node {i} to node {i + 1}: {ret}"

  return graph

proc configure*(graph: Graph) =
  if graph.configured:
    return
  if graph.nodes.len < 2:
    error "Graph needs at least a source and a sink before configure"

  let ret = avfilter_graph_config(graph.graph, nil)
  if ret < 0:
    error &"Could not configure filter graph: {ret}"

  graph.configured = true

proc push*(graph: Graph, frame: ptr AVFrame) =
  if not graph.configured:
    error "Graph must be configured before pushing frames"

  if frame == nil:
    error "Frame shouldn't be nil here"
  let ret = av_buffersrc_write_frame(graph.nodes[0], frame)
  if ret < 0:
    error &"Error pushing frame to graph: {ret}"

proc pull*(graph: Graph): ptr AVFrame =
  # Caller responsible for freeing frames
  if not graph.configured:
    error "Graph must be configured before pulling frames"
  var frame = av_frame_alloc()
  if frame == nil:
    error "Could not allocate frame for pulling"

  let ret = av_buffersink_get_frame(graph.nodes[^1], frame)
  if ret < 0:
    av_frame_free(addr frame)
    error &"Error pulling frame from graph: {ret}"

  return frame

proc pullTransient*(graph: Graph): ptr AVFrame =
  # Returns a Graph-owned frame valid until the next pullTransient/cleanup.
  # Caller must NOT free; data lifetime is tied to the Graph.
  # Returns nil on EAGAIN/EOF.
  if not graph.configured:
    error "Graph must be configured before pulling frames"
  if graph.recvFrame == nil:
    graph.recvFrame = av_frame_alloc()
    if graph.recvFrame == nil:
      error "Could not allocate frame for pulling"
  else:
    av_frame_unref(graph.recvFrame)

  let ret = av_buffersink_get_frame(graph.nodes[^1], graph.recvFrame)
  if ret < 0:
    return nil
  return graph.recvFrame

proc flush*(graph: Graph) =
  # Flush the filter graph by sending a nil frame
  if not graph.configured:
    error "Graph must be configured before flushing"
  let ret = av_buffersrc_write_frame(graph.nodes[0], nil)
  if ret < 0:
    error &"Error flushing graph: {ret}"
