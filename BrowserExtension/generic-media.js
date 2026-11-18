(() => {
  if (globalThis.__renotchGenericMediaInstalled) return;
  globalThis.__renotchGenericMediaInstalled = true;

  // YouTube has a dedicated script with richer info; skip it here.
  const host = location.hostname.toLowerCase();
  if (host === "www.youtube.com" || host === "m.youtube.com" || host === "youtube.com") return;

  const sessionID = crypto.randomUUID();
  let lastFingerprint = "";

  function activeElement() {
    return [...document.querySelectorAll("audio, video")].find(
      (el) => !el.paused && !el.ended && el.duration > 0
    );
  }

  function mediaState() {
    const meta = navigator.mediaSession?.metadata;
    const state = navigator.mediaSession?.playbackState;
    const el = activeElement();

    const isPlaying = state === "playing" || (!!el && !el.paused && !el.ended);
    const title = meta?.title || (el ? document.title : "");

    return {
      isPlaying,
      title,
      artist: meta?.artist || "",
      album: meta?.album || "",
      artworkURL: meta?.artwork?.[0]?.src || "",
      position: el ? el.currentTime : 0,
      duration: el ? el.duration : 0,
    };
  }

  function emit(force = false) {
    const s = mediaState();
    if (!s.isPlaying && !s.title) {
      if (lastFingerprint !== "none") {
        lastFingerprint = "none";
        chrome.runtime.sendMessage({ kind: "media", action: "clear", sessionID });
      }
      return;
    }

    const fingerprint = `${s.isPlaying}|${s.title}|${s.artist}`;
    if (fingerprint === lastFingerprint && !force) return;
    lastFingerprint = fingerprint;

    chrome.runtime.sendMessage({
      kind: "media",
      action: "update",
      sessionID,
      title: s.title || "Media",
      channel: s.artist || host.replace(/^www\./, ""),
      url: location.href,
      thumbnailURL: s.artworkURL || "",
      isPlaying: s.isPlaying,
      position: Math.round(s.position),
      duration: Math.round(s.duration),
    });
  }

  document.addEventListener("play", () => emit(), true);
  document.addEventListener("pause", () => emit(), true);
  document.addEventListener("ended", () => emit(), true);
  window.addEventListener("pagehide", () => {
    chrome.runtime.sendMessage({ kind: "media", action: "clear", sessionID });
  });

  // Heartbeat every 2s so the app never expires the media session.
  setInterval(() => emit(true), 2000);
  emit();
})();
