#!/usr/bin/env bash
# dymond_dispatch — the platform work layer ("the call center"), built CLEAN in
# one pass. Supersedes the earlier build_dispatch_core/rtm/add_scheduled scripts
# (those contained endless-setter syntax that breaks on Ruby 3.3).
#
# Everything baked in from the start:
#   - WorkItem (the "call") WITH run_at (scheduled work) from day one
#   - Queues (self-registering lanes)
#   - EngineAdapter + ActiveJobEngine (swappable base; honors run_at)
#   - Dispositions (completion callbacks — the "wrap-up")
#   - Dispatcher (submit/cancel/retry/snapshot)
#   - Bridge (optional-dependency shim; compute already calls this)
#   - PerformWorkItemJob (accepts .perform classes AND ActiveJob classes)
#   - RTM wallboard + engine with HELPER LOADING (the studio bug, pre-fixed)
#   - EditorRoutes with STATIC-BEFORE-DYNAMIC ordering (the studio/status bug)
#
# Run from ~/Desktop/Development (it creates the gem dir).
#   cd ~/Desktop/Development && bash build_dispatch.sh
set -uo pipefail

GEM="dymond_dispatch"
ROOT="$(pwd)/$GEM"
echo "==> Building $GEM at $ROOT"

if [ -d "$ROOT" ]; then
  echo "  !! $ROOT already exists. Move it aside or delete it first." >&2
  exit 1
fi

mkdir -p "$ROOT"/{lib/dymond_dispatch/engines,app/models/dymond_dispatch,app/jobs/dymond_dispatch,app/controllers/dymond_dispatch,app/helpers/dymond_dispatch,app/views/dymond_dispatch/rtm,db/migrate}
cd "$ROOT"

# ============================ gem skeleton ============================
cat > .gitignore <<'EOF'
*.gem
.bundle/
pkg/
Gemfile.lock
.DS_Store
EOF

cat > lib/dymond_dispatch/version.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  VERSION = "0.1.0"
end
RUBY

cat > dymond_dispatch.gemspec <<'RUBY'
# frozen_string_literal: true
require_relative "lib/dymond_dispatch/version"

Gem::Specification.new do |s|
  s.name        = "dymond_dispatch"
  s.version     = DymondDispatch::VERSION
  s.required_ruby_version = ">= 3.3.0"
  s.license     = "MIT"
  s.summary     = "dymond_dispatch — the LightekMCG platform work layer (call center + RTM)"
  s.description = "Work dispatch and real-time monitoring: WorkItems, queues, " \
                  "completion dispositions, and a wallboard. ActiveJob is today's " \
                  "engine, isolated behind an adapter so the base is swappable."
  s.authors     = ["Marlon Henry"]
  s.email       = ["marlon@lightekmcg.com"]
  s.homepage    = "https://github.com/lightekmcg/dymond_dispatch"

  s.files = Dir["{app,config,db,lib}/**/*", "README.md"]
  s.require_paths = ["lib"]

  s.add_dependency "rails", ">= 8.0"
end
RUBY

cat > Gemfile <<'EOF'
source "https://rubygems.org"
gemspec
EOF

cat > README.md <<'EOF'
# dymond_dispatch

The platform work layer — the "call center".

| call center      | platform                                   |
|------------------|--------------------------------------------|
| call             | `WorkItem` (handler, args, status, result) |
| lane / queue     | `Queues` (default, builds, media, system)  |
| agent            | worker running `PerformWorkItemJob`        |
| wrap-up          | `Dispositions` — who to update on completion |
| wallboard        | RTM at `/dashboard/dispatch`               |

Pragmatic sovereignty: ActiveJob is today's engine, isolated in
`Engines::ActiveJobEngine` behind `EngineAdapter`. Everything above it is
engine-agnostic. Swap later with `EngineAdapter.engine = MyEngine`.

## Submit work
```ruby
DymondDispatch.submit("DymondCompute::TranscodeHandler",
  args: [asset.id], queue: "media", priority: 4,
  dispositions: [
    { "kind" => "broadcast", "stream" => "dymond_dispatch:rtm", "on" => "any" }
  ])
```

