(function () {
  "use strict";

  const params = new URLSearchParams(window.location.search);
  const noteId = params.get("id");

  const editor = document.getElementById("editor");
  const previewPane = document.getElementById("pane-preview");
  const editPane = document.getElementById("pane-edit");
  const tabEdit = document.getElementById("tab-edit");
  const tabPreview = document.getElementById("tab-preview");
  const statusEl = document.getElementById("status");
  const titleEl = document.getElementById("note-title");

  let saveTimer = null;
  let lastSavedAt = null;
  let savedTickerTimer = null;
  let serverTitle = "";
  let noteDeleted = false;
  let serverDisconnected = false;

  // Reads/writes against the contenteditable node go through these two
  // helpers so future iterations can layer syntax-aware visual styling
  // on top without touching the rest of the editor.
  function getContent() {
    return editor.innerText;
  }

  function setContent(value) {
    editor.textContent = value;
  }

  function setStatus(text) {
    statusEl.textContent = text;
  }

  function extractTitleFromContent(text) {
    const match = text.match(/^[ \t]*#[ \t]+(.+?)[ \t]*$/m);
    return match ? match[1].trim() : "";
  }

  function refreshTitle() {
    const fromContent = extractTitleFromContent(getContent());
    const resolved = fromContent || serverTitle || "Untitled";
    titleEl.textContent = resolved;
    document.title = `${resolved} — Arcmark`;
  }

  function updateSavedTicker() {
    if (!lastSavedAt) return;
    const seconds = Math.max(0, Math.round((Date.now() - lastSavedAt) / 1000));
    if (seconds < 5) {
      setStatus("saved");
    } else if (seconds < 60) {
      setStatus(`saved · ${seconds}s ago`);
    } else {
      const minutes = Math.round(seconds / 60);
      setStatus(`saved · ${minutes}m ago`);
    }
  }

  function scheduleSavedTicker() {
    if (savedTickerTimer) clearInterval(savedTickerTimer);
    savedTickerTimer = setInterval(updateSavedTicker, 5000);
  }

  function stopSavedTicker() {
    if (savedTickerTimer) {
      clearInterval(savedTickerTimer);
      savedTickerTimer = null;
    }
  }

  function enterDeletedState() {
    if (noteDeleted) return;
    noteDeleted = true;
    stopSavedTicker();
    if (saveTimer) {
      clearTimeout(saveTimer);
      saveTimer = null;
    }
    document.body.classList.add("note-deleted");
    editor.setAttribute("contenteditable", "false");

    const main = document.querySelector("main.content");
    if (main) {
      main.innerHTML = "";
      const card = document.createElement("div");
      card.className = "empty-state";
      const heading = document.createElement("h2");
      heading.textContent = "Note no longer available";
      const blurb = document.createElement("p");
      blurb.textContent = "This note was deleted in Arcmark. You can close this tab.";
      card.appendChild(heading);
      card.appendChild(blurb);
      main.appendChild(card);
    }
    setStatus("deleted");
    document.title = "Deleted note — Arcmark";
  }

  function enterDisconnectedState() {
    if (serverDisconnected) return;
    serverDisconnected = true;
    stopSavedTicker();
    if (saveTimer) {
      clearTimeout(saveTimer);
      saveTimer = null;
    }
    document.body.classList.add("server-disconnected");
    editor.setAttribute("contenteditable", "false");

    const main = document.querySelector("main.content");
    if (main) {
      main.innerHTML = "";
      const card = document.createElement("div");
      card.className = "empty-state";
      const heading = document.createElement("h2");
      heading.textContent = "Editor disconnected";
      const blurb = document.createElement("p");
      blurb.textContent = "Arcmark restarted, so this tab can no longer reach the editor. Reopen this note from Arcmark to continue editing.";
      card.appendChild(heading);
      card.appendChild(blurb);
      main.appendChild(card);
    }
    setStatus("disconnected");
    document.title = "Disconnected — Arcmark";
  }

  async function loadNote() {
    if (!noteId) {
      setStatus("missing note id");
      return;
    }
    try {
      const response = await fetch(`/api/notes/${noteId}`, {
        cache: "no-store"
      });
      if (response.status === 404) {
        enterDeletedState();
        return;
      }
      if (!response.ok) {
        setStatus(`load failed (${response.status})`);
        return;
      }
      const data = await response.json();
      setContent(data.content || "");
      serverTitle = data.title || "";
      refreshTitle();
      lastSavedAt = Date.now();
      setStatus("saved");
      scheduleSavedTicker();
    } catch (err) {
      enterDisconnectedState();
    }
  }

  async function saveNote() {
    if (!noteId || noteDeleted || serverDisconnected) return;
    setStatus("saving…");
    try {
      const response = await fetch(`/api/notes/${noteId}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: getContent() }),
        cache: "no-store"
      });
      if (response.status === 404) {
        enterDeletedState();
        return;
      }
      if (!response.ok) {
        stopSavedTicker();
        setStatus(`save failed (${response.status})`);
        return;
      }
      lastSavedAt = Date.now();
      setStatus("saved");
      scheduleSavedTicker();
    } catch (err) {
      enterDisconnectedState();
    }
  }

  function scheduleSave() {
    if (noteDeleted || serverDisconnected) return;
    if (saveTimer) clearTimeout(saveTimer);
    setStatus("editing…");
    saveTimer = setTimeout(saveNote, 500);
  }

  function showEdit() {
    editPane.hidden = false;
    previewPane.hidden = true;
    tabEdit.classList.add("active");
    tabPreview.classList.remove("active");
    tabEdit.setAttribute("aria-selected", "true");
    tabPreview.setAttribute("aria-selected", "false");
  }

  function showPreview() {
    const rendered = window.marked && window.DOMPurify
      ? window.DOMPurify.sanitize(window.marked.parse(getContent()))
      : "";
    previewPane.innerHTML = rendered;
    editPane.hidden = true;
    previewPane.hidden = false;
    tabEdit.classList.remove("active");
    tabPreview.classList.add("active");
    tabEdit.setAttribute("aria-selected", "false");
    tabPreview.setAttribute("aria-selected", "true");
  }

  // Belt-and-braces: even though contenteditable="plaintext-only" tells
  // Safari/Chrome to ignore rich content, we force pastes through plain
  // text so any future user paste from a rich source stays as markdown.
  editor.addEventListener("paste", function (event) {
    event.preventDefault();
    const text = (event.clipboardData || window.clipboardData).getData("text/plain");
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) return;
    const range = selection.getRangeAt(0);
    range.deleteContents();
    range.insertNode(document.createTextNode(text));
    range.collapse(false);
    selection.removeAllRanges();
    selection.addRange(range);
    scheduleSave();
  });

  editor.addEventListener("input", function () {
    refreshTitle();
    scheduleSave();
  });

  tabEdit.addEventListener("click", showEdit);
  tabPreview.addEventListener("click", showPreview);

  // Render shortcut hints in the tab buttons. macOS users see ⌘, others Ctrl.
  const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || "");
  const modifierLabel = isMac ? "⌘" : "Ctrl+";
  document.querySelectorAll(".shortcut").forEach(function (el) {
    el.textContent = modifierLabel + el.dataset.key;
  });

  // Cmd+E (macOS) / Ctrl+E (Windows/Linux) → Edit, Cmd/Ctrl+L → Preview.
  document.addEventListener("keydown", function (event) {
    if (!(event.metaKey || event.ctrlKey)) return;
    if (event.shiftKey || event.altKey) return;
    const key = event.key.toLowerCase();
    if (key === "e") {
      event.preventDefault();
      showEdit();
      editor.focus();
    } else if (key === "l") {
      event.preventDefault();
      showPreview();
    }
  });

  loadNote();
})();
