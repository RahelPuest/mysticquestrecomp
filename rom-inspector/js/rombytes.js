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

const RomBytes = {
  bytes: null, // Uint8Array | null
  fileName: null,
  listeners: [],

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

  isLoaded() { return this.bytes !== null; },

  loadFile(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        this.bytes = new Uint8Array(reader.result);
        this.fileName = file.name;
        this._notify();
        resolve();
      };
      reader.onerror = () => reject(reader.error);
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

// Default DMG grey ramp (0=white..3=black) -- a display choice, same
// default as src/rendering/TileImage.lua's own DEFAULT_PALETTE/
// DMG_SHADES (this project's real, live-verified BGP=$E4 confirms the
// identity mapping for backgrounds).
const GB_SHADES = ["#fdfdf5", "#a8a89c", "#4a4a44", "#0a0a08"];

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