A HANDLER is any class responding to `.perform(*args)` returning a Hash —
or an ActiveJob subclass (run inline by the worker).
EOF
echo "  [skeleton] gemspec, version, Gemfile, README"

# ============================ migration (run_at included) ============================
TS="$(date -u +%Y%m%d%H%M%S 2>/dev/null || ruby -e "puts Time.now.utc.strftime('%Y%m%d%H%M%S')")"
cat > "db/migrate/${TS}_create_dymond_dispatch_work_items.rb" <<'RUBY'
# frozen_string_literal: true
class CreateDymondDispatchWorkItems < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_dispatch_work_items do |t|
      t.string   :handler,  null: false            # class that performs the work
      t.jsonb    :args,     default: []
      t.string   :queue,    null: false, default: "default"
      t.integer  :priority, null: false, default: 5   # 1 (high) .. 9 (low)
      t.string   :status,   null: false, default: "queued"
      t.string   :worker_id                            # who picked it up
      t.jsonb    :dispositions, default: []            # completion callbacks
      t.jsonb    :result,   default: {}
      t.text     :error
      t.integer  :attempts, null: false, default: 0
      t.datetime :run_at                               # scheduled work (prayer times, etc.)
      t.datetime :enqueued_at
      t.datetime :started_at
      t.datetime :finished_at
      t.string   :tenant_key
      t.timestamps
    end
    add_index :dymond_dispatch_work_items, %i[status queue]
    add_index :dymond_dispatch_work_items, :enqueued_at
    add_index :dymond_dispatch_work_items, :run_at
    add_index :dymond_dispatch_work_items, :tenant_key
  end
end
RUBY
echo "  [core] migration (with run_at)"

# ============================ WorkItem ============================
cat > app/models/dymond_dispatch/work_item.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # A unit of work — the "call". Every long/async task in the platform becomes a
  # WorkItem: queued, picked up by a worker, worked, then it fires its
  # dispositions (who to update on completion). The RTM reads these live.
  class WorkItem < ActiveRecord::Base
    self.table_name = "dymond_dispatch_work_items"

    STATUSES = %w[queued working done failed cancelled].freeze

    validates :handler, :queue, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :queued,    -> { where(status: "queued") }
    scope :working,   -> { where(status: "working") }
    scope :finished,  -> { where(status: %w[done failed]) }
    scope :failed,    -> { where(status: "failed") }
    scope :active,    -> { where(status: %w[queued working]) }
    scope :scheduled, -> { where(status: "queued").where.not(run_at: nil) }
    scope :in_queue,  ->(q) { where(queue: q) }
    scope :recent,    -> { order(created_at: :desc) }

    def queued?
      status == "queued"
    end

    def working?
      status == "working"
    end

    def done?
      status == "done"
    end

    def failed?
      status == "failed"
    end

    def finished?
      done? || failed?
    end

    def scheduled?
      queued? && run_at.present?
    end

    def duration
      return nil unless started_at
      (finished_at || Time.current) - started_at
    end

    # --- state transitions (the only writers of status) ---
    def mark_working!(wid)
      update!(status: "working", worker_id: wid, started_at: Time.current,
              attempts: attempts + 1)
    end

    def mark_done!(res = {})
      update!(status: "done", result: res, finished_at: Time.current)
    end

    def mark_failed!(err)
      update!(status: "failed", error: err.to_s[0, 2000], finished_at: Time.current)
    end
  end
end
RUBY
echo "  [core] WorkItem"

# ============================ Queues ============================
cat > lib/dymond_dispatch/queues.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # Named lanes. Self-registering (dynamic collection — doctrine). A queue
  # declares its concurrency hint; handlers route to a lane at submit time
  # (skill-based routing, call-center style).
  class Queues
    Definition = Struct.new(:name, :concurrency, :description, keyword_init: true)

    @lanes = {}
    @mutex = Mutex.new

    class << self
      def register(name, concurrency: 1, description: nil)
        @mutex.synchronize do
          @lanes[name.to_s] = Definition.new(name: name.to_s,
                                             concurrency: concurrency,
                                             description: description)
        end
      end

      def all
        @lanes.values
      end

      def names
        @lanes.keys
      end

      def find(n)
        @lanes[n.to_s]
      end

      def exists?(n)
        @lanes.key?(n.to_s)
      end

      def clear
        @mutex.synchronize { @lanes = {} }
      end
    end

    # Sensible defaults; gems/hosts register their own.
    register "default", concurrency: 2, description: "General work"
    register "builds",  concurrency: 1, description: "Domain generation / codegen"
    register "media",   concurrency: 2, description: "Transcode / media pipeline"
    register "system",  concurrency: 1, description: "Scheduler / prayer / maintenance"
  end
