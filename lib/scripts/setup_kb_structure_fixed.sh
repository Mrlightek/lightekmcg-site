#!/bin/bash
set -e
cd ~/Desktop/Development/dymond_kb
mkdir -p db/migrate app/models/dymond_kb app/controllers/dymond_kb app/views/dymond_kb/kb_dashboard lib/dymond_kb

echo "Writing migrations..."
cd ~/Desktop/Development/dymond_kb

echo "Writing migrations..."
TS1=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS1}_create_dymond_kb_topics.rb" << 'EOF'
# frozen_string_literal: true
class CreateDymondKbTopics < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_kb_topics do |t|
      t.string  :name,        null: false
      t.string  :topic_id,    null: false  # stable slug, e.g. "start", "modules"
      t.string  :icon
      t.string  :color
      t.text    :description
      t.integer :sort_order,  default: 0
      t.timestamps
    end
    add_index :dymond_kb_topics, :topic_id, unique: true
  end
end
EOF
sleep 1
TS2=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS2}_create_dymond_kb_articles.rb" << 'EOF'
# frozen_string_literal: true
class CreateDymondKbArticles < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_kb_articles do |t|
      t.references :topic, null: false, foreign_key: { to_table: :dymond_kb_topics }
      t.string  :article_id,   null: false  # stable slug, e.g. "start-overview"
      t.string  :title,        null: false
      t.string  :article_type, null: false, default: "guide" # guide | reference | troubleshooting
      t.text    :excerpt
      t.text    :body
      t.integer :read_minutes, default: 5
      t.boolean :featured,     default: false, null: false
      t.integer :sort_order,   default: 0
      t.timestamps
    end
    add_index :dymond_kb_articles, :article_id, unique: true
    add_index :dymond_kb_articles, :featured
  end
end
EOF

echo "Writing models..."
mkdir -p app/models/dymond_kb
cat > app/models/dymond_kb/topic.rb << 'EOF'
# frozen_string_literal: true
module DymondKb
  class Topic < ApplicationRecord
    self.table_name = "dymond_kb_topics"

    has_many :articles, class_name: "DymondKb::Article", foreign_key: :topic_id, dependent: :destroy, inverse_of: :topic

    validates :name, :topic_id, presence: true
    validates :topic_id, uniqueness: true

    scope :ordered, -> { order(:sort_order, :name) }

    def article_count
      articles.count
    end
  end
end
EOF

cat > app/models/dymond_kb/article.rb << 'EOF'
# frozen_string_literal: true
module DymondKb
  class Article < ApplicationRecord
    self.table_name = "dymond_kb_articles"

    TYPES = %w[guide reference troubleshooting].freeze

    belongs_to :topic, class_name: "DymondKb::Topic"

    validates :title, :article_id, presence: true
    validates :article_id, uniqueness: true
    validates :article_type, inclusion: { in: TYPES }

    scope :featured, -> { where(featured: true) }
    scope :ordered, -> { order(:sort_order, :title) }
    scope :search, ->(q) {
      where("title ILIKE :q OR excerpt ILIKE :q OR body ILIKE :q", q: "%#{q}%")
    }

    def type_label
      article_type.upcase
    end
  end
end
EOF

echo ""
echo "Stage 1 done. Run 'bin/rails db:migrate' from lightekmcg-site after all stages complete."
cd ~/Desktop/Development/dymond_kb

echo "Writing public KbController..."
cat > app/controllers/dymond_kb/kb_controller.rb << 'EOF'
# frozen_string_literal: true
module DymondKb
  class KbController < ::DymondSite::ApplicationController
    def index
      @topics = DymondKb::Topic.ordered
      @featured = DymondKb::Article.featured.includes(:topic).ordered
      @recent = DymondKb::Article.includes(:topic).order(updated_at: :desc).limit(6)
    end

    def topic
      @topic = DymondKb::Topic.find_by!(topic_id: params[:id])
      @articles = @topic.articles.ordered
    end

    def article
      @article = DymondKb::Article.find_by!(article_id: params[:id])
      @topic = @article.topic
    end

    def search
      @query = params[:q].to_s.strip
      @results = @query.present? ? DymondKb::Article.search(@query).includes(:topic).ordered : []
    end
  end
end
EOF

