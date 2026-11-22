const active = item => item.status !== "completed" && item.status !== "failed";
const transient = error => error.status == null || error.status === 408 || error.status === 429 || error.status >= 500;

export class RenderRequests {
  constructor({ request, historyUrl, stateChanged, historyChanged, accepted, setTimer = (callback, delay) => setTimeout(callback, delay),
    clearTimer = timer => clearTimeout(timer), requestId = () => crypto.randomUUID() }) {
    Object.assign(this, { request, historyUrl, stateChanged, historyChanged, accepted, setTimer, clearTimer, requestId });
    this.generation = 0;
    this.failures = 0;
    this.submitting = false;
    this.activeRender = null;
    this.statusError = null;
  }

  get locked() { return this.submitting || !!this.activeRender; }

  async refresh() {
    this.clearTimer(this.timer);
    const generation = ++this.generation;
    try {
      const items = await this.request(this.historyUrl, { timeout: 15000 });
      if (generation !== this.generation) return;
      this.activeRender = items.find(active) ?? null;
      this.statusError = null;
      this.failures = 0;
      this.historyChanged(items);
      this.stateChanged();
      if (this.activeRender) this.timer = this.setTimer(() => this.refresh(), 2200);
    } catch (error) {
      if (generation !== this.generation) return;
      const retrying = transient(error);
      this.statusError = retrying ? "Render status temporarily unavailable. Reconnecting…" : error.message;
      this.stateChanged();
      if (retrying) {
        const delay = Math.min(30000, 2200 * 2 ** Math.min(this.failures++, 4));
        this.timer = this.setTimer(() => this.refresh(), delay);
      }
    }
  }

  async submit(url, prepare) {
    if (this.locked) return;
    this.submitting = true;
    this.stateChanged();
    try {
      const body = await prepare();
      const key = JSON.stringify([url, body]);
      if (this.pending?.key !== key) this.pending = { key, id: this.requestId() };
      let render;
      try {
        render = await this.request(url, { method: "POST", timeout: 15000,
          body: { ...body, request_id: this.pending.id } });
      } catch (error) {
        if (!transient(error)) this.pending = null;
        this.refresh();
        throw error;
      }
      this.pending = null;
      this.activeRender = active(render) ? render : null;
      this.accepted(render);
      this.refresh();
    } finally {
      this.submitting = false;
      this.stateChanged();
    }
  }
}