end
RUBY
echo "  [core] Queues"

# ============================ Engine adapter (NO endless setter) ============================
cat > lib/dymond_dispatch/engine_adapter.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # The ENGINE is what actually runs work off the queue. Today: ActiveJob (proven
  # concurrency/retries). Tomorrow: our own dispatch engine. Everything above this
  # adapter (WorkItem, Queues, Dispositions, Dispatcher, RTM) is engine-agnostic —
  # that's the pragmatic sovereignty: own the layer, swap the base when it's worth it.
  module EngineAdapter
    module_function

    def engine
      @engine ||= Engines::ActiveJobEngine
    end

    # THE SWAP POINT. Note: a normal method body — `def engine=(e) = expr` is a
    # SyntaxError in Ruby 3.3 ("setter method cannot be defined in an endless
    # method definition").
    def engine=(new_engine)
      @engine = new_engine
    end

    # Hand a persisted WorkItem to the engine for execution.
    def dispatch(work_item)
      engine.dispatch(work_item)
    end

    def workers
      engine.respond_to?(:workers) ? engine.workers : []
    end
  end
end
RUBY

cat > lib/dymond_dispatch/engines/active_job_engine.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  module Engines
    # Wraps ActiveJob. The ONLY place that knows the underlying queue backend.
    # Honors run_at for scheduled work (wait_until).
    module ActiveJobEngine
      module_function

      def dispatch(work_item)
        opts = { queue: work_item.queue, priority: work_item.priority }
        opts[:wait_until] = work_item.run_at if work_item.run_at.present?
        DymondDispatch::PerformWorkItemJob.set(**opts).perform_later(work_item.id)
      end

      # ActiveJob doesn't uniformly expose worker liveness; the RTM derives
      # activity from in-flight WorkItems instead.
      def workers
        []
      end
    end
  end
end
RUBY
echo "  [core] EngineAdapter + ActiveJobEngine (honors run_at)"

# ============================ Dispositions (the wrap-up) ============================
cat > lib/dymond_dispatch/dispositions.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # "Who/what does this need to update on completion?" — the call-center wrap-up.
  # A disposition fires when a WorkItem finishes. Kinds are self-registering, so
  # new disposition types are drop-in (dynamic collection — doctrine).
  #
  #   { "kind" => "enqueue",   "handler" => "SomeJob", "args" => [...], "on" => "done" }
  #   { "kind" => "touch",     "model" => "DymondCompute::Asset", "id" => 3, "on" => "any" }
  #   { "kind" => "update",    "model" => "X", "id" => 1, "attributes" => {...}, "on" => "done" }
  #   { "kind" => "broadcast", "stream" => "dymond_dispatch:rtm", "on" => "any" }
  #   { "kind" => "webhook",   "url" => "https://...", "on" => "failed" }
  module Dispositions
    @kinds = {}

    class << self
      def register(kind, &blk)
        @kinds[kind.to_s] = blk
      end

      def kinds
        @kinds.keys
      end

      def handler_for(kind)
        @kinds[kind.to_s]
      end

      # Fire all dispositions matching the finished state.
      def fire!(work_item)
        state = work_item.status # done | failed
        Array(work_item.dispositions).each do |spec|
          on = (spec["on"] || "done").to_s
          next unless on == "any" || on == state

          h = handler_for(spec["kind"])
          next unless h

          begin
            h.call(work_item, spec)
          rescue StandardError => e
            Rails.logger.warn "[dispatch] disposition #{spec['kind']} failed: #{e.message}"
          end
        end
      end
    end

    # ---- built-in kinds ----
    register("enqueue") do |_wi, spec|
      klass = spec["handler"].to_s.safe_constantize
      klass&.perform_later(*Array(spec["args"]))
    end

    register("touch") do |_wi, spec|
      model = spec["model"].to_s.safe_constantize
      model&.find_by(id: spec["id"])&.touch
    end

    register("update") do |_wi, spec|
      model = spec["model"].to_s.safe_constantize
      model&.find_by(id: spec["id"])&.update(spec["attributes"] || {})
    end

    register("broadcast") do |wi, spec|
      if defined?(ActionCable)
        ActionCable.server.broadcast(
          spec["stream"] || "dymond_dispatch:rtm",
          { id: wi.id, handler: wi.handler, status: wi.status, queue: wi.queue }
        )
      end
    end

    register("webhook") do |wi, spec|
      if defined?(DymondDispatch::WebhookJob)
        DymondDispatch::WebhookJob.perform_later(spec["url"], { id: wi.id, status: wi.status })
      end
    end
  end
