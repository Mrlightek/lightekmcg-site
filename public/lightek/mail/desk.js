(() => {
  if (window.LightekMailDesk) return;
  const mount = () => {
    const app = document.querySelector("[data-mail-app]");
    if (!app || app.dataset.mounted) return;
    app.dataset.mounted = "1";
    const dock = app.querySelector("[data-mail-compose-dock]");
    const dockFrame = dock.querySelector("iframe");
    let dirty = false,
      lastFocus = null,
      request = null,
      toastTimer;
    const status = (text) => {
      const box = app.querySelector("[data-mail-status]");
      box.textContent = text;
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => (box.textContent = ""), 7000);
    };
    const embed = (url) => {
      const parsed = new URL(url, location.href);
      parsed.searchParams.set("workspace", "1");
      return parsed.href;
    };
    const closeDock = () => {
      if (
        dirty &&
        !confirm(
          "Close this composer? Unsaved changes and selected files will be lost. Save a draft to keep the message.",
        )
      )
        return;
      dirty = false;
      dock.hidden = true;
      dockFrame.removeAttribute("src");
      lastFocus?.focus();
    };
    const compose = (url) => {
      if (!dock.hidden) {
        dock.classList.remove("is-minimized");
        if (dockFrame.src === embed(url)) return;
        if (
          dirty &&
          !confirm(
            "Replace your current composer? Save a draft first to keep your message.",
          )
        )
          return;
      }
      dirty = false;
      lastFocus = document.activeElement;
      dock.hidden = false;
      dock.classList.remove("is-minimized");
      dockFrame.src = embed(url);
      app.querySelector("[data-mail-dock-title]").textContent = new URL(
        url,
        location.href,
      ).searchParams.has("reply_id")
        ? "Conversation reply"
        : "New message";
    };
    const navigate = async (url, options = {}) => {
      request?.abort();
      request = new AbortController();
      const shell = app.querySelector("[data-mail-shell]");
      shell.setAttribute("aria-busy", "true");
      status(options.method ? "Updating messages…" : "Loading your mail…");
      try {
        const response = await fetch(url, {
          credentials: "same-origin",
          signal: request.signal,
          ...options,
        });
        const doc = new DOMParser().parseFromString(
          await response.text(),
          "text/html",
        );
        const next = doc.querySelector("[data-mail-shell]");
        if (!response.ok || !next)
          throw new Error(
            doc.querySelector(".alert, .notice.danger")?.textContent ||
              "Mail could not be loaded. Please try again.",
          );
        shell.replaceWith(next);
        app.dataset.account =
          doc.querySelector("[data-mail-app]").dataset.account;
        app.querySelector(".mail-brand").href =
          `/dashboard/mail?account_id=${app.dataset.account}`;
        app.querySelector(".mail-topbar a:not(.mail-brand)").href =
          `/dashboard/mail?account_id=${app.dataset.account}&view=settings`;
        const target = new URL(response.url);
        if (!options.pop)
          history.pushState(
            {},
            "",
            target.pathname + target.search + target.hash,
          );
        status(
          options.method
            ? doc.querySelector("[data-mail-notice], .undo-bar span")
                ?.textContent || "Mailbox updated."
            : "",
        );
        if (target.hash)
          document
            .getElementById(target.hash.slice(1))
            ?.scrollIntoView({ block: "start" });
      } catch (error) {
        if (error.name !== "AbortError") status(error.message);
      } finally {
        shell.removeAttribute("aria-busy");
      }
    };
    const read = (link) => {
      const frame = app.querySelector("[data-mail-reader-frame]");
      if (!frame) return;
      app.querySelectorAll("[data-mail-item]").forEach((row) => {
        const active = row.contains(link);
        row.classList.toggle("is-active", active);
        row
          .querySelector("[data-mail-read]")
          .setAttribute("aria-current", String(active));
      });
      app.querySelector("[data-mail-reader-empty]").hidden = true;
      app.querySelector("[data-mail-reader-toolbar]").hidden = false;
      app.querySelector("[data-mail-reader-full]").href = link.href;
      frame.hidden = false;
      frame.src = embed(link.href);
      frame.setAttribute("aria-busy", "true");
      app.querySelector(".mail-desk").classList.add("reader-open");
      status("Opening conversation…");
    };
    const closeReader = () => {
      app.querySelector(".mail-desk")?.classList.remove("reader-open");
      app.querySelector("[data-mail-item].is-active a")?.focus();
    };
    const preview = (url) => {
      const dialog = app.querySelector("[data-mail-preview-modal]");
      dialog.querySelector("iframe").src = url;
      const download = new URL(url);
      download.searchParams.delete("preview");
      dialog.querySelector("a").href = download.href;
      dialog.showModal();
    };
    const wireFrame = (frame, composing) => {
      let doc;
      try {
        doc = frame.contentDocument;
      } catch (_) {
        return;
      }
      if (!doc?.body) return;
      doc.body.classList.add("workspace-embedded");
      // Keep navigation in the workspace and compose separate from the reader.
      doc.addEventListener("click", (event) => {
        const link = event.target.closest("a");
        if (!link || event.metaKey || event.ctrlKey || event.shiftKey) return;
        const url = new URL(link.href, location.href);
        if (url.origin !== location.origin) return;
        if (link.hasAttribute("data-mail-preview")) {
          event.preventDefault();
          preview(url.href);
        } else if (/\/compose$/.test(url.pathname)) {
          event.preventDefault();
          compose(url.href);
        } else if (
          url.pathname === "/dashboard/mail" ||
          url.pathname === "/dashboard/mail/"
        ) {
          event.preventDefault();
          if (composing) closeDock();
          else closeReader();
        } else if (/\/messages\/\d+$/.test(url.pathname)) {
          event.preventDefault();
          frame.src = embed(url.href);
        }
      });
      doc.querySelectorAll("form").forEach((form) => {
        form.dataset.turbo = "false";
        const field = document.createElement("input");
        field.type = "hidden";
        field.name = "workspace";
        field.value = "1";
        if (!form.querySelector("[name=workspace]")) form.append(field);
        form.addEventListener("submit", () => {
          if (composing) dirty = false;
        });
      });
      if (composing) {
        const form = doc.querySelector("[data-mail-compose]");
        if (form) {
          dirty = Boolean(doc.querySelector("[data-mail-compose-error]"));
          form.addEventListener("input", () => (dirty = true));
          form.addEventListener("change", () => (dirty = true));
          form.querySelector("[name=to]")?.focus();
        }
        const completed = doc.querySelector("[data-mail-composed]")?.dataset
          .mailComposed;
        if (completed) {
          dirty = false;
          dock.hidden = true;
          status(
            completed === "draft"
              ? "Draft saved. Ready when you are."
              : "Message queued for sending.",
          );
          navigate(location.href);
        } else if (!form && !doc.querySelector("[data-mail-message-id]")) {
          status("Your session may have expired. Open Mail again to sign in.");
        }
      } else {
        frame.removeAttribute("aria-busy");
        status("");
        const id = doc.querySelector("[data-mail-message-id]")?.dataset
          .mailMessageId;
        if (id) {
          const row = app.querySelector(`[data-mail-item="${id}"]`);
          if (row?.classList.contains("unread")) {
            row.classList.remove("unread");
            row.querySelector(".unread-dot")?.remove();
            const unread = app.querySelector(
              '.folder-nav a[href*="folder=unread"] .folder-count',
            );
            if (unread)
              unread.textContent = Math.max(0, Number(unread.textContent) - 1);
          }
        }
        // A flag action redirects to the inbox: refresh the outer list instead.
        if (doc.querySelector("[data-mail-app]")) navigate(location.href);
      }
    };
    dockFrame.addEventListener("load", () => wireFrame(dockFrame, true));
    app.addEventListener(
      "load",
      (event) => {
        if (event.target.matches("[data-mail-reader-frame]"))
          wireFrame(event.target, false);
      },
      true,
    );
    app.addEventListener("click", (event) => {
      const link = event.target.closest("a");
      if (
        link &&
        !event.metaKey &&
        !event.ctrlKey &&
        !event.shiftKey &&
        event.button === 0
      ) {
        if (link.matches("[data-mail-dock]")) {
          event.preventDefault();
          compose(link.href);
        } else if (link.matches("[data-mail-read]")) {
          event.preventDefault();
          read(link);
        } else if (link.matches("[data-mail-nav]")) {
          event.preventDefault();
          navigate(link.href);
        }
      }
      if (event.target.closest("[data-mail-help]"))
        app.querySelector("[data-mail-shortcuts]").showModal();
      if (event.target.closest("[data-mail-modal-close]"))
        event.target.closest("dialog").close();
      if (event.target.closest("[data-mail-dock-close]")) closeDock();
      if (event.target.closest("[data-mail-dock-minimize]")) {
        dock.classList.toggle("is-minimized");
        event.target
          .closest("button")
          .setAttribute(
            "aria-label",
            dock.classList.contains("is-minimized")
              ? "Restore composer"
              : "Minimize composer",
          );
      }
      if (event.target.closest("[data-mail-dock-expand]")) {
        dock.classList.toggle("is-expanded");
        dock.classList.remove("is-minimized");
      }
      if (event.target.closest("[data-mail-reader-close]")) closeReader();
    });
    app.addEventListener("submit", (event) => {
      const form = event.target;
      if (form.matches("[data-mail-search]")) {
        event.preventDefault();
        const url = new URL(form.action);
        new FormData(form).forEach((value, key) =>
          url.searchParams.set(key, value),
        );
        navigate(url);
      }
      if (form.matches("[data-mail-bulk]")) {
        event.preventDefault();
        const data = new FormData(form);
        if (event.submitter?.name)
          data.set(event.submitter.name, event.submitter.value);
        if (
          form.querySelector('[name="message_ids[]"]') &&
          !data.getAll("message_ids[]").length
        ) {
          status("Select a message first.");
          return;
        }
        navigate(form.action, { method: "POST", body: data });
      }
    });
    app.addEventListener("change", (event) => {
      if (event.target.matches("[data-mail-switch]")) {
        const form = event.target.form;
        form.requestSubmit();
      }
      if (event.target.matches("[data-mail-select-all]"))
        app
          .querySelectorAll('[name="message_ids[]"]')
          .forEach((box) => (box.checked = event.target.checked));
      const boxes = [...app.querySelectorAll('[name="message_ids[]"]')];
      const checked = boxes.filter((box) => box.checked).length;
      const count = app.querySelector("[data-mail-selection-count]");
      if (count)
        count.textContent = checked ? `${checked} selected` : "Select messages";
      const all = app.querySelector("[data-mail-select-all]");
      if (all) {
        all.checked = boxes.length > 0 && checked === boxes.length;
        all.indeterminate = checked > 0 && checked < boxes.length;
      }
    });
    document.addEventListener("keydown", (event) => {
      if (
        !app.isConnected ||
        event.ctrlKey ||
        event.metaKey ||
        event.altKey ||
        event.target.closest("input,textarea,select,[contenteditable=true]") ||
        app.querySelector("dialog[open]")
      )
        return;
      const rows = [...app.querySelectorAll("[data-mail-read]")];
      const current = rows.findIndex((row) =>
        row.closest("[data-mail-item]").classList.contains("is-active"),
      );
      if (event.key === "c") {
        event.preventDefault();
        const link = app.querySelector("[data-mail-dock]");
        if (link) compose(link.href);
      }
      if (event.key === "/") {
        event.preventDefault();
        app.querySelector("[name=q]")?.focus();
      }
      if (event.key === "?") {
        event.preventDefault();
        app.querySelector("[data-mail-shortcuts]").showModal();
      }
      if (event.key === "j" || event.key === "k") {
        event.preventDefault();
        const next =
          rows[
            Math.max(
              0,
              Math.min(rows.length - 1, current + (event.key === "j" ? 1 : -1)),
            )
          ];
        if (next) {
          read(next);
          next.scrollIntoView({ block: "nearest" });
        }
      }
      if (event.key === "x" && current >= 0) {
        event.preventDefault();
        const box = rows[current].closest("article").querySelector("input");
        box.checked = !box.checked;
        box.dispatchEvent(new Event("change", { bubbles: true }));
      }
      if (event.key === "r" && current >= 0) {
        event.preventDefault();
        const url = new URL(rows[current].href);
        const id = url.pathname.split("/").pop();
        compose(
          `${url.origin}/dashboard/mail/accounts/${app.dataset.account}/compose?reply_id=${id}`,
        );
      }
      if (event.key === "Escape") closeReader();
    });
    window.addEventListener("popstate", () => {
      if (app.isConnected) navigate(location.href, { pop: true });
    });
    document.addEventListener("turbo:before-visit", (event) => {
      if (
        app.isConnected &&
        dirty &&
        !confirm(
          "Leave Mail? Save a draft first to keep your message and attachments.",
        )
      )
        event.preventDefault();
    });
    document.addEventListener("turbo:before-cache", () => {
      if (!app.isConnected) return;
      delete app.dataset.mounted;
      dock.hidden = true;
      dockFrame.removeAttribute("src");
    });
    window.addEventListener("beforeunload", (event) => {
      if (app.isConnected && dirty) {
        event.preventDefault();
        event.returnValue = "";
      }
    });
    app.querySelectorAll("dialog").forEach((dialog) =>
      dialog.addEventListener("close", () => {
        if (dialog.matches("[data-mail-preview-modal]"))
          dialog.querySelector("iframe").removeAttribute("src");
      }),
    );
  };
  window.LightekMailDesk = { mount };
  document.addEventListener("DOMContentLoaded", mount);
  document.addEventListener("turbo:load", mount);
  mount();
})();
