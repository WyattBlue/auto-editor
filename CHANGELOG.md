# 31.3.3

## Major
 -

## Features
 -

## Performance
 - Copy complete H.264 or VP9 GOPs without re-encoding when rendering compatible
   H.264 MP4/MOV/Matroska or VP9 WebM timelines; only GOP fragments touching edit
   points are re-encoded.
   Reuse render resources across cuts and fall back when copying would cost more than
   a full render.

## Fixes
 -
