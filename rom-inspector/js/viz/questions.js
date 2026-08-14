function render_questions(main) {
  const areas = [...new Set(OPEN_QUESTIONS.map(q => q.area))];
  main.innerHTML = `
    <h1 class="page-title">Offene Fragen</h1>
    <p class="page-lede">
      Diese Untersuchung markiert bewusst, was sie (noch) NICHT weiß, statt Lücken zu
      erraten oder stillschweigend zu überspringen &mdash; das ist die Arbeitsweise des
      zugrundeliegenden Reverse-Engineering-Projekts selbst. ${OPEN_QUESTIONS.length} real
      offene Punkte, jeder mit den konkreten ROM-Adressen/Mechanismen, um die es geht.
    </p>
    <div class="toolbar">
      <div class="pill-tabs" id="areaTabs">
        <div class="pill-tab active" data-area="all">Alle</div>
        ${areas.map(a => `<div class="pill-tab" data-area="${escapeHtml(a)}">${escapeHtml(a)}</div>`).join("")}
      </div>
    </div>
    <div class="card-grid" id="questionCards"></div>
  `;
  const host = document.getElementById("questionCards");
  function renderList(area) {
    host.innerHTML = "";
    for (const q of OPEN_QUESTIONS) {
      if (area !== "all" && q.area !== area) continue;
      const card = document.createElement("div");
      card.className = "card question-card";
      card.innerHTML = `<div class="area">${escapeHtml(q.area)}</div><h3>${escapeHtml(q.title)}</h3><div class="desc">${escapeHtml(q.description)}</div>`;
      host.appendChild(card);
    }
  }
  document.querySelectorAll("#areaTabs .pill-tab").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("#areaTabs .pill-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      renderList(tab.dataset.area);
    });
  });
  renderList("all");
}
