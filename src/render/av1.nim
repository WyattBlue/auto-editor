import ../[av, ffmpeg, log, timeline]
import smart
import vp9

proc partialLosslessAv1Plan*(output: OutputContainer, tl: v3,
    args: mainArgs): seq[SmartSpan] =
  output.partialLosslessPlan(tl, args, ID_AV1)

proc makePartialLosslessAv1*(output: var OutputContainer, tl: v3,
    args: mainArgs, spans: seq[SmartSpan]):
    (ptr AVStream, iterator(): (ptr AVPacket, int64)) =
  output.makePartialLossless(tl, args, spans, ID_AV1)