echo "Writing admin KbDashboardController..."
cat > app/controllers/dymond_kb/kb_dashboard_controller.rb << 'EOF'
# frozen_string_literal: true
module DymondKb
  class KbDashboardController < ::DymondDash::ApplicationController
    def index
      @topics = DymondKb::Topic.ordered
      @articles = DymondKb::Article.includes(:topic).ordered
    end

    # ── Topics ──
    def new_topic
      @topic = DymondKb::Topic.new
    end

    def create_topic
      @topic = DymondKb::Topic.new(topic_params)
      if @topic.save
        redirect_to dymond_dash.kb_dashboard_path, notice: "Topic created."
      else
        render :new_topic, status: :unprocessable_entity
      end
    end

    def edit_topic
      @topic = DymondKb::Topic.find(params[:id])
    end

    def update_topic
      @topic = DymondKb::Topic.find(params[:id])
      if @topic.update(topic_params)
        redirect_to dymond_dash.kb_dashboard_path, notice: "Topic updated."
      else
        render :edit_topic, status: :unprocessable_entity
      end
    end

    def destroy_topic
      DymondKb::Topic.find(params[:id]).destroy
      redirect_to dymond_dash.kb_dashboard_path, notice: "Topic removed."
    end

    # ── Articles ──
    def new_article
      @article = DymondKb::Article.new
      @topics = DymondKb::Topic.ordered
    end

    def create_article
      @article = DymondKb::Article.new(article_params)
      if @article.save
        redirect_to dymond_dash.kb_dashboard_path, notice: "Article created."
      else
        @topics = DymondKb::Topic.ordered
        render :new_article, status: :unprocessable_entity
      end
    end

    def edit_article
      @article = DymondKb::Article.find(params[:id])
      @topics = DymondKb::Topic.ordered
    end

    def update_article
      @article = DymondKb::Article.find(params[:id])
      if @article.update(article_params)
        redirect_to dymond_dash.kb_dashboard_path, notice: "Article updated."
      else
        @topics = DymondKb::Topic.ordered
        render :edit_article, status: :unprocessable_entity
      end
    end

    def destroy_article
      DymondKb::Article.find(params[:id]).destroy
      redirect_to dymond_dash.kb_dashboard_path, notice: "Article removed."
    end

    private

    def topic_params
      params.require(:topic).permit(:name, :topic_id, :icon, :color, :description, :sort_order)
    end

    def article_params
      params.require(:article).permit(:topic_id, :article_id, :title, :article_type,
                                       :excerpt, :body, :read_minutes, :featured, :sort_order)
    end
  end
end
EOF

echo "Writing routes..."
cat > config/routes.rb << 'EOF'
# frozen_string_literal: true
DymondKb::Engine.routes.draw do
  root to: "kb#index"
  get "search", to: "kb#search", as: :search
  get "topic/:id", to: "kb#topic", as: :topic
  get "article/:id", to: "kb#article", as: :article
end
EOF

echo "Writing editor_routes.rb (admin CRUD routes, drawn under /dashboard)..."
cat > lib/dymond_kb/editor_routes.rb << 'EOF'
# frozen_string_literal: true
module DymondKb
  module EditorRoutesRegistration
    module_function
    def register!
      return unless defined?(DymondDash::EditorRoutes)
      c = "dymond_kb/kb_dashboard"
      DymondDash::EditorRoutes.register(path: "kb",                        to: "#{c}#index",         as: "kb_dashboard",       verb: :get)
      DymondDash::EditorRoutes.register(path: "kb/topics/new",             to: "#{c}#new_topic",     as: "new_kb_topic",       verb: :get)
      DymondDash::EditorRoutes.register(path: "kb/topics",                 to: "#{c}#create_topic",  as: "kb_topics",          verb: :post)
      DymondDash::EditorRoutes.register(path: "kb/topics/:id/edit",        to: "#{c}#edit_topic",    as: "edit_kb_topic",      verb: :get)
      DymondDash::EditorRoutes.register(path: "kb/topics/:id",             to: "#{c}#update_topic",  as: "kb_topic",           verb: :patch)
      DymondDash::EditorRoutes.register(path: "kb/topics/:id",             to: "#{c}#destroy_topic",  as: "destroy_kb_topic",   verb: :delete)
      DymondDash::EditorRoutes.register(path: "kb/articles/new",           to: "#{c}#new_article",   as: "new_kb_article",     verb: :get)
      DymondDash::EditorRoutes.register(path: "kb/articles",               to: "#{c}#create_article", as: "kb_articles",       verb: :post)
      DymondDash::EditorRoutes.register(path: "kb/articles/:id/edit",      to: "#{c}#edit_article",  as: "edit_kb_article",    verb: :get)
      DymondDash::EditorRoutes.register(path: "kb/articles/:id",           to: "#{c}#update_article", as: "kb_article",        verb: :patch)
      DymondDash::EditorRoutes.register(path: "kb/articles/:id",           to: "#{c}#destroy_article", as: "destroy_kb_article", verb: :delete)
    end
  end
