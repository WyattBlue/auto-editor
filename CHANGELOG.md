# 31.3.3

## Major
 -

## Features
 -

## Performance
 - Copy complete H.264 GOPs without re-encoding when rendering compatible MP4/MOV
   timelines; only GOP fragments touching edit points are re-encoded. Reuse render
   resources across cuts and fall back when copying would cost more than a full render.

## Fixes
 -
