// Client-side, local-only ROM loading + Game Boy 2bpp tile decoding.
// The ROM file NEVER leaves the browser (no fetch/upload, plain
// FileReader -> ArrayBuffer) -- this project never ships or transmits
// ROM bytes itself, same convention as the main codebase's own
// RomLocator.lua ("look for a local file, never embed one"). Without a
// loaded ROM, the Tile/Map viewers show a clear prompt instead of
// silently rendering nothing.
//
// GBTile decode faithfully ports src/rendering/GBTile.lua's own
// `decodeTile` (kept in sync deliberately, per that file's own doc
// comment linking it to tools/graphics/gbtile.py) -- same 2bpp planar
// algorithm, not a reimplementation with different bit order.

// Real Game Boy header validation -- the SAME algorithm as
// src/import/RomIdentity.lua's own `identify()` (header checksum over
// 0x134-0x14C, stored at 0x14D; deliberately kept in sync, matching
// this file's own established convention for gbDecodeTile mirroring
// GBTile.lua). AUDIT FINDING (2026-08-20): `loadFile` used to accept
// ANY file with zero validation -- the `<input accept=".gb">` in
// index.html is only a file-picker hint (a user can still pick "all
// files" or drag in something else), and nothing downstream ever
// checked what actually got loaded. A wrong file used to silently
// become "the loaded ROM" -- every canvas/table reading `RomBytes.
// bytes` would then read garbage or throw deep inside a render
// function, with no indication of what actually went wrong. Now
// rejected right here, before `this.bytes` is ever set.
function validateGbRom(bytes) {
  if (bytes.length < 0x150) {
    return { ok: false, reason: `Datei zu klein (${bytes.length} Byte) -- ein echter Game-Boy-ROM-Header braucht mindestens 336 Byte.` };
  }
  let x = 0;
  for (let i = 0x134; i <= 0x14C; i++) x = (x - bytes[i] - 1) & 0xFF;
  if (x !== bytes[0x14D]) {
    return { ok: false, reason: "Header-Prüfsumme stimmt nicht -- das ist wahrscheinlich keine gültige Game-Boy-ROM-Datei (oder sie ist beschädigt)." };
  }
  return { ok: true };
}

const RomBytes = {
  bytes: null, // Uint8Array | null
  fileName: null,
  listeners: [],
  errorListeners: [],

  // Registers `fn` to run on every future load; returns an unsubscribe
  // function. Callers that only care while their own section is
  // mounted (the Tile/Map viewers) MUST unsubscribe on navigation --
  // see js/app.js's `onSectionUnload` -- otherwise a stale listener
  // referencing a since-removed DOM node throws once the ROM is loaded
  // from a different section.
  onChange(fn) {
    this.listeners.push(fn);
    return () => {
      const i = this.listeners.indexOf(fn);
      if (i !== -1) this.listeners.splice(i, 1);
    };
  },
  _notify() { for (const fn of this.listeners) fn(); },

  // Fires ONLY when a load attempt fails validation/reading -- kept
  // separate from `onChange` (a real successful load) so a listener
  // that only cares about "the ROM changed" never has to branch on
  // success/failure itself.
  onError(fn) {
    this.errorListeners.push(fn);
    return () => {
      const i = this.errorListeners.indexOf(fn);
      if (i !== -1) this.errorListeners.splice(i, 1);
    };
  },
  _notifyError(reason) { for (const fn of this.errorListeners) fn(reason); },

  isLoaded() { return this.bytes !== null; },

  // Resolves on a real, successfully-validated ROM load; rejects (with
  // a human-readable German reason, also broadcast via onError) on a
  // read failure or a file that fails the real header check above.
  // Never leaves `this.bytes` pointing at unvalidated data -- a failed
  // load keeps whatever ROM (or lack of one) was already loaded.
  loadFile(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const bytes = new Uint8Array(reader.result);
        const check = validateGbRom(bytes);
        if (!check.ok) {
          this._notifyError(check.reason);
          reject(new Error(check.reason));
          return;
        }
        this.bytes = bytes;
        this.fileName = file.name;
        this._notify();
        resolve();
      };
      reader.onerror = () => {
        const reason = "Datei konnte nicht gelesen werden.";
        this._notifyError(reason);
        reject(reader.error || new Error(reason));
      };
      reader.readAsArrayBuffer(file);
    });
  },

  // 16 raw bytes starting at `fileOffset`, or null if out of range /
  // no ROM loaded.
  tileBytesAt(fileOffset) {
    if (!this.bytes || fileOffset + 16 > this.bytes.length || fileOffset < 0) return null;
    return this.bytes.subarray(fileOffset, fileOffset + 16);
  },
};

