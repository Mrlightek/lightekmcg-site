(() => {
  const MAX_ROWS = 100;
  const MAX_COLUMNS = 26;

  function parse(source) {
    if (!source) return [];
    const rows = [];
    let row = [], cell = "", quoted = false;
    for (let index = 0; index < source.length; index++) {
      const character = source[index];
      if (quoted && character === '"' && source[index + 1] === '"') {
        cell += '"';
        index++;
      } else if (character === '"') {
        quoted = !quoted;
      } else if (!quoted && (character === "," || character === "\n" || character === "\r")) {
        row.push(cell);
        cell = "";
        if (character !== ",") {
          rows.push(row);
          row = [];
          if (character === "\r" && source[index + 1] === "\n") index++;
        }
      } else {
        cell += character;
      }
    }
    if (quoted) throw new Error("Unclosed CSV field");
    if (cell || row.length || !/[\r\n]$/.test(source)) rows.push([...row, cell]);
    return rows;
  }

  function serialize(rows) {
    return Array.from(rows, row => Array.from(row || [], cell => {
      if (!cell) return "";
      return /[",\r\n]/.test(cell) ? '"' + cell.replaceAll('"', '""') + '"' : cell;
    }).join(",")).join("\n");
  }

  function connect(container) {
    if (container.dataset.gridReady) return;
    const source = container.querySelector("[data-office-grid-source]");
    let rows;
    try { rows = parse(source.value); } catch { return; }
    const viewport = document.createElement("div");
    viewport.className = "office-sheet office-edit-grid";
    const table = document.createElement("table");
    table.setAttribute("aria-label", "Edit spreadsheet cells");
    const addRow = document.createElement("button");
    const addColumn = document.createElement("button");
    addRow.type = addColumn.type = "button";
    addRow.textContent = "Add row";
    addColumn.textContent = "Add column";
    viewport.append(table);
    container.append(viewport, addRow, " ", addColumn);
    container.dataset.gridReady = "true";
    source.hidden = true;
    source.labels[0].hidden = true;

    let height = 8;
    let width = 6;
    const label = column => String.fromCharCode(65 + column);

    function draw() {
      height = Math.max(height, rows.length);
      width = Math.max(width, ...rows.map(row => row.length));
      table.replaceChildren();
      const heading = table.createTHead().insertRow();
      for (let column = -1; column < width; column++) {
        const cell = document.createElement("th");
        cell.scope = "col";
        cell.textContent = column < 0 ? "" : label(column);
        heading.append(cell);
      }
      const body = table.createTBody();
      for (let row = 0; row < height; row++) {
        const line = body.insertRow();
        const header = document.createElement("th");
        header.scope = "row";
        header.textContent = row + 1;
        line.append(header);
        for (let column = 0; column < width; column++) {
          const field = document.createElement("textarea");
          field.rows = 1;
          field.maxLength = 4000;
          field.value = rows[row]?.[column] ?? "";
          field.setAttribute("aria-label", label(column) + (row + 1));
          field.addEventListener("input", () => {
            rows[row] ||= [];
            rows[row][column] = field.value;
            while (rows[row].length && !rows[row].at(-1)) rows[row].pop();
            while (rows.length && !rows.at(-1)?.length) rows.pop();
            source.value = serialize(rows);
            source.dispatchEvent(new Event("input", {bubbles: true}));
          });
          line.insertCell().append(field);
        }
      }
      addRow.disabled = height >= MAX_ROWS;
      addColumn.disabled = width >= MAX_COLUMNS;
    }

    // A field may stay focused while its autosave response arrives.
    source.addEventListener("office-snapshot", () => {
      const updatedRows = parse(source.value);
      if (serialize(updatedRows) === serialize(rows)) return;
      const address = table.contains(document.activeElement) ? document.activeElement.getAttribute("aria-label") : null;
      rows = updatedRows;
      draw();
      if (address) table.querySelector('[aria-label="' + address + '"]')?.focus();
    });
    source.required = false;
    addRow.addEventListener("click", () => { height++; draw(); table.rows[height].cells[1].firstChild.focus(); });
    addColumn.addEventListener("click", () => { width++; draw(); table.rows[1].cells[width].firstChild.focus(); });
    draw();
  }

  function start() {
    document.querySelectorAll("[data-office-grid]").forEach(connect);
  }
  document.addEventListener("turbo:load", start);
  start();
})();
