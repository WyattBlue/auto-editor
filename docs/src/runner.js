// Runs the auto-editor wasm module inside a dedicated worker.
//
// Why a worker: the module is built with PROXY_TO_PTHREAD, so every FS syscall
// is proxied to the thread that owns the runtime. On the page's UI thread that
// thread has no FileReaderSync, which WORKERFS needs to read File slices. Owning
// the runtime here (a worker) puts FileReaderSync in reach, so inputs can be
// mounted via WORKERFS and read slice-by-slice off disk instead of being loaded
// into a single JS ArrayBuffer (which caps out near 2-4GB). Inputs are therefore
// effectively unbounded; outputs still live in MEMFS (~4GB ceiling).

// Feature-detect wasm64 (memory section with i64 limits flag = 0x04).
const hasWasm64 = WebAssembly.validate(new Uint8Array([
  0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 4, 1
]));
// In a worker Emscripten's _scriptName resolves to self.location (this file), so
// it would spawn the pthread pool running runner.js. Pin the module's real URL
// so mainScriptUrlOrBlob points the pool workers at the right script.
const scriptUrl = new URL(
  (hasWasm64 ? 'auto-editor-web64' : 'auto-editor-web') + '.js', self.location.href
).href;
importScripts(scriptUrl);

const IN = '/in';      // read-only WORKERFS mount of the input Files
const WORK = '/work';  // writable MEMFS: input symlinks live here, outputs land here
const CHUNK = 64 * 1024 * 1024;

self.onmessage = async (e) => {
  if (e.data.type !== 'run') return;
  const { args, files } = e.data;
  const print = (text) => self.postMessage({ type: 'print', text });

  let resolveDone, rejectDone;
  const done = new Promise((res, rej) => { resolveDone = res; rejectDone = rej; });

  let mod;
  try {
    mod = await AutoEditor({
      arguments: args,
      mainScriptUrlOrBlob: scriptUrl,
      print, printErr: print,
      preRun: [(m) => {
        m.FS.mkdir(IN);
        m.FS.mount(m.FS.filesystems.WORKERFS, { files }, IN);
        m.FS.mkdir(WORK);
        // Default output is written next to the input; symlink the read-only
        // input into the writable dir so that path resolves and stays writable.
        for (const f of files) m.FS.symlink(IN + '/' + f.name, WORK + '/' + f.name);
      }],
      onExit: (code) =>
        code === 0 ? resolveDone() : rejectDone(new Error('exited with code ' + code)),
    });
  } catch (err) {
    self.postMessage({ type: 'error', message: 'module init failed: ' + err });
    return;
  }

  try {
    await done;
  } catch (err) {
    self.postMessage({ type: 'error', message: err.message });
    return;
  }

  // Anything in WORK that isn't an input symlink is an output. Read it out in
  // chunks into a multi-part Blob, which can exceed the single-ArrayBuffer cap.
  const inputNames = new Set(files.map(f => f.name));
  for (const name of mod.FS.readdir(WORK)) {
    if (name === '.' || name === '..' || inputNames.has(name)) continue;
    const path = WORK + '/' + name;
    let st;
    try { st = mod.FS.lstat(path); } catch { continue; }
    if (mod.FS.isLink(st.mode) || !mod.FS.isFile(st.mode)) continue;

    const fd = mod.FS.open(path, 'r');
    const parts = [];
    const buf = new Uint8Array(CHUNK);
    for (let pos = 0; pos < st.size; pos += CHUNK) {
      const n = mod.FS.read(fd, buf, 0, Math.min(CHUNK, st.size - pos), pos);
      parts.push(buf.slice(0, n));
    }
    mod.FS.close(fd);
    self.postMessage({ type: 'output', name, blob: new Blob(parts) });
  }
  self.postMessage({ type: 'done' });
};
