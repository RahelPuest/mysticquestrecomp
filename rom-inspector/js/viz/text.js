// A faithful JS port of src/import/TextDecoder.lua's decodeByte/
// decodeString, driven by the SAME real data tables (TEXT_DECODER) --
// not a reimplementation with separate, potentially-drifting logic.
function td_decodeByte(b) {
  const T = TEXT_DECODER;
  if (b === T.spaceByte) return { ch: " ", kind: "control" };
  if (b === T.periodByte) return { ch: ".", kind: "control" };
  if (b === T.hyphenByte) return { ch: "-", kind: "control" };
  if (b === T.newlineByte) return { ch: "\n", kind: "control" };
  if (b === T.exclamationByte) return { ch: "!", kind: "control" };
  if (b === T.questionByte) return { ch: "?", kind: "control" };
  if (b === T.colonByte) return { ch: ":", kind: "control" };
  const um = T.umlauts.find(u => u.byte === b);
  if (um) return { ch: um.char, kind: "umlaut" };
  const di = T.digraphs.find(d => d.byte === b);
  if (di) return { ch: di.chars, kind: "digraph" };
  if (b >= T.mainBase && b < T.mainBase + T.mainGlyphs.length) {
    return { ch: T.mainGlyphs[b - T.mainBase], kind: "main" };
  }
  return null;
}

