# 31.7.2

## Major
 -

## Features
 -

## Performance
 -

## Fixes
 - A packet that fails to decode no longer aborts the whole analysis. The bad packet is skipped with a warning and the rest of the file is still read, so one damaged frame in a long recording can't throw away the entire result.
 - Analysis now drains the decoder at the end of a stream.
 - An analysis taken over skipped packets is no longer written to the cache, so holes can't be served back as real silence on later runs.
 - `levels` exits non-zero when it had to skip packets. The values it did read are still printed.
 - All progress and status output now goes to stderr: the progress bar, the `Finished.` line, and the progress-line clear written before a warning or error. stdout carries only data.

# Misc.
 -