end
EOF

echo "Stage 2 done."
cd ~/Desktop/Development/dymond_kb

echo "Writing admin views..."
mkdir -p app/views/dymond_kb/kb_dashboard

cat > app/views/dymond_kb/kb_dashboard/index.html.erb << 'EOF'
<% content_for :page_title, "Knowledge Base" %>
<% content_for :topbar_actions do %>
  <%= link_to "New Topic", dymond_dash.new_kb_topic_path, class: "dd-topbar-btn dd-btn-ghost" %>
  <%= link_to "New Article", dymond_dash.new_kb_article_path, class: "dd-topbar-btn dd-btn-primary" %>
<% end %>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Topics</div>
  <% @topics.each do |t| %>
    <div style="display:flex; align-items:center; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--dd-border);">
      <span><%= t.icon %> <%= t.name %> <span style="color:var(--dd-text-muted); font-size:12px;">· <%= t.article_count %> articles</span></span>
      <div style="display:flex; gap:8px;">
        <%= link_to "Edit", dymond_dash.edit_kb_topic_path(t), class: "dd-topbar-btn dd-btn-ghost" %>
        <%= button_to "Delete", dymond_dash.destroy_kb_topic_path(t), method: :delete,
              form: { data: { turbo_confirm: "Remove #{t.name}? Articles inside will be deleted too." } }, class: "dd-topbar-btn dd-btn-ghost" %>
      </div>
    </div>
  <% end %>
</div>

<div class="dd-card">
  <div class="dd-card-title">Articles</div>
  <% @articles.each do |a| %>
    <div style="display:flex; align-items:center; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--dd-border);">
      <span><%= a.title %> <span style="color:var(--dd-text-muted); font-size:12px;">· <%= a.topic.name %> · <%= a.type_label %><%= " · FEATURED" if a.featured %></span></span>
      <div style="display:flex; gap:8px;">
        <%= link_to "Edit", dymond_dash.edit_kb_article_path(a), class: "dd-topbar-btn dd-btn-ghost" %>
        <%= button_to "Delete", dymond_dash.destroy_kb_article_path(a), method: :delete,
              form: { data: { turbo_confirm: "Remove this article?" } }, class: "dd-topbar-btn dd-btn-ghost" %>
      </div>
    </div>
  <% end %>
</div>
EOF

cat > app/views/dymond_kb/kb_dashboard/_topic_form.html.erb << 'EOF'
<%= form_with model: @topic, url: (@topic.persisted? ? dymond_dash.kb_topic_path(@topic) : dymond_dash.kb_topics_path) do |f| %>
  <div class="dd-card" style="display:flex; flex-direction:column; gap:12px; max-width:500px;">
    <label>Name <%= f.text_field :name, class: "fg-input" %></label>
    <label>Topic ID (slug, e.g. "start") <%= f.text_field :topic_id, class: "fg-input" %></label>
    <label>Icon (emoji) <%= f.text_field :icon, class: "fg-input" %></label>
    <label>Color (hex) <%= f.text_field :color, class: "fg-input" %></label>
    <label>Description <%= f.text_area :description, class: "fg-input" %></label>
    <label>Sort Order <%= f.number_field :sort_order, class: "fg-input" %></label>
    <%= f.submit class: "dd-topbar-btn dd-btn-primary" %>
  </div>
<% end %>
EOF

cat > app/views/dymond_kb/kb_dashboard/new_topic.html.erb << 'EOF'
<% content_for :page_title, "New Topic" %>
<%= render "topic_form" %>
EOF

cat > app/views/dymond_kb/kb_dashboard/edit_topic.html.erb << 'EOF'
<% content_for :page_title, "Edit #{@topic.name}" %>
<%= render "topic_form" %>
EOF

