(() => {
  function connect(panel) {
    if (panel.dataset.connected) return;
    const form = panel.closest("form");
    const field = (name) => form.querySelector('[name$="[' + name + ']"]');
    const editor = form.querySelector("trix-editor");
    if (editor && !editor.editor) return;

    panel.dataset.connected = "true";
    const scope = field("lock_version").name.split("[")[0];
    const version = field("lock_version");
    const title = field("title");
    const content = field("content");
    const status = panel.querySelector("[data-office-status]");
    const keep = panel.querySelector("[data-office-draft]");
    const latest = panel.querySelector("[data-office-latest]");
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content ||
      form.querySelector('[name="authenticity_token"]')?.value;
    let savedContent = content.value;
    let savedTitle = title.value;
    let inFlight = false;
    let conflict = false;
    let applying = false;
    let timer;

    const dirty = () => content.value !== savedContent;
    const changedTitle = () => title.value !== savedTitle;
    const report = (message) => {
      if (status.textContent !== message) status.textContent = message;
    };

    function setVersion(value) {
      version.value = value;
      const details = panel.closest("section");
      details.querySelectorAll("[data-office-restore] input[name=lock_version]").forEach((input) => {
        input.value = value;
      });
    }

    function apply(snapshot) {
      setVersion(snapshot.version);
      if (!changedTitle()) title.value = snapshot.title;
      savedTitle = snapshot.title;
      if (dirty() && content.value === snapshot.content) {
        savedContent = content.value;
      } else {
        applying = true;
        if (editor) {
          let html = snapshot.content;
          if (!snapshot.rich_text) {
            const text = document.createElement("div");
            text.textContent = html;
            html = text.innerHTML.replace(/\r\n|\r|\n/g, "<br>");
          }
          editor.editor.loadHTML(html);
        } else {
          content.value = snapshot.content;
          content.dispatchEvent(new Event("office-snapshot"));
        }
        savedContent = content.value;
        applying = false;
      }
    }

    function showConflict() {
      conflict = true;
      latest.hidden = false;
      report("Another editor changed this file. Your edits are still here. Use the latest version to reconcile them.");
    }

    async function refresh(useLatest = false) {
      if (inFlight || !panel.isConnected) return;
      if (!useLatest && (conflict || dirty() || changedTitle() || document.hidden)) return;
      inFlight = true;
      try {
        const url = new URL(panel.dataset.readUrl, location.href);
        if (!useLatest) url.searchParams.set("since", version.value);
        const response = await fetch(url, {headers: {Accept: "application/json"}, cache: "no-store"});
        if (response.status === 204) {
          report("Live editing is on.");
          return;
        }
        if (!response.ok) throw new Error();
        const snapshot = await response.json();
        if (useLatest) {
          keep.value = [title.value, content.value].join("\n\n");
          keep.hidden = false;
          panel.querySelector("[data-office-draft-label]").hidden = false;
          savedTitle = title.value;
          conflict = false;
          latest.hidden = true;
        }
        if (useLatest || (!dirty() && !changedTitle())) {
          apply(snapshot);
          report("Updated to the latest saved version.");
        }
      } catch {
        report("Live editing is reconnecting. Your edits are still here.");
      } finally {
        inFlight = false;
        if (dirty() && !conflict) queueSave();
      }
    }

    async function save() {
      if (inFlight || conflict || !dirty() || !panel.isConnected) return;
      inFlight = true;
      const draft = content.value;
      let retry = false;
      report("Saving changes…");
      try {
        const response = await fetch(panel.dataset.writeUrl, {
          method: panel.dataset.writeMethod,
          headers: {Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrf || ""},
          body: JSON.stringify({[scope]: {content: draft, rich_text: Boolean(editor), lock_version: version.value}})
        });
        if (response.status === 409) {
          showConflict();
          return;
        }
        if (!response.ok) {
          const failure = await response.json().catch(() => ({}));
          report(failure.error || "Could not save. Your edits are still here.");
          retry = response.status >= 500;
          return;
        }
        const snapshot = await response.json();
        if (changedTitle() && snapshot.title !== savedTitle) {
          showConflict();
          return;
        }
        if (content.value === draft) {
          apply(snapshot);
        } else if (snapshot.content === draft) {
          setVersion(snapshot.version);
          if (!changedTitle()) title.value = snapshot.title;
          savedTitle = snapshot.title;
          savedContent = draft;
        } else {
          showConflict();
          return;
        }
        report("Changes saved.");
        retry = dirty();
      } catch {
        report("Live editing is reconnecting. Your edits are still here.");
        retry = true;
      } finally {
        inFlight = false;
        if (retry) queueSave(2000);
      }
    }

    function queueSave(delay = 700) {
      clearTimeout(timer);
      timer = setTimeout(save, delay);
    }

    (editor || content).addEventListener(editor ? "trix-change" : "input", () => {
      if (!applying && dirty()) queueSave();
    });
    function warnBeforeLeaving(event) {
      if (!panel.isConnected || (!dirty() && !changedTitle())) return;
      event.preventDefault();
      event.returnValue = "";
    }
    window.addEventListener("beforeunload", warnBeforeLeaving);
    form.addEventListener("submit", (event) => {
      if (inFlight || conflict) {
        event.preventDefault();
        report(conflict ? "Reconcile the latest version before saving." : "Wait for the current save to finish, then try again.");
      } else {
        window.removeEventListener("beforeunload", warnBeforeLeaving);
      }
    });
    latest.addEventListener("click", () => refresh(true));
    const interval = setInterval(() => {
      if (!panel.isConnected) {
        clearInterval(interval);
        window.removeEventListener("beforeunload", warnBeforeLeaving);
      } else {
        refresh();
      }
    }, 2500);
    report("Live editing is on. Content changes autosave.");
  }

  function start() {
    document.querySelectorAll("[data-office-live]").forEach(connect);
  }
  document.addEventListener("trix-initialize", start);
  document.addEventListener("turbo:load", start);
  start();
})();
