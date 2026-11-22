export function previewOptions(asset, layer, fps) {
  return { source_revision: asset.source_revision, fps, action_name: layer.action || undefined, pose_frame: layer.pose_frame };
}

export class ModelPreviews {
  constructor(request, changed) {
    Object.assign(this, { request, changed, entries: new Map() });
  }

  get(asset, layer, fps) {
    if (!asset?.preview_request_url) return;
    const options = previewOptions(asset, layer, fps);
    const key = JSON.stringify([asset.id, options]);
    if (!this.entries.has(key)) {
      const url = new URL(asset.preview_request_url, location.href);
      for (const [name, value] of Object.entries(options)) {
        if (value !== undefined) url.searchParams.set(name, value);
      }
      const entry = { key, url: url.href, options, preview_status: "loading" };
      this.entries.set(key, entry);
      this.fetch(entry);
    }
    return this.entries.get(key);
  }

  async fetch(entry, submit = false) {
    if (entry.pending) return;
    entry.pending = true;
    try {
      const options = submit ? { method: "POST", body: entry.options, timeout: 15000 } : { timeout: 15000 };
      Object.assign(entry, await this.request(entry.url, options));
      if (entry.preview_status === "queued") setTimeout(() => this.fetch(entry), 2500);
    } catch {
      entry.preview_status = "failed";
    } finally {
      entry.pending = false;
      this.changed();
    }
  }

  build(entry) {
    if (entry.pending || entry.preview_status === "queued" || entry.preview_status === "ready") return;
    entry.preview_status = "queued";
    this.changed();
    return this.fetch(entry, true);
  }
}
