/*
 * Async WebCodecs bridge for FFmpeg's synchronous AVCodec API.
 *
 * JSPI suspends the FFmpeg pthread while WebCodecs runs, then restores the
 * wasm stack before returning to C. This lets decoder callbacks run without
 * changing FFmpeg's synchronous AVCodec contract.
 */

addToLibrary({
  $AEWebCodecs: {
    nextHandle: 1,
    handles: new Map(),

    ctrl: function(entry) {
      return new Int32Array(wasmMemory.buffer, entry.ctrlPtr, 16);
    },

    complete: function(entry, status) {
      Atomics.store(AEWebCodecs.ctrl(entry), 0, status);
    },

    timestamp: function(view, timestamp) {
      const value = Number.isFinite(timestamp) ? Math.trunc(timestamp) : 0;
      view[11] = value | 0;
      view[12] = Math.floor(value / 4294967296) | 0;
    },

    emitVideo: async function(entry, frame, outPtr, outCapacity) {
      // copyTo() copies visibleRect, not the coded rect. Sizing the layout from
      // codedWidth/codedHeight would leave the padding rows of coded-larger
      // streams (Chrome decodes 1080p H.264 as 1088 tall) never written.
      const rect = frame.visibleRect
        ?? { x: 0, y: 0, width: frame.codedWidth, height: frame.codedHeight };
      const width = rect.width;
      const height = rect.height;
      const chromaWidth = Math.ceil(width / 2);
      const chromaHeight = Math.ceil(height / 2);
      let format = frame.format;
      let formatCode;
      let layout;
      let size;

      if (format === 'I420') {
        formatCode = 0;
        layout = [
          { offset: 0, stride: width },
          { offset: width * height, stride: chromaWidth },
          {
            offset: width * height + chromaWidth * chromaHeight,
            stride: chromaWidth,
          },
        ];
        size = width * height + 2 * chromaWidth * chromaHeight;
      } else if (format === 'NV12') {
        formatCode = 1;
        layout = [
          { offset: 0, stride: width },
          { offset: width * height, stride: 2 * chromaWidth },
        ];
        size = width * height + 2 * chromaWidth * chromaHeight;
      } else {
        format = 'RGBA';
        formatCode = 2;
        layout = [{ offset: 0, stride: width * 4 }];
        size = width * height * 4;
      }
      if (size > outCapacity) {
        throw new RangeError('decoded video frame exceeds staging buffer');
      }

      const copyOptions = format === 'RGBA'
        ? { format, layout, rect }
        : { layout, rect };
      await frame.copyTo(
        new Uint8Array(wasmMemory.buffer, outPtr, size),
        copyOptions,
      );
      const view = AEWebCodecs.ctrl(entry);
      view[1] = formatCode;
      view[2] = width;
      view[3] = height;
      view[4] = layout.length;
      view[5] = layout[0].offset;
      view[6] = layout[0].stride;
      view[7] = layout[1]?.offset ?? 0;
      view[8] = layout[1]?.stride ?? 0;
      view[9] = layout[2]?.offset ?? 0;
      view[10] = layout[2]?.stride ?? 0;
      view[13] = size;
      AEWebCodecs.timestamp(view, frame.timestamp);
    },

    emitAudio: function(entry, sample, outPtr, outCapacity) {
      const channels = sample.numberOfChannels;
      const frames = sample.numberOfFrames;
      const planeSize = frames * 4;
      const size = planeSize * channels;
      if (size > outCapacity) {
        throw new RangeError('decoded audio frame exceeds staging buffer');
      }

      for (let plane = 0; plane < channels; plane++) {
        sample.copyTo(
          new Float32Array(
            wasmMemory.buffer,
            outPtr + plane * planeSize,
            frames,
          ),
          { planeIndex: plane, format: 'f32-planar' },
        );
      }
      const view = AEWebCodecs.ctrl(entry);
      view[1] = 0;
      view[2] = frames;
      view[3] = 0;
      view[4] = channels;
      view[5] = 0;
      view[6] = planeSize;
      view[13] = size;
      view[14] = channels;
      view[15] = sample.sampleRate;
      AEWebCodecs.timestamp(view, sample.timestamp);
    },

    emitOne: async function(entry, outPtr, outCapacity) {
      const sample = entry.outputs.shift();
      if (!sample) {
        AEWebCodecs.complete(entry, 2);
        return;
      }
      try {
        if (entry.kind !== 2) {
          await AEWebCodecs.emitVideo(entry, sample, outPtr, outCapacity);
        } else {
          AEWebCodecs.emitAudio(entry, sample, outPtr, outCapacity);
        }
        AEWebCodecs.complete(entry, 1);
      } finally {
        sample.close();
      }
    },

    fail: function(entry, error) {
      entry.error = error;
      if (entry.outputWaiter) {
        entry.outputWaiter();
        entry.outputWaiter = null;
      }
      console.error('auto-editor WebCodecs decoder:', error);
      AEWebCodecs.complete(entry, -1);
    },

    createDecoder: function(entry) {
      if (entry.decoder) {
        try {
          entry.decoder.close();
        } catch {
          // Already closed.
        }
      }
      entry.outputs.splice(0).forEach(sample => sample.close());
      entry.decodeCount = 0;
      entry.outputCount = 0;
      entry.outputWaiter = null;
      entry.error = null;
      const init = {
        output: sample => {
          entry.outputs.push(sample);
          if (entry.outputWaiter) {
            entry.outputWaiter();
            entry.outputWaiter = null;
          }
          entry.outputCount++;
        },
        error: error => AEWebCodecs.fail(entry, error),
      };
      entry.decoder = entry.kind === 2
        ? new AudioDecoder(init)
        : new VideoDecoder(init);
      entry.decoder.configure(entry.config);
    },

    videoCodec: function(
      kind,
      extraPtr,
      extraSize,
      width,
      height,
      profile,
      level,
      bitDepth,
    ) {
      if (kind === 1) {
        if (extraSize >= 4 && HEAPU8[extraPtr] === 1) {
          return 'avc1.'
            + HEAPU8[extraPtr + 1].toString(16).padStart(2, '0')
            + HEAPU8[extraPtr + 2].toString(16).padStart(2, '0')
            + HEAPU8[extraPtr + 3].toString(16).padStart(2, '0');
        }
        return 'avc1.640028';
      }

      const fallbackLevel = width * height > 1920 * 1080 ? 51 : 40;
      if (kind === 3) {
        let av1Profile = profile;
        let av1Level = level;
        let tier = 'M';
        let depth = bitDepth;
        // ISO BMFF stores the exact AV1 profile, level, tier, and bit depth
        // in the four-byte AV1CodecConfigurationRecord.
        if (extraSize >= 4 && HEAPU8[extraPtr] === 0x81) {
          av1Profile = HEAPU8[extraPtr + 1] >> 5;
          av1Level = HEAPU8[extraPtr + 1] & 0x1f;
          tier = HEAPU8[extraPtr + 2] & 0x80 ? 'H' : 'M';
          depth = HEAPU8[extraPtr + 2] & 0x40
            ? (HEAPU8[extraPtr + 2] & 0x20 ? 12 : 10)
            : 8;
        }
        if (av1Profile < 0 || av1Profile > 2
            || av1Level < 0 || av1Level > 31
            || (depth !== 8 && depth !== 10 && depth !== 12)) {
          return null;
        }
        return `av01.${av1Profile}.${String(av1Level).padStart(2, '0')}${tier}.${String(depth).padStart(2, '0')}`;
      }
      if (kind === 4) {
        const vp9Profile = profile >= 0 && profile <= 3 ? profile : 0;
        const vp9Level = level >= 10 && level <= 62 ? level : fallbackLevel;
        const depth = bitDepth === 10 || bitDepth === 12
          ? bitDepth
          : (vp9Profile >= 2 ? 10 : 8);
        return `vp09.${String(vp9Profile).padStart(2, '0')}.${String(vp9Level).padStart(2, '0')}.${String(depth).padStart(2, '0')}`;
      }
      if (kind === 6) {
        return 'vp8';
      }

      const hevcProfile = profile > 0 ? profile : 1;
      const hevcLevel = level > 0
        ? level
        : (width * height > 1920 * 1080 ? 153 : 120);
      const compatibility = hevcProfile === 1
        ? 6
        : (hevcProfile === 2 ? 4 : 0);
      return `hvc1.${hevcProfile}.${compatibility}.L${hevcLevel}.B0`;
    },
  },

  ae_wc_init__deps: ['$AEWebCodecs', '$Asyncify'],
  ae_wc_init: function(
    kind,
    ctrlPtr,
    extraPtr,
    extraSize,
    width,
    height,
    sampleRate,
    channels,
    profile,
    level,
    bitDepth,
  ) {
    return Asyncify.handleAsync(async () => {
      if ((kind !== 2 && typeof VideoDecoder === 'undefined')
          || (kind === 2 && typeof AudioDecoder === 'undefined')) {
        return 0;
      }

      let codec;
      let description;
      if (extraSize > 0) {
        description = HEAPU8.slice(extraPtr, extraPtr + extraSize).buffer;
      }
      if (kind !== 2) {
        codec = AEWebCodecs.videoCodec(
          kind,
          extraPtr,
          extraSize,
          width,
          height,
          profile,
          level,
          bitDepth,
        );
        if (!codec) return 0;
        if (kind === 1 && !(extraSize >= 4 && HEAPU8[extraPtr] === 1)) {
          description = undefined;
        } else if (kind === 3 || kind === 4 || kind === 6) {
          description = undefined;
        }
      } else {
        let objectType = 2;
        if (extraSize >= 2) {
          objectType = HEAPU8[extraPtr] >> 3;
          if (objectType === 31) {
            objectType = 32
              + ((HEAPU8[extraPtr] & 7) << 3)
              + (HEAPU8[extraPtr + 1] >> 5);
          }
        }
        codec = `mp4a.40.${objectType}`;
      }

      const config = kind !== 2
        ? {
            codec,
            codedWidth: width,
            codedHeight: height,
            description,
            optimizeForLatency: true,
          }
        : { codec, sampleRate, numberOfChannels: channels, description };
      if (kind === 1 || kind === 5) {
        config.hardwareAcceleration = 'prefer-hardware';
      }
      const supported = kind === 2
        ? await AudioDecoder.isConfigSupported(config)
        : await VideoDecoder.isConfigSupported(config);
      if (!supported.supported) {
        return 0;
      }
      const handle = AEWebCodecs.nextHandle++;
      const entry = {
        kind,
        ctrlPtr,
        config: supported.config,
        decoder: null,
        outputs: [],
        decodeCount: 0,
        outputCount: 0,
        outputWaiter: null,
        error: null,
      };
      try {
        AEWebCodecs.createDecoder(entry);
      } catch (error) {
        console.error('auto-editor WebCodecs configuration:', error);
        return 0;
      }
      AEWebCodecs.handles.set(handle, entry);
      AEWebCodecs.complete(entry, 1);
      return handle;
    });
  },

  ae_wc_decode__deps: ['$AEWebCodecs', '$Asyncify'],
  ae_wc_decode: function(
    handle,
    packetPtr,
    packetSize,
    timestamp,
    duration,
    key,
    outPtr,
    outCapacity,
  ) {
    return Asyncify.handleAsync(async () => {
      const entry = AEWebCodecs.handles.get(handle);
      if (!entry) return -1;
      AEWebCodecs.complete(entry, 0);
      try {
        const data = HEAPU8.slice(packetPtr, packetPtr + packetSize);
        const chunk = entry.kind !== 2
          ? new EncodedVideoChunk({
              type: key ? 'key' : 'delta',
              timestamp,
              duration: duration || undefined,
              data,
            })
          : new EncodedAudioChunk({
              type: 'key',
              timestamp,
              duration: duration || undefined,
              data,
            });
        let outputReady;
        if (!entry.outputs.length) {
          outputReady = new Promise(resolve => {
            entry.outputWaiter = resolve;
          });
        }
        entry.decoder.decode(chunk);
        entry.decodeCount++;
        if (!entry.outputs.length) {
          if (entry.kind === 2) {
            // AAC emits one AudioData for every packet. Waiting for it is
            // required because auto-editor's audio iterator does not issue an
            // explicit end-of-stream drain.
            await new Promise((resolve, reject) => {
              const timer = setTimeout(
                () => reject(new Error('WebCodecs audio decode timed out')),
                30000,
              );
              outputReady.then(() => {
                clearTimeout(timer);
                resolve();
              }, reject);
            });
          } else {
            // H.264 may retain packets for frame reordering.
            await Promise.race([
              outputReady,
              new Promise(resolve => setTimeout(resolve, 0)),
            ]);
          }
        }
        entry.outputWaiter = null;
        if (entry.error) {
          AEWebCodecs.complete(entry, -1);
        } else {
          await AEWebCodecs.emitOne(entry, outPtr, outCapacity);
        }
        return 0;
      } catch (error) {
        AEWebCodecs.fail(entry, error);
        return -1;
      }
    });
  },

  ae_wc_command__deps: ['$AEWebCodecs', '$Asyncify'],
  ae_wc_command: function(handle, command, outPtr, outCapacity) {
    return Asyncify.handleAsync(async () => {
      const entry = AEWebCodecs.handles.get(handle);
      if (!entry) return -1;
      AEWebCodecs.complete(entry, 0);
      try {
        if (command === 3) {
          AEWebCodecs.createDecoder(entry);
          AEWebCodecs.complete(entry, 1);
        } else {
          if (command === 2 && entry.outputCount < entry.decodeCount) {
            await entry.decoder.flush();
          }
          await AEWebCodecs.emitOne(entry, outPtr, outCapacity);
        }
        return 0;
      } catch (error) {
        AEWebCodecs.fail(entry, error);
        return -1;
      }
    });
  },

  ae_wc_close__deps: ['$AEWebCodecs'],
  ae_wc_close: function(handle) {
    const entry = AEWebCodecs.handles.get(handle);
    if (!entry) return;
    if (entry.decoder) {
      try {
        entry.decoder.close();
      } catch {
        // Already closed.
      }
    }
    entry.outputs.splice(0).forEach(sample => sample.close());
    AEWebCodecs.handles.delete(handle);
  },
});