end
RUBY
echo "  [core] Dispositions"

# ============================ Dispatcher ============================
cat > lib/dymond_dispatch/dispatcher.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # The floor supervisor. Callers submit work here; the dispatcher records the
  # WorkItem and hands it to the engine. Supports immediate AND scheduled work
  # (run_at) — prayer appointments ride this.
  module Dispatcher
    module_function

    def submit(handler, args: [], queue: "default", priority: 5,
               dispositions: [], tenant: nil, run_at: nil)
      q = Queues.exists?(queue) ? queue.to_s : "default"
      wi = WorkItem.create!(
        handler: handler.to_s, args: Array(args), queue: q, priority: priority.to_i,
        dispositions: Array(dispositions), tenant_key: tenant,
        status: "queued", enqueued_at: Time.current, run_at: run_at
      )
      EngineAdapter.dispatch(wi)
      wi
    end

    def cancel(work_item_id)
      wi = WorkItem.find_by(id: work_item_id)
      return nil unless wi&.queued?
      wi.update!(status: "cancelled", finished_at: Time.current)
      wi
    end

    def retry(work_item_id)
      wi = WorkItem.find_by(id: work_item_id)
      return nil unless wi&.failed?
      wi.update!(status: "queued", error: nil, finished_at: nil,
                 enqueued_at: Time.current, run_at: nil)
      EngineAdapter.dispatch(wi)
      wi
    end

    # ---- RTM reads (dynamic collections) ----
    def snapshot
      {
        queues: Queues.all.map do |lane|
          {
            name: lane.name, concurrency: lane.concurrency,
            queued:  WorkItem.queued.in_queue(lane.name).count,
            working: WorkItem.working.in_queue(lane.name).count
          }
        end,
        active:    WorkItem.active.recent.limit(25).map { |w| item_json(w) },
        recent:    WorkItem.finished.recent.limit(25).map { |w| item_json(w) },
        scheduled: WorkItem.scheduled.order(:run_at).limit(15).map { |w| item_json(w) },
        totals: {
          queued:  WorkItem.queued.count,
          working: WorkItem.working.count,
          done_today:   WorkItem.where(status: "done").where("finished_at > ?", Time.current.beginning_of_day).count,
          failed_today: WorkItem.failed.where("finished_at > ?", Time.current.beginning_of_day).count
        }
      }
    end

    def item_json(w)
      {
        id: w.id, handler: w.handler, queue: w.queue, status: w.status,
        priority: w.priority, worker: w.worker_id, attempts: w.attempts,
        duration: w.duration&.round(1), error: w.error&.slice(0, 140),
        run_at: w.run_at, enqueued_at: w.enqueued_at, finished_at: w.finished_at
      }
    end
  end

  module_function

  def submit(*args, **kw)
    Dispatcher.submit(*args, **kw)
  end

  def snapshot
    Dispatcher.snapshot
  end
end
RUBY
echo "  [core] Dispatcher (submit/cancel/retry/snapshot, run_at)"

