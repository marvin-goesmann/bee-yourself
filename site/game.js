import { WASI, File, OpenFile, ConsoleStdout } from "https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.4.2/+esm";

const SAVE_KEY = "bee-yourself-save";
const WIDTH = 240;
const HEIGHT = 180;
const FRAME_SECONDS = 1 / 30;
const SAVE_INTERVAL_MS = 60_000;

export async function start(canvas) {
  const exports = await load();
  const bytes = () => new Uint8Array(exports.memory.buffer);

  exports.bee_set_utc_offset(-new Date().getTimezoneOffset() * 60);
  const saved = readSave();
  if (saved) {
    const data = new TextEncoder().encode(saved);
    const pointer = exports.bee_alloc(data.length);
    bytes().set(data, pointer);
    exports.bee_start(pointer, data.length);
  } else {
    exports.bee_start(0, 0);
  }

  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(WIDTH, HEIGHT);
  let last;

  function frame(now) {
    requestAnimationFrame(frame);
    if (last !== undefined && now - last < FRAME_SECONDS * 900) return;
    const dt = last === undefined ? FRAME_SECONDS : Math.min(0.1, (now - last) / 1000);
    last = now;
    const pointer = exports.bee_frame(dt, now / 1000);
    if (!pointer) return;
    image.data.set(new Uint8Array(exports.memory.buffer, pointer, WIDTH * HEIGHT * 4));
    ctx.putImageData(image, 0, 0);
    canvas.style.cursor = exports.bee_pointer() ? "pointer" : "default";
    if (exports.bee_dirty()) save();
  }
  requestAnimationFrame(frame);

  function save() {
    const length = exports.bee_save();
    if (!length) return;
    const json = new TextDecoder().decode(new Uint8Array(exports.memory.buffer, exports.bee_saved(), length));
    try { localStorage.setItem(SAVE_KEY, json); } catch {}
  }

  function point(event) {
    const rect = canvas.getBoundingClientRect();
    return [(event.clientX - rect.left) / rect.width * WIDTH, (event.clientY - rect.top) / rect.height * HEIGHT];
  }

  canvas.addEventListener("pointerdown", (event) => {
    canvas.setPointerCapture(event.pointerId);
    const [x, y] = point(event);
    exports.bee_hover(x, y);
    exports.bee_down(x, y);
  });
  canvas.addEventListener("pointermove", (event) => {
    const [x, y] = point(event);
    if (event.buttons) exports.bee_drag(x, y); else exports.bee_hover(x, y);
  });
  canvas.addEventListener("pointerup", (event) => {
    const [x, y] = point(event);
    exports.bee_up(x, y);
    if (event.pointerType !== "mouse") exports.bee_leave();
  });
  canvas.addEventListener("pointerleave", (event) => {
    if (!event.buttons) exports.bee_leave();
  });

  let scrolled = 0;
  canvas.addEventListener("wheel", (event) => {
    event.preventDefault();
    scrolled += event.deltaY;
    if (Math.abs(scrolled) < 30) return;
    exports.bee_scroll(Math.sign(scrolled));
    scrolled = 0;
  }, { passive: false });

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape") exports.bee_escape();
  });

  let hiddenAt;
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      hiddenAt = Date.now();
      save();
    } else if (hiddenAt !== undefined) {
      const seconds = (Date.now() - hiddenAt) / 1000;
      if (seconds > 1) exports.bee_catch_up(seconds);
      hiddenAt = undefined;
      last = undefined;
    }
  });
  window.addEventListener("pagehide", save);
  setInterval(save, SAVE_INTERVAL_MS);
}

async function load() {
  const wasi = new WASI([], [], [
    new OpenFile(new File([])),
    ConsoleStdout.lineBuffered((line) => console.log(line)),
    ConsoleStdout.lineBuffered((line) => console.warn(line)),
  ]);
  const imports = { wasi_snapshot_preview1: wasi.wasiImport };
  const url = "/bee.wasm?v=5";
  let instance;
  try {
    ({ instance } = await WebAssembly.instantiateStreaming(fetch(url), imports));
  } catch {
    ({ instance } = await WebAssembly.instantiate(await (await fetch(url)).arrayBuffer(), imports));
  }
  wasi.initialize(instance);
  return instance.exports;
}

function readSave() {
  try { return localStorage.getItem(SAVE_KEY); } catch { return null; }
}
