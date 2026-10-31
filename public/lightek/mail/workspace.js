(() => {
  if (window.LightekMailWorkspace) {
    window.LightekMailWorkspace.mount();
    return;
  }

  function resizeFrame(frame) {
    try {
      const doc = frame.contentDocument;
      if (!doc) return;
      frame.style.height = `${Math.max(180, Math.min(1600, doc.body.scrollHeight + 12))}px`;
      doc.querySelectorAll("img").forEach((img) =>
        img.addEventListener("load", () => resizeFrame(frame), {
          once: true,
        }),
      );
    } catch (_) {
      /* A clicked external link is no longer our srcdoc document. */
    }
  }

  function mountComposer(form) {
    if (form.dataset.mailMounted) return;
    form.dataset.mailMounted = "1";
    const editor = form.querySelector("[data-mail-editor]");
    const html = form.querySelector("[data-mail-html]");
    const text = form.querySelector("[data-mail-text]");
    if (!editor || !html || !text) return;
    const rich = form.querySelector("[data-rich-composer]");
    const fallback = form.querySelector("[data-mail-fallback]");
    const escape = (value) => {
      const div = document.createElement("div");
      div.textContent = value;
      return div.innerHTML;
    };
    editor.innerHTML =
      html.value ||
      text.value
        .split(/\n{2,}/)
        .map((p) => `<p>${escape(p).replace(/\n/g, "<br>")}</p>`)
        .join("");
    if (!text.value && !html.value) editor.innerHTML = "";
    form.querySelector("[data-mail-rich-enabled]").value = "1";
    rich.hidden = false;
    fallback.hidden = true;
    let selection = null;
    const saveSelection = () => {
      const current = window.getSelection();
      if (current && current.rangeCount && editor.contains(current.anchorNode))
        selection = current.getRangeAt(0).cloneRange();
    };
    const restoreSelection = () => {
      editor.focus();
      if (selection) {
        const current = window.getSelection();
        current.removeAllRanges();
        current.addRange(selection);
      }
    };
    const sync = () => {
      text.value = editor.innerText.replace(/\u00a0/g, " ").trim();
      html.value = text.value ? editor.innerHTML : "";
      form.querySelectorAll("[data-mail-command]").forEach((button) => {
        if (
          ["bold", "italic", "underline"].includes(button.dataset.mailCommand)
        ) {
          button.setAttribute(
            "aria-pressed",
            String(document.queryCommandState(button.dataset.mailCommand)),
          );
        }
      });
    };
    editor.addEventListener("input", sync);
    editor.addEventListener("keyup", saveSelection);
    editor.addEventListener("mouseup", saveSelection);
    // Paste text without executing markup supplied by another application.
    editor.addEventListener("paste", (event) => {
      event.preventDefault();
      document.execCommand(
        "insertText",
        false,
        event.clipboardData.getData("text/plain"),
      );
      sync();
    });
    editor.addEventListener("drop", (event) => event.preventDefault());
    form.querySelectorAll("[data-mail-command]").forEach((button) => {
      button.addEventListener("mousedown", (event) => event.preventDefault());
      button.addEventListener("click", () => {
        restoreSelection();
        document.execCommand(button.dataset.mailCommand, false);
        saveSelection();
        sync();
      });
    });
    const linkRow = form.querySelector("[data-mail-link-row]");
    const linkUrl = form.querySelector("[data-mail-link-url]");
    form.querySelector("[data-mail-link]").addEventListener("click", () => {
      saveSelection();
      linkRow.hidden = false;
      linkUrl.focus();
    });
    form
      .querySelector("[data-mail-link-cancel]")
      .addEventListener("click", () => {
        linkRow.hidden = true;
        restoreSelection();
      });
    const addLink = () => {
      let url;
      try {
        url = new URL(linkUrl.value);
      } catch (_) {
        linkUrl.setCustomValidity(
          "Enter a full https://, http:// or mailto: address.",
        );
        linkUrl.reportValidity();
        return;
      }
      if (!["https:", "http:", "mailto:"].includes(url.protocol)) {
        linkUrl.setCustomValidity("Use https://, http:// or mailto:.");
        linkUrl.reportValidity();
        return;
      }
      linkUrl.setCustomValidity("");
      restoreSelection();
      if (!window.getSelection().toString())
        document.execCommand("insertText", false, url.href);
      else document.execCommand("createLink", false, url.href);
      linkRow.hidden = true;
      linkUrl.value = "";
      saveSelection();
      sync();
    };
    form
      .querySelector("[data-mail-link-apply]")
      .addEventListener("click", addLink);
    linkUrl.addEventListener("input", () => linkUrl.setCustomValidity(""));
    linkUrl.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        addLink();
      }
    });
    const files = form.querySelector("[data-mail-attachments]");
    files.addEventListener("change", () => {
      const target = form.querySelector("[data-mail-file-list]");
      target.replaceChildren();
      Array.from(files.files).forEach((file) => {
        const item = document.createElement("span");
        item.className = "selected-file";
        item.textContent = `${file.name} · ${Math.ceil(file.size / 1024)} KB`;
        target.append(item);
      });
    });
    form.addEventListener("submit", sync);
    form.addEventListener("formdata", (event) => {
      sync();
      event.formData.set("text", text.value);
      event.formData.set("html", html.value);
    });
    sync();
  }

  function mount() {
    document.querySelectorAll("[data-mail-original]").forEach((original) => {
      if (original.dataset.mailMounted) return;
      original.dataset.mailMounted = "1";
      if (window.matchMedia("(max-width: 1050px)").matches)
        original.open = false;
    });
    document.querySelectorAll("[data-mail-compose]").forEach(mountComposer);
    document.querySelectorAll("[data-mail-frame]").forEach((frame) => {
      if (frame.dataset.mailMounted) return;
      frame.dataset.mailMounted = "1";
      frame.addEventListener("load", () => resizeFrame(frame));
      resizeFrame(frame);
      frame
        .closest("details")
        ?.addEventListener("toggle", () => resizeFrame(frame));
    });
  }
  window.LightekMailWorkspace = { mount };
  let resizePending = false;
  window.addEventListener("resize", () => {
    if (resizePending) return;
    resizePending = true;
    window.requestAnimationFrame(() => {
      document.querySelectorAll("[data-mail-frame]").forEach(resizeFrame);
      resizePending = false;
    });
  });
  document.addEventListener("DOMContentLoaded", mount);
  document.addEventListener("turbo:load", mount);
  mount();
})();