# ============================ Bridge (compute already calls this) ============================
cat > lib/dymond_dispatch/bridge.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # Lets a gem route work through dispatch WHEN PRESENT, and fall back to plain
  # ActiveJob when it isn't. This is why dymond_compute does NOT depend on
  # dymond_dispatch — its TranscodeDispatch checks defined?(DymondDispatch::Bridge)
  # and routes accordingly. Installing this gem flips transcodes onto the
  # wallboard with no code change upstream.
  module Bridge
    module_function

    def available?
      defined?(DymondDispatch::Dispatcher) ? true : false
    end

    def submit_or_enqueue(handler:, job: nil, args: [], queue: "default",
                          priority: 5, dispositions: [], tenant: nil, run_at: nil)
      if available?
        DymondDispatch::Dispatcher.submit(handler, args: args, queue: queue,
                                          priority: priority, dispositions: dispositions,
                                          tenant: tenant, run_at: run_at)
      elsif job
        run_at ? job.set(wait_until: run_at).perform_later(*args) : job.perform_later(*args)
      end
    end
  end
end
RUBY
echo "  [core] Bridge"

# ============================ the worker (dual contract) ============================
cat > app/jobs/dymond_dispatch/perform_work_item_job.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # The agent taking the call. Accepts TWO handler contracts:
  #   1. a plain class responding to .perform(*args) -> result
  #   2. an ActiveJob subclass -> executed inline via perform_now
  # (2) lets existing ActiveJob classes — e.g. prayer-appointed jobs — be
  # dispatched without rewriting them. One worker, one WorkItem, one status.
  class PerformWorkItemJob < ActiveJob::Base
    queue_as :default

    def perform(work_item_id)
      wi = WorkItem.find_by(id: work_item_id)
      return unless wi&.queued?

      wi.mark_working!(worker_id)
      begin
        result = invoke(wi)
        wi.mark_done!(result.is_a?(Hash) ? result : { value: result.to_s })
      rescue StandardError => e
        wi.mark_failed!("#{e.class}: #{e.message}")
      end

      Dispositions.fire!(wi)
      wi
    end

    private

    def invoke(wi)
      klass = wi.handler.to_s.safe_constantize
      raise "unknown handler #{wi.handler}" if klass.nil?

      args = Array(wi.args)
      if klass.respond_to?(:perform)
        klass.perform(*args)
      elsif defined?(ActiveJob::Base) && klass < ActiveJob::Base
        klass.perform_now(*args)
      else
        raise "handler #{wi.handler} must respond to .perform or be an ActiveJob"
      end
    end

    def worker_id
      @worker_id ||= begin
        require "socket"
        "#{Socket.gethostname}:#{Process.pid}:#{Thread.current.object_id}"
      rescue StandardError
        "worker:#{Process.pid}"
      end
    end
  end
end
RUBY
echo "  [core] PerformWorkItemJob (dual contract)"

# ============================ helper ============================
cat > app/helpers/dymond_dispatch/dispatch_helper.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  module DispatchHelper
    BADGE = "display:inline-block;padding:2px 9px;border-radius:12px;font-size:10px;" \
            "font-weight:600;text-transform:uppercase;letter-spacing:.4px;" \
            "min-width:58px;text-align:center;"

    def dispatch_status_style(status)
      colors = {
        "queued"    => "background:rgba(255,255,255,.08);color:#aaa;",
        "working"   => "background:rgba(245,180,60,.15);color:#f5b43c;",
        "done"      => "background:rgba(60,200,120,.15);color:#3cc878;",
        "failed"    => "background:rgba(245,80,60,.15);color:#f5503c;",
        "cancelled" => "background:rgba(255,255,255,.05);color:#666;"
      }
      BADGE + colors[status.to_s].to_s
    end
  end
end
RUBY

# ============================ RTM controller ============================
cat > app/controllers/dymond_dispatch/rtm_controller.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # The wallboard. index renders the floor; snapshot serves live JSON for polling.
  class RtmController < ::DymondDash::ApplicationController
    def index
      @snapshot = DymondDispatch::Dispatcher.snapshot
    end

    def snapshot
      render json: DymondDispatch::Dispatcher.snapshot
    end

    def retry_item
      DymondDispatch::Dispatcher.retry(params[:id])
      redirect_to dymond_dash.dispatch_rtm_path, notice: "Requeued."
    end

    def cancel_item
      DymondDispatch::Dispatcher.cancel(params[:id])
      redirect_to dymond_dash.dispatch_rtm_path, notice: "Cancelled."
    end
  end