// Real Game Boy 2bpp decode: 16 bytes -> 8x8 array of 0-3 palette indices.
// `bytes` any indexable byte source (Uint8Array or plain array), 0-based.
function gbDecodeTile(bytes) {
  const rows = [];
  for (let y = 0; y < 8; y++) {
    const lo = bytes[y * 2], hi = bytes[y * 2 + 1];
    const row = [];
    for (let x = 0; x < 8; x++) {
      const bitIndex = 7 - x;
      const pixel = (((hi >> bitIndex) & 1) << 1) | ((lo >> bitIndex) & 1);
      row.push(pixel);
    }
    rows.push(row);
  }
  return rows;
}

// Palette PRESETS -- a pure viewer/display preference, NOT decoded ROM
// data. The real, live-verified fact this project has established is
// just BGP=$E4 (the identity 0->0,1->1,2->2,3->3 shade mapping, see
// src/rendering/TileImage.lua's own DEFAULT_PALETTE/DMG_SHADES doc
// comment) -- which of the Game Boy's many real physical screens
// (original DMG green LCD, Pocket's monochrome LCD, Game Boy Light's
// amber backlight) actually rendered those 4 shades is a hardware/
// accessory choice the ROM itself has no opinion on. These 4 presets
// are well-known reference colors for those real screens (commonly
// used by GB tile viewers/emulators), offered here purely so the
// website is easier to look at -- never presented as "the real ROM
// palette," which does not exist as a single fixed color scheme.
const GBPalette = {
  PRESETS: {
    grey: { label: "Graustufen (Standard)", colors: ["#fdfdf5", "#a8a89c", "#4a4a44", "#0a0a08"] },
    dmgGreen: { label: "DMG-Grün (Original Game Boy)", colors: ["#9bbc0f", "#8bac0f", "#306230", "#0f380f"] },
    pocket: { label: "Game Boy Pocket (reines S/W)", colors: ["#ffffff", "#a9a9a9", "#545454", "#000000"] },
    amber: { label: "Bernstein (Game Boy Light)", colors: ["#f7e7c6", "#dcae57", "#a8702c", "#3f2810"] },
  },
  current: "grey",
  listeners: [],

  colors() { return this.PRESETS[this.current].colors; },

  set(name) {
    if (!this.PRESETS[name] || name === this.current) return;
    this.current = name;
    try { localStorage.setItem("mq_rominspector_palette", name); } catch (e) { /* private mode etc. -- fine, just don't persist */ }
    GB_SHADES = this.PRESETS[name].colors;
    this._notify();
  },

  // Restores a previously-picked preset (if any) before first render.
  init() {
    let saved = null;
    try { saved = localStorage.getItem("mq_rominspector_palette"); } catch (e) { /* ignore */ }
    if (saved && this.PRESETS[saved]) {
      this.current = saved;
      GB_SHADES = this.PRESETS[saved].colors;
    }
  },

  onChange(fn) {
    this.listeners.push(fn);
    return () => {
      const i = this.listeners.indexOf(fn);
      if (i !== -1) this.listeners.splice(i, 1);
    };
  },
  _notify() { for (const fn of this.listeners) fn(); },
};

// The actually-active 4-shade ramp (0=lightest..3=darkest) `gbDrawTile`
// reads on every call -- a `let`, not `const`, specifically so
// `GBPalette.set()` above can swap it and have every canvas pick up
// the new colors on its next redraw, no per-viz-module wiring needed.
let GB_SHADES = GBPalette.PRESETS.grey.colors;

// Draws one decoded tile (8x8 array of 0-3) onto a canvas 2D context at
// (dx, dy), each pixel scaled by `scale`.
function gbDrawTile(ctx2d, tile, dx, dy, scale) {
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) {
      ctx2d.fillStyle = GB_SHADES[tile[y][x]];
      ctx2d.fillRect(dx + x * scale, dy + y * scale, scale, scale);
    }
  }
}

// Resolves one ROOM_MAPS tileOffsets entry (either a plain number file
// offset, or `{literal:[16 bytes]}` for the handful of real tiles
// stored as a literal pattern rather than a ROM address -- see
// export_data.lua's own doc comment) into raw 16-byte tile data, or
// null if it needs the ROM and none is loaded.
function resolveTileBytes(entry) {
  if (entry && typeof entry === "object" && entry.literal) return entry.literal;
  if (typeof entry === "number") return RomBytes.tileBytesAt(entry);
  return null;
}