cat > app/views/dymond_kb/kb_dashboard/_article_form.html.erb << 'EOF'
<%= form_with model: @article, url: (@article.persisted? ? dymond_dash.kb_article_path(@article) : dymond_dash.kb_articles_path) do |f| %>
  <div class="dd-card" style="display:flex; flex-direction:column; gap:12px; max-width:700px;">
    <label>Topic
      <%= f.collection_select :topic_id, @topics, :id, :name, {}, class: "fg-input" %>
    </label>
    <label>Article ID (slug, e.g. "start-overview") <%= f.text_field :article_id, class: "fg-input" %></label>
    <label>Title <%= f.text_field :title, class: "fg-input" %></label>
    <label>Type
      <%= f.select :article_type, DymondKb::Article::TYPES.map { |t| [t.humanize, t] }, {}, class: "fg-input" %>
    </label>
    <label>Excerpt <%= f.text_area :excerpt, rows: 2, class: "fg-input" %></label>
    <label>Body <%= f.text_area :body, rows: 12, class: "fg-input" %></label>
    <label>Read time (minutes) <%= f.number_field :read_minutes, class: "fg-input" %></label>
    <label><%= f.check_box :featured %> Featured</label>
    <label>Sort Order <%= f.number_field :sort_order, class: "fg-input" %></label>
    <%= f.submit class: "dd-topbar-btn dd-btn-primary" %>
  </div>
<% end %>
EOF

cat > app/views/dymond_kb/kb_dashboard/new_article.html.erb << 'EOF'
<% content_for :page_title, "New Article" %>
<%= render "article_form" %>
EOF

cat > app/views/dymond_kb/kb_dashboard/edit_article.html.erb << 'EOF'
<% content_for :page_title, "Edit Article" %>
<%= render "article_form" %>
EOF

echo "Registering nav item..."
cat > ~/Desktop/Development/lightekmcg-site/config/initializers/kb_nav.rb << 'EOF'
# frozen_string_literal: true
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :kb; f.label = "Knowledge Base"; f.icon = "book"
    f.gem_source = "kb"; f.nav_section = :platform; f.min_plan = :starter
    f.nav_items = [{ label: "Knowledge Base", icon: "book", path: "dymond_dash.kb_dashboard_path" }]
  end
rescue StandardError => e
  Rails.logger.warn "[KB] nav registration skipped: #{e.message}"
end
EOF

echo "Stage 3 done."
cd ~/Desktop/Development/dymond_kb

echo "Adding section-parsing and related-articles helpers to Article model..."
cat > app/models/dymond_kb/article.rb << 'EOF'
# frozen_string_literal: true
module DymondKb
  class Article < ApplicationRecord
    self.table_name = "dymond_kb_articles"

    TYPES = %w[guide reference troubleshooting].freeze

    belongs_to :topic, class_name: "DymondKb::Topic"

    validates :title, :article_id, presence: true
    validates :article_id, uniqueness: true
    validates :article_type, inclusion: { in: TYPES }

    scope :featured, -> { where(featured: true) }
    scope :ordered, -> { order(:sort_order, :title) }
    scope :search, ->(q) {
      where("title ILIKE :q OR excerpt ILIKE :q OR body ILIKE :q", q: "%#{q}%")
    }

    def type_label
      article_type.upcase
    end

    # "## Heading" lines in body become the on-page nav — no separate column
    # needed, the body is the single source of truth for its own structure.
    def sections
      body.to_s.scan(/^##\s+(.+)$/).flatten.presence || ["Overview"]
    end

    # Up to 3 other articles in the same topic — a sensible default rather
    # than hand-curating explicit relations for 46 articles.
    def related_articles
      topic.articles.where.not(id: id).ordered.limit(3)
    end

    def read_label
      "#{read_minutes} min"
    end

    def updated_label
      updated_at.strftime("%b %-d")
    end
  end
end
EOF

echo "Writing the real KbController#index (single action, all data as JSON)..."
cat > app/controllers/dymond_kb/kb_controller.rb << 'EOF'
# frozen_string_literal: true
module DymondKb
  class KbController < ::DymondSite::ApplicationController
    def index
      @topics = DymondKb::Topic.ordered.includes(:articles)
      @articles = DymondKb::Article.ordered.includes(:topic)
    end
  end
end
EOF

echo "Stage 4 done."