end
RUBY
echo "  [rtm] helper + controller"

# ============================ RTM views ============================
cat > app/views/dymond_dispatch/rtm/index.html.erb <<'ERB'
<% content_for :page_title, "Dispatch" %>
<%
  card = "background:var(--dd-card-bg,#16181f);border:1px solid var(--dd-border);border-radius:12px;"
%>
<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;">
  <h2 style="font-size:20px;font-weight:700;margin:0;">Dispatch</h2>
  <span id="rtm-pulse" style="font-size:11px;color:var(--dd-text-muted);transition:opacity .2s;">live</span>
</div>
<p style="color:var(--dd-text-secondary);font-size:13px;margin-bottom:20px;">
  The work floor. Every async task in the platform &mdash; domain builds, transcodes,
  prayer-scheduled jobs &mdash; routes through here.
</p>

<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:20px;">
  <% { queued: "Queued", working: "Working", done_today: "Done today", failed_today: "Failed today" }.each do |k, label| %>
    <div style="<%= card %>padding:16px;text-align:center;">
      <div id="rtm-total-<%= k %>" style="font-size:26px;font-weight:700;"><%= @snapshot[:totals][k] %></div>
      <div style="font-size:11px;color:var(--dd-text-muted);text-transform:uppercase;letter-spacing:.5px;"><%= label %></div>
    </div>
  <% end %>
</div>

<div style="<%= card %>padding:18px;margin-bottom:20px;">
  <div style="font-size:13px;font-weight:600;margin-bottom:12px;">Queues</div>
  <div id="rtm-queues" style="display:grid;gap:10px;">
    <% @snapshot[:queues].each do |q| %>
      <div class="rtm-queue" data-name="<%= q[:name] %>" style="display:flex;align-items:center;gap:12px;font-size:13px;">
        <span style="min-width:90px;font-weight:600;"><%= q[:name] %></span>
        <span style="color:var(--dd-text-muted);font-size:11px;">&times;<%= q[:concurrency] %></span>
        <span class="q-working" style="color:#f5b43c;"><%= q[:working] %> working</span>
        <span class="q-queued" style="color:var(--dd-text-secondary);"><%= q[:queued] %> queued</span>
      </div>
    <% end %>
  </div>
</div>

<div style="<%= card %>padding:18px;margin-bottom:20px;">
  <div style="font-size:13px;font-weight:600;margin-bottom:12px;">In flight</div>
  <%= render "items", items: @snapshot[:active] %>
</div>

<% if @snapshot[:scheduled].present? %>
  <div style="<%= card %>padding:18px;margin-bottom:20px;">
    <div style="font-size:13px;font-weight:600;margin-bottom:12px;">Scheduled</div>
    <%= render "items", items: @snapshot[:scheduled] %>
  </div>
<% end %>

<div style="<%= card %>padding:18px;">
  <div style="font-size:13px;font-weight:600;margin-bottom:12px;">Recent</div>
  <%= render "items", items: @snapshot[:recent] %>
</div>

<%= render "poll" %>
ERB

cat > app/views/dymond_dispatch/rtm/_items.html.erb <<'ERB'
<% if items.blank? %>
  <div style="font-size:12px;color:var(--dd-text-muted);">Nothing here.</div>
