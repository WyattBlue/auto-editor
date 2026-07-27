/*
 * Async WebCodecs encoder bridge for FFmpeg's synchronous AVCodec API.
 */

addToLibrary({
  $AEWebEncoders: {
    nextHandle: 1,
    handles: new Map(),

    ctrl: function(entry) {
      return new Int32Array(wasmMemory.buffer, entry.ctrlPtr, 10);
    },

    complete: function(entry, status) {
      Atomics.store(AEWebEncoders.ctrl(entry), 0, status);
    },

    i64: function(view, index, value) {
      const number = Number.isFinite(value) ? Math.trunc(value) : 0;
      view[index] = number | 0;
      view[index + 1] = Math.floor(number / 4294967296) | 0;
    },

    fail: function(entry, error) {
      entry.error = error;
      if (entry.outputWaiter) {
        entry.outputWaiter();
        entry.outputWaiter = null;
      }
      console.error('auto-editor WebCodecs encoder:', error);
      AEWebEncoders.complete(entry, -1);
    },

    createEncoder: function(entry) {
      if (entry.encoder) {
        try {
          entry.encoder.close();
        } catch {
          // Already closed.
        }
      }
      entry.outputs = [];
      entry.outputWaiter = null;
      entry.error = null;
      const init = {
        output: (chunk, metadata) => {
          entry.outputs.push({ chunk, metadata });
          if (entry.outputWaiter) {
            entry.outputWaiter();
            entry.outputWaiter = null;
          }
        },
        error: error => AEWebEncoders.fail(entry, error),
      };
      entry.encoder = entry.kind === 2
        ? new AudioEncoder(init)
        : new VideoEncoder(init);
      entry.encoder.configure(entry.config);
    },

    videoCodec: function(kind, width, height, profile, level) {
      const large = width * height > 1920 * 1080;
      if (kind === 1) {
        const h264Profile = profile >= 0 ? profile & 0xff : 100;
        let prefix;
        if (h264Profile === 66) {
          prefix = '42e0';
        } else if (h264Profile === 77) {
          prefix = '4d00';
        } else if (h264Profile === 100) {
          prefix = '6400';
        } else {
          return null;
        }
        const h264Level = level > 0 ? level : (large ? 51 : 40);
        return `avc1.${prefix}${h264Level.toString(16).padStart(2, '0')}`;
      }
      if (kind === 3) {
        const av1Profile = profile >= 0 && profile <= 2 ? profile : 0;
        const av1Level = level >= 0 && level <= 31 ? level : (large ? 12 : 8);
        const depth = av1Profile === 2 ? 10 : 8;
        return `av01.${av1Profile}.${String(av1Level).padStart(2, '0')}M.${String(depth).padStart(2, '0')}`;
      }
      if (kind === 4) {
        const vp9Profile = profile >= 0 && profile <= 3 ? profile : 0;
        const vp9Level = level >= 10 && level <= 62 ? level : (large ? 51 : 40);
        const depth = vp9Profile >= 2 ? 10 : 8;
        return `vp09.${String(vp9Profile).padStart(2, '0')}.${String(vp9Level).padStart(2, '0')}.${String(depth).padStart(2, '0')}`;
      }
      if (kind === 6) {
        return 'vp8';
      }
      const hevcProfile = profile > 0 ? profile : 1;
      const hevcLevel = level > 0 ? level : (large ? 153 : 120);
      const compatibility = hevcProfile === 1
        ? 6
        : (hevcProfile === 2 ? 4 : 0);
      return `hvc1.${hevcProfile}.${compatibility}.L${hevcLevel}.B0`;
    },

    description: function(metadata) {
      const description = metadata?.decoderConfig?.description;
      return description
        ? new Uint8Array(
            description.buffer ?? description,
            description.byteOffset ?? 0,
            description.byteLength,
          )
        : null;
    },

    prime: async function(entry, outPtr, outCapacity) {
      if (entry.kind === 2) {
        const frames = 1024;
        const audio = new AudioData({
          format: 'f32-planar',
          sampleRate: entry.config.sampleRate,
          numberOfFrames: frames,
          numberOfChannels: entry.config.numberOfChannels,
          timestamp: 0,
          data: new Uint8Array(
            frames * entry.config.numberOfChannels * 4,
          ),
        });
        entry.encoder.encode(audio);
        audio.close();
      } else {
        const width = entry.config.width;
        const height = entry.config.height;
        const chromaWidth = Math.ceil(width / 2);
        const chromaHeight = Math.ceil(height / 2);
        const video = new VideoFrame(
          new Uint8Array(width * height + 2 * chromaWidth * chromaHeight),
          {
            format: 'I420',
            codedWidth: width,
            codedHeight: height,
            timestamp: 0,
            duration: Math.round(1000000 / entry.config.framerate),
          },
        );
        entry.encoder.encode(video, { keyFrame: true });
        video.close();
      }
      await entry.encoder.flush();
      await AEWebEncoders.waitForOutput(entry);
      const first = entry.outputs.shift();
      const extra = AEWebEncoders.description(first?.metadata);
      const extraSize = extra?.byteLength ?? 0;
      const needsExtra = entry.kind === 1
        || entry.kind === 2
        || entry.kind === 5;
      if ((needsExtra && !extraSize) || extraSize > outCapacity) {
        throw new Error('WebCodecs encoder did not provide decoder configuration');
      }
      if (extraSize) {
        HEAPU8.set(extra, outPtr);
      }
      const view = AEWebEncoders.ctrl(entry);
      view[7] = 0;
      view[8] = extraSize;
      AEWebEncoders.createEncoder(entry);
    },

    waitForOutput: async function(entry) {
      if (entry.outputs.length || entry.error) return;
      await new Promise((resolve, reject) => {
        const timer = setTimeout(
          () => reject(new Error('WebCodecs encode timed out')),
          30000,
        );
        entry.outputWaiter = () => {
          clearTimeout(timer);
          resolve();
        };
      });
    },

    emitOne: function(entry, outPtr, outCapacity, eofStatus) {
      const item = entry.outputs[0];
      if (!item) {
        AEWebEncoders.complete(entry, eofStatus);
        return;
      }

      const extra = AEWebEncoders.description(item.metadata);
      const packetSize = item.chunk.byteLength;
      const extraSize = extra?.byteLength ?? 0;
      const view = AEWebEncoders.ctrl(entry);
      if (packetSize + extraSize > outCapacity) {
        view[1] = packetSize;
        view[7] = packetSize;
        view[8] = extraSize;
        AEWebEncoders.complete(entry, 4);
        return;
      }

      entry.outputs.shift();
      item.chunk.copyTo(
        new Uint8Array(wasmMemory.buffer, outPtr, packetSize),
      );
      if (extraSize) {
        HEAPU8.set(extra, outPtr + packetSize);
      }

      view[1] = packetSize;
      view[2] = item.chunk.type === 'key' ? 1 : 0;
      AEWebEncoders.i64(view, 3, item.chunk.timestamp);
      AEWebEncoders.i64(view, 5, item.chunk.duration ?? 0);
      view[7] = packetSize;
      view[8] = extraSize;
      view[9] = entry.outputs.length ? 1 : 0;
      AEWebEncoders.complete(entry, 1);
    },
  },

  ae_we_init__deps: ['$AEWebEncoders', '$Asyncify'],
  ae_we_init: function(
    kind,
    ctrlPtr,
    width,
    height,
    sampleRate,
    channels,
    frameRate,
    bitRate,
    profile,
    level,
    outPtr,
    outCapacity,
  ) {
    return Asyncify.handleAsync(async () => {
      if ((kind !== 2 && typeof VideoEncoder === 'undefined')
          || (kind === 2 && typeof AudioEncoder === 'undefined')) {
        return 0;
      }

      let config;
      if (kind === 2) {
        config = {
            codec: 'mp4a.40.2',
            sampleRate,
            numberOfChannels: channels,
            bitrate: bitRate > 0 ? bitRate : 128000,
          };
      } else {
        const codec = AEWebEncoders.videoCodec(
          kind,
          width,
          height,
          profile,
          level,
        );
        if (!codec) return 0;
        config = {
            codec,
            width,
            height,
            framerate: frameRate > 0 ? frameRate : 30,
            bitrate: bitRate > 0
              ? bitRate
              : Math.max(500000, width * height * frameRate * 0.07),
            latencyMode: 'realtime',
          };
        if (kind === 1 || kind === 5) {
          config.hardwareAcceleration = 'prefer-hardware';
        }
        if (kind === 1) {
          config.avc = { format: 'avc' };
        } else if (kind === 5) {
          config.hevc = { format: 'hevc' };
        }
      }
      const support = kind === 2
        ? await AudioEncoder.isConfigSupported(config)
        : await VideoEncoder.isConfigSupported(config);
      if (!support.supported) return 0;

      const handle = AEWebEncoders.nextHandle++;
      const entry = {
        kind,
        ctrlPtr,
        config: support.config,
        encoder: null,
        outputs: [],
        outputWaiter: null,
        error: null,
      };
      try {
        AEWebEncoders.createEncoder(entry);
        await AEWebEncoders.prime(entry, outPtr, outCapacity);
      } catch (error) {
        if (entry.encoder) {
          try {
            entry.encoder.close();
          } catch {
            // Already closed.
          }
        }
        console.error('auto-editor WebCodecs encoder configuration:', error);
        return 0;
      }
      AEWebEncoders.handles.set(handle, entry);
      AEWebEncoders.complete(entry, 1);
      return handle;
    });
  },

  ae_we_encode__deps: ['$AEWebEncoders', '$Asyncify'],
  ae_we_encode: function(
    handle,
    inputPtr,
    inputSize,
    width,
    height,
    samples,
    timestamp,
    duration,
    key,
    outPtr,
    outCapacity,
  ) {
    return Asyncify.handleAsync(async () => {
      const entry = AEWebEncoders.handles.get(handle);
      if (!entry) return -1;
      AEWebEncoders.complete(entry, 0);
      try {
        const data = HEAPU8.slice(inputPtr, inputPtr + inputSize);
        if (entry.kind === 2) {
          const audio = new AudioData({
            format: 'f32-planar',
            sampleRate: entry.config.sampleRate,
            numberOfFrames: samples,
            numberOfChannels: entry.config.numberOfChannels,
            timestamp,
            data,
          });
          entry.encoder.encode(audio);
          audio.close();
        } else {
          const video = new VideoFrame(data, {
            format: 'I420',
            codedWidth: width,
            codedHeight: height,
            timestamp,
            duration: duration || undefined,
          });
          entry.encoder.encode(video, { keyFrame: !!key });
          video.close();
        }
        await AEWebEncoders.waitForOutput(entry);
        if (entry.error) return -1;
        AEWebEncoders.emitOne(entry, outPtr, outCapacity, 2);
        return 0;
      } catch (error) {
        AEWebEncoders.fail(entry, error);
        return -1;
      }
    });
  },

  ae_we_command__deps: ['$AEWebEncoders', '$Asyncify'],
  ae_we_command: function(handle, command, outPtr, outCapacity) {
    return Asyncify.handleAsync(async () => {
      const entry = AEWebEncoders.handles.get(handle);
      if (!entry) return -1;
      AEWebEncoders.complete(entry, 0);
      try {
        if (command === 2) {
          await entry.encoder.flush();
        }
        AEWebEncoders.emitOne(
          entry,
          outPtr,
          outCapacity,
          command === 2 ? 3 : 2,
        );
        return 0;
      } catch (error) {
        AEWebEncoders.fail(entry, error);
        return -1;
      }
    });
  },

  ae_we_close__deps: ['$AEWebEncoders'],
  ae_we_close: function(handle) {
    const entry = AEWebEncoders.handles.get(handle);
    if (!entry) return;
    if (entry.encoder) {
      try {
        entry.encoder.close();
      } catch {
        // Already closed.
      }
    }
    AEWebEncoders.handles.delete(handle);
  },
});