function render_text(main) {
  main.innerHTML = `
    <h1 class="page-title">Text-Encoding</h1>
    <p class="page-lede">
      Mystic Quests eigenes In-ROM-Textformat: ein 64-Glyphen-Hauptalphabet ab Byte
      ${hex(TEXT_DECODER.mainBase, 2)}, ein separates Digraph-Kompressionsbyte darunter
      (aktuell ${TEXT_DECODER.digraphs.length} von möglichen 176 Werten cross-verifiziert),
      7 Umlaut/Eszett-Sonderbytes, und ${["0x1A newline", "0xFF space", "0x00 terminator"].join(", ")}
      plus feste Satzzeichen-Bytes.
    </p>

    <h2 class="section-title">Live-Dekodierer</h2>
    <div class="panel">
      <div class="toolbar">
        ${TEXT_DECODER.samples.map((s, i) => `<button class="btn small" data-sample="${i}">Beispiel: ${escapeHtml(s.label)}</button>`).join("")}
        <button class="btn small" id="clearBytes">Leeren</button>
      </div>
      <textarea id="byteInput" class="mono-input" rows="3" style="width:100%;" placeholder="Hex-Bytes, z.B. B6 B0 BF ... 00" aria-label="Hex-Bytes zum Dekodieren eingeben"></textarea>
      <div style="margin-top:10px;">
        <button class="btn primary" id="decodeBtn">Dekodieren</button>
      </div>
      <div class="decode-trace" id="decodeTrace"></div>
      <div class="decode-output" id="decodeOutput"></div>
    </div>

    <h2 class="section-title">Referenz-Tabellen</h2>
    <div class="pill-tabs" id="refTabs">
      <div class="pill-tab active" data-ref="main">Hauptalphabet</div>
      <div class="pill-tab" data-ref="digraphs">Digraphen (${TEXT_DECODER.digraphs.length})</div>
      <div class="pill-tab" data-ref="umlauts">Umlaute</div>
      <div class="pill-tab" data-ref="control">Steuerbytes</div>
    </div>
    <div id="refTable" class="panel"></div>
  `;

  const byteInput = document.getElementById("byteInput");
  document.querySelectorAll("[data-sample]").forEach(btn => {
    btn.addEventListener("click", () => {
      const s = TEXT_DECODER.samples[parseInt(btn.dataset.sample, 10)];
      byteInput.value = s.bytes.map(b => b.toString(16).toUpperCase().padStart(2, "0")).join(" ");
      runDecode();
    });
  });
  document.getElementById("clearBytes").addEventListener("click", () => { byteInput.value = ""; document.getElementById("decodeTrace").innerHTML = ""; document.getElementById("decodeOutput").textContent = ""; });
  document.getElementById("decodeBtn").addEventListener("click", runDecode);

  function runDecode() {
    const bytes = byteInput.value.trim().split(/[\s,]+/).filter(Boolean).map(s => parseInt(s.replace(/^0x/i, ""), 16)).filter(n => !isNaN(n));
    const trace = document.getElementById("decodeTrace");
    trace.innerHTML = "";
    let out = "";
    let stopped = false;
    for (const b of bytes) {
      const box = document.createElement("div");
      box.className = "decode-byte";
      if (b === TEXT_DECODER.terminatorByte) {
        box.classList.add("control");
        box.innerHTML = `<span class="b">${hex(b, 2)}</span><span class="c">\\0</span>`;
        trace.appendChild(box);
        stopped = true;
        break;
      }
      const d = td_decodeByte(b);
      if (!d) {
        box.classList.add("unknown");
        box.innerHTML = `<span class="b">${hex(b, 2)}</span><span class="c">?</span>`;
        trace.appendChild(box);
        stopped = true;
        break;
      }
      box.classList.add(d.kind);
      box.innerHTML = `<span class="b">${hex(b, 2)}</span><span class="c">${escapeHtml(d.ch === "\n" ? "\\n" : d.ch)}</span>`;
      trace.appendChild(box);
      out += d.ch;
    }
    document.getElementById("decodeOutput").textContent = out || "(kein Text)";
    if (stopped) {
      const note = document.createElement("div");
      note.style.cssText = "width:100%; font-size:11px; color:var(--text-faint); margin-top:4px;";
      note.textContent = "Dekodierung gestoppt (Terminator oder unbekanntes Byte) -- exakt wie TextDecoder.decodeString es real tut.";
      trace.appendChild(note);
    }
  }

  function renderRef(kind) {
    const host = document.getElementById("refTable");
    if (kind === "main") {
      let rows = "";
      for (let i = 0; i < TEXT_DECODER.mainGlyphs.length; i++) {
        rows += `<tr><td class="addr">${hex(TEXT_DECODER.mainBase + i, 2)}</td><td class="mono" style="font-size:16px;">${escapeHtml(TEXT_DECODER.mainGlyphs[i])}</td></tr>`;
      }
      host.innerHTML = `<table class="data-table"><thead><tr><th>Byte</th><th>Zeichen</th></tr></thead><tbody>${rows}</tbody></table>`;
    } else if (kind === "digraphs") {
      const rows = TEXT_DECODER.digraphs.map(d => `<tr><td class="addr">${hex(d.byte, 2)}</td><td class="mono">"${escapeHtml(d.chars)}"</td></tr>`).join("");
      host.innerHTML = `<table class="data-table"><thead><tr><th>Byte</th><th>Zeichenpaar</th></tr></thead><tbody>${rows}</tbody></table>
        <p style="color:var(--text-dim); font-size:12px; margin-top:10px;">Nur cross-verifizierte Einträge (2+ unabhängige Wörter/Namen) &mdash; siehe „Offene Fragen“ für weitere, noch nicht bestätigte Kandidaten.</p>`;
    } else if (kind === "umlauts") {
      const rows = TEXT_DECODER.umlauts.map(u => `<tr><td class="addr">${hex(u.byte, 2)}</td><td class="mono" style="font-size:16px;">${escapeHtml(u.char)}</td></tr>`).join("");
      host.innerHTML = `<table class="data-table"><thead><tr><th>Byte</th><th>Zeichen</th></tr></thead><tbody>${rows}</tbody></table>`;
    } else {
      const controls = [
        ["Space", TEXT_DECODER.spaceByte], ["Terminator", TEXT_DECODER.terminatorByte],
        ["Period .", TEXT_DECODER.periodByte], ["Hyphen -", TEXT_DECODER.hyphenByte],
        ["Newline", TEXT_DECODER.newlineByte], ["Exclamation !", TEXT_DECODER.exclamationByte],
        ["Question ?", TEXT_DECODER.questionByte], ["Colon :", TEXT_DECODER.colonByte],
      ];
      const rows = controls.map(([n, b]) => `<tr><td class="addr">${hex(b, 2)}</td><td>${n}</td></tr>`).join("");
      host.innerHTML = `<table class="data-table"><thead><tr><th>Byte</th><th>Bedeutung</th></tr></thead><tbody>${rows}</tbody></table>`;
    }
  }
  document.querySelectorAll("#refTabs .pill-tab").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("#refTabs .pill-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      renderRef(tab.dataset.ref);
    });
  });
  renderRef("main");
}