<% else %>
  <div style="display:grid;gap:8px;">
    <% items.each do |i| %>
      <div style="display:flex;align-items:center;gap:12px;font-size:12px;padding:8px 10px;background:rgba(255,255,255,.03);border-radius:8px;">
        <span style="<%= dispatch_status_style(i[:status]) %>"><%= i[:status] %></span>
        <span style="font-weight:600;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"><%= i[:handler] %></span>
        <span style="color:var(--dd-text-muted);"><%= i[:queue] %></span>
        <% if i[:run_at] %>
          <span style="color:var(--dd-text-muted);"><%= i[:run_at].strftime("%-I:%M %p") rescue i[:run_at] %></span>
        <% end %>
        <% if i[:duration] %><span style="color:var(--dd-text-muted);"><%= i[:duration] %>s</span><% end %>
        <% if i[:status] == "failed" %>
          <%= button_to "Retry", dymond_dash.dispatch_rtm_retry_path(i[:id]), method: :post,
                form: { style: "display:inline;margin:0;" },
                style: "background:rgba(255,255,255,.08);color:var(--dd-text-primary);border:none;border-radius:6px;padding:4px 10px;font-size:11px;cursor:pointer;" %>
        <% elsif i[:status] == "queued" %>
          <%= button_to "Cancel", dymond_dash.dispatch_rtm_cancel_path(i[:id]), method: :post,
                form: { style: "display:inline;margin:0;" },
                style: "background:none;color:var(--dd-text-muted);border:none;font-size:11px;cursor:pointer;" %>
        <% end %>
      </div>
      <% if i[:error].present? %>
        <div style="font-size:11px;color:#f5503c;padding:0 10px 6px;"><%= i[:error] %></div>
      <% end %>
    <% end %>
  </div>
<% end %>
ERB

cat > app/views/dymond_dispatch/rtm/_poll.html.erb <<'ERB'
<script>
(function(){
  var url = "<%= dymond_dash.dispatch_rtm_snapshot_path %>";
  var pulse = document.getElementById("rtm-pulse");
  function tick(){
    fetch(url, { headers: { "Accept": "application/json" } })
      .then(function(r){ return r.json(); })
      .then(function(d){
        ["queued","working","done_today","failed_today"].forEach(function(k){
          var el = document.getElementById("rtm-total-" + k);
          if (el && d.totals) el.textContent = d.totals[k];
        });
        (d.queues || []).forEach(function(q){
          var row = document.querySelector('.rtm-queue[data-name="' + q.name + '"]');
          if (!row) return;
          row.querySelector(".q-working").textContent = q.working + " working";
          row.querySelector(".q-queued").textContent  = q.queued + " queued";
        });
        if (pulse) { pulse.style.opacity = "1"; setTimeout(function(){ pulse.style.opacity = ".35"; }, 200); }
      })
      .catch(function(){})
      .finally(function(){ setTimeout(tick, 3000); });
  }
  tick();
})();
</script>
ERB
echo "  [rtm] views (wallboard, items, poll)"

# ============================ editor routes (STATIC BEFORE DYNAMIC) ============================
cat > lib/dymond_dispatch/editor_routes.rb <<'RUBY'
# frozen_string_literal: true
module DymondDispatch
  # Registers the RTM routes with dymond_dash's EditorRoutes registry (drawn
  # under /dashboard).
  #
  # ORDER MATTERS. Rails routing is first-match-wins and these are drawn in
  # registration order: every STATIC path must precede any DYNAMIC (":id") path
  # that could swallow it. ("dispatch/:id" first would match "/dispatch/snapshot"
  # with id="snapshot".) Static first, ":id" last.
  module EditorRoutesRegistration
    module_function

    def register!
      return unless defined?(DymondDash::EditorRoutes)

      r = DymondDash::EditorRoutes
      c = "dymond_dispatch/rtm"

      # --- STATIC ---
      r.register(path: "dispatch",          to: "#{c}#index",    as: "dispatch_rtm",          verb: :get)
      r.register(path: "dispatch/snapshot", to: "#{c}#snapshot", as: "dispatch_rtm_snapshot", verb: :get)

      # --- DYNAMIC (":id" last) ---
      r.register(path: "dispatch/:id/retry",  to: "#{c}#retry_item",  as: "dispatch_rtm_retry",  verb: :post)
      r.register(path: "dispatch/:id/cancel", to: "#{c}#cancel_item", as: "dispatch_rtm_cancel", verb: :post)
    end
  end
end
RUBY
echo "  [rtm] editor routes (static before dynamic)"

# ============================ engine (WITH helper loading) ============================
cat > lib/dymond_dispatch/engine.rb <<'RUBY'
# frozen_string_literal: true
require "rails/engine"

module DymondDispatch
  class Engine < ::Rails::Engine
    isolate_namespace DymondDispatch

    # Load THIS gem's helpers into ALL controllers.
    #
    # Required because RtmController inherits from DymondDash::ApplicationController
    # (a DIFFERENT gem's controller), so isolate_namespace's normal helper wiring
    # doesn't reach it. Attaching at action_controller_base makes dispatch_status_style
    # available wherever the wallboard renders.
    #
    # Engine.helpers returns a single MODULE containing every helper the engine
    # defines — pass it straight to `helper`. NEVER call .each on it (Module, not Array).
    initializer "dymond_dispatch.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper DymondDispatch::Engine.helpers
      end
    end

    # Register RTM routes with dymond_dash BEFORE routes are drawn.
    initializer "dymond_dispatch.register_editor_routes", before: :add_routing_paths do
      require "dymond_dispatch/editor_routes"
      DymondDispatch::EditorRoutesRegistration.register!
    end

    # Migrations run in place (no install:migrations copy).
    initializer "dymond_dispatch.append_migrations" do |app|
      unless app.root.to_s == root.to_s
        config.paths["db/migrate"].expanded.each { |p| app.config.paths["db/migrate"] << p }
      end
    end
  end
end
RUBY

# ============================ main lib ============================
cat > lib/dymond_dispatch.rb <<'RUBY'
# frozen_string_literal: true
#
# dymond_dispatch — the LightekMCG platform work layer (the "call center").
#
#   call        -> WorkItem
#   lane        -> Queues
#   agent       -> PerformWorkItemJob
#   wrap-up     -> Dispositions (who to update on completion)
#   wallboard   -> RTM at /dashboard/dispatch
#
# Pragmatic sovereignty: ActiveJob is today's engine, isolated behind
# EngineAdapter. Everything above it is engine-agnostic — swap the base later
# with DymondDispatch::EngineAdapter.engine = MyEngine.

require "dymond_dispatch/version"
require "dymond_dispatch/queues"
require "dymond_dispatch/engines/active_job_engine"
require "dymond_dispatch/engine_adapter"
require "dymond_dispatch/dispositions"
require "dymond_dispatch/dispatcher"
require "dymond_dispatch/bridge"
require "dymond_dispatch/engine" if defined?(Rails::Engine)

module DymondDispatch
end
RUBY
echo "  [gem] engine + lib/dymond_dispatch.rb"

# ============================ git ============================
git init -q 2>/dev/null || true
git add -A 2>/dev/null || true
git commit -q -m "dymond_dispatch: work layer + RTM wallboard" 2>/dev/null || true
git branch -M main 2>/dev/null || true
git remote add origin "git@github.com:lightekmcg/dymond_dispatch.git" 2>/dev/null || true

cat <<'EOF'

==================================================================
BUILT. Now wire it up:
==================================================================

1) CREATE THE REPO on GitHub: lightekmcg/dymond_dispatch, then:
     cd ~/Desktop/Development/dymond_dispatch
     git push -u origin main

2) HOST Gemfile — dymond_dispatch MUST load BEFORE dymond_dash
   (dash's RTM controller + the Development section reference it):

     gem "dymond_dispatch", git: "git@github.com:lightekmcg/dymond_dispatch.git", branch: "main"
     gem "dymond_dash",     git: "..."   # <- after dispatch

3) MOUNT the engine (host config/routes.rb) — the RTM lives under /dashboard,
   which dymond_dash owns, so NO separate mount is needed. EditorRoutes handles it.

4) bundle install && rails db:migrate && rails s

5) VERIFY:
     bin/rails runner 'p DymondDispatch::Queues.names'
     # => ["default", "builds", "media", "system"]
     open http://localhost:3000/dashboard/dispatch

6) THE PAYOFF — transcodes now route through dispatch automatically.
   dymond_compute's TranscodeDispatch already checks defined?(DymondDispatch::Bridge).
   Upload a video and watch it appear on the wallboard, media queue, with a
   completion disposition. ZERO changes to compute. That's the Bridge working.

==================================================================
VERIFY THE RUBY BEFORE BUNDLING
==================================================================
  cd ~/Desktop/Development/dymond_dispatch
  for f in $(find lib app -name '*.rb'); do ruby -c "$f" >/dev/null || echo "SYNTAX: $f"; done
  echo "syntax check done"
EOF
