#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/susu_signup_invites_mail_${STAMP}"
mkdir -p "$BACKUP"

for f in config/routes.rb config/environments/production.rb app/controllers/susu_memberships_controller.rb app/models/susu_group.rb app/views/layouts/susu_public.html.erb app/views/susu_public/home.html.erb app/views/susu_public/onboarding.html.erb; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

mkdir -p app/controllers app/models app/mailers app/views/susu_registrations app/views/susu_invitation_mailer db/migrate lib/tasks

MIGRATION="db/migrate/${STAMP}_create_susu_invitations.rb"
cat > "$MIGRATION" <<'RUBY'
class CreateSusuInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :susu_invitations do |t|
      t.references :susu_group, null: false, foreign_key: true
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :email_address, null: false
      t.integer :payout_position, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :accepted_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :susu_invitations, [:susu_group_id, :email_address], unique: true, name: "idx_susu_invites_group_email"
    add_index :susu_invitations, :status
    add_index :susu_invitations, :expires_at
  end
end
RUBY

cat > app/models/susu_invitation.rb <<'RUBY'
class SusuInvitation < ApplicationRecord
  STATUSES = %w[pending accepted cancelled expired].freeze
  belongs_to :susu_group
  belongs_to :inviter, class_name: "User"

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :payout_position, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :expires_at, presence: true

  scope :pending, -> { where(status: "pending") }

  def expired? = expires_at <= Time.current

  def accept_for!(user)
    raise ArgumentError, "Invitation has expired" if expired?
    raise ArgumentError, "Invitation email does not match this account" unless user.email_address.casecmp?(email_address)

    transaction do
      membership = susu_group.susu_memberships.find_or_create_by!(user: user) do |record|
        record.payout_position = payout_position
      end
      user.grant_feature!(:susu, source: "susu_invitation") if user.respond_to?(:grant_feature!)
      update!(status: "accepted", accepted_at: Time.current)
      membership
    end
  end

  def invitation_token
    signed_id(purpose: :susu_invitation, expires_in: 14.days)
  end

  def self.find_by_invitation_token!(token)
    find_signed!(token, purpose: :susu_invitation)
  end
end
RUBY

cat > app/controllers/susu_registrations_controller.rb <<'RUBY'
class SusuRegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    @invitation = invitation_from_params
    @user = User.new(email_address: @invitation&.email_address)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    @invitation = nil
    @user = User.new
  end

  def create
    @invitation = invitation_from_params
    @user = User.new(registration_params.merge(role: "client"))

    User.transaction do
      @user.save!
      @user.grant_feature!(:susu, source: @invitation ? "susu_invitation_signup" : "susu_public_signup")
      @invitation&.accept_for!(@user)
    end

    start_new_session_for(@user)
    redirect_to(@invitation ? susu_group_path(@invitation.susu_group) : new_susu_group_path,
                notice: @invitation ? "Account created and invitation accepted." : "Welcome to Susu.")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    @user ||= User.new
    @user.errors.add(:base, e.message) if @user.errors.empty?
    render :new, status: :unprocessable_entity
  end

  private

  def invitation_from_params
    return unless params[:invite].present?
    SusuInvitation.find_by_invitation_token!(params[:invite])
  end

  def registration_params
    params.require(:user).permit(:first_name, :last_name, :email_address, :phone, :password, :password_confirmation)
  end
end
RUBY

cat > app/controllers/susu_invitations_controller.rb <<'RUBY'
class SusuInvitationsController < ApplicationController
  allow_unauthenticated_access only: :accept

  def accept
    invitation = SusuInvitation.find_by_invitation_token!(params[:token])

    if invitation.expired?
      redirect_to susu_path, alert: "This Susu invitation has expired."
    elsif authenticated?
      invitation.accept_for!(current_user)
      redirect_to susu_group_path(invitation.susu_group), notice: "You joined #{invitation.susu_group.name}."
    else
      redirect_to susu_signup_path(invite: params[:token])
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to susu_path, alert: "That Susu invitation is invalid or has expired."
  rescue ArgumentError => e
    redirect_to susu_path, alert: e.message
  end
end
RUBY

cat > app/mailers/susu_invitation_mailer.rb <<'RUBY'
class SusuInvitationMailer < ApplicationMailer
  def invite
    @invitation = params.fetch(:invitation)
    @group = @invitation.susu_group
    @inviter = @invitation.inviter
    @invite_url = accept_susu_invitation_url(token: @invitation.invitation_token)

    mail(
      to: @invitation.email_address,
      from: ENV.fetch("MAIL_FROM", "Susu by Lightek <susu@lightekmcg.com>"),
      subject: "#{@inviter.full_name} invited you to join #{@group.name}"
    )
  end
end
RUBY

cat > app/views/susu_invitation_mailer/invite.html.erb <<'ERB'
<h1>You’ve been invited to a Susu</h1>
<p><strong><%= @inviter.full_name %></strong> invited you to join <strong><%= @group.name %></strong> on Susu by Lightek.</p>
<p>Contribution: <strong><%= number_to_currency(@group.contribution_amount) %></strong> · <%= @group.cycle_frequency.humanize %></p>
<p><%= link_to "Accept invitation and join", @invite_url %></p>
ERB

cat > app/views/susu_invitation_mailer/invite.text.erb <<'ERB'
You’ve been invited to a Susu

<%= @inviter.full_name %> invited you to join <%= @group.name %> on Susu by Lightek.
Contribution: <%= number_to_currency(@group.contribution_amount) %>
Schedule: <%= @group.cycle_frequency.humanize %>

Accept invitation:
<%= @invite_url %>
ERB

cat > app/views/susu_registrations/new.html.erb <<'ERB'
<% content_for :title, "Create your Susu account" %>
<main>
  <section class="page-hero">
    <div class="eyebrow">SUSU ACCOUNT</div>
    <h1><%= @invitation ? "Join #{@invitation.susu_group.name}" : "Create your Susu account" %></h1>
    <p>This signup creates a client account with Susu access only.</p>
  </section>

  <section class="section onboarding" style="max-width:680px">
    <% if @user.errors.any? %>
      <div class="pricing-card" style="margin-bottom:18px"><strong><%= @user.errors.full_messages.to_sentence %></strong></div>
    <% end %>

    <%= form_with model: @user, url: susu_signup_path do |form| %>
      <%= hidden_field_tag :invite, params[:invite] if params[:invite].present? %>
      <div class="pricing-card">
        <p><%= form.label :first_name %><br><%= form.text_field :first_name, required: true %></p>
        <p><%= form.label :last_name %><br><%= form.text_field :last_name, required: true %></p>
        <p><%= form.label :email_address, "Email" %><br><%= form.email_field :email_address, required: true %></p>
        <p><%= form.label :phone %><br><%= form.telephone_field :phone %></p>
        <p><%= form.label :password %><br><%= form.password_field :password, required: true %></p>
        <p><%= form.label :password_confirmation %><br><%= form.password_field :password_confirmation, required: true %></p>
        <%= form.submit(@invitation ? "Create account and join Susu" : "Create Susu account", class: "btn btn-primary btn-large") %>
      </div>
    <% end %>

    <p style="margin-top:18px">Already have an account? <%= link_to "Sign in", new_session_path %>.</p>
  </section>
</main>
ERB

python3 <<'PY'
from pathlib import Path

path = Path("app/controllers/susu_memberships_controller.rb")
src = path.read_text()
old = '''    unless user
      redirect_to @susu_group,
                  alert: "No Lightek account exists for #{email}. Account invitations are the next onboarding step."
      return
    end
'''
new = '''    unless user
      pending_count = @susu_group.susu_invitations.pending.count
      if @susu_group.members.count + pending_count >= @susu_group.target_member_count
        redirect_to @susu_group, alert: "This Susu already has enough members or pending invitations."
        return
      end

      invitation = @susu_group.susu_invitations.find_or_initialize_by(email_address: email)
      invitation.assign_attributes(
        inviter: current_user,
        payout_position: @susu_group.next_payout_position + pending_count,
        status: "pending",
        expires_at: 14.days.from_now
      )
      invitation.save!
      SusuInvitationMailer.with(invitation: invitation).invite.deliver_later

      redirect_to @susu_group, notice: "Invitation sent to #{email}."
      return
    end
'''
if old not in src:
    raise SystemExit("ERROR: expected missing-user invitation block not found")
path.write_text(src.replace(old, new, 1))
PY

python3 <<'PY'
from pathlib import Path
path = Path("app/models/susu_group.rb")
src = path.read_text()
if "has_many :susu_invitations" not in src:
    anchor = '  belongs_to :organizer, class_name: "User"\n'
    if anchor not in src:
        raise SystemExit("ERROR: SusuGroup anchor not found")
    src = src.replace(anchor, anchor + '  has_many :susu_invitations, dependent: :destroy\n\n', 1)
    path.write_text(src)
PY

python3 <<'PY'
from pathlib import Path
path = Path("config/routes.rb")
src = path.read_text()
if 'as: :susu_signup' not in src:
    block = '''get  "/susu/signup", to: "susu_registrations#new", as: :susu_signup
post "/susu/signup", to: "susu_registrations#create"
get  "/susu/invitations/:token/accept", to: "susu_invitations#accept", as: :accept_susu_invitation

'''
    marker = '# ── Susu public product surface'
    if marker not in src:
        raise SystemExit("ERROR: Susu public route marker not found")
    src = src.replace(marker, block + marker, 1)
    path.write_text(src)
PY

python3 <<'PY'
from pathlib import Path
for file in ["app/views/layouts/susu_public.html.erb","app/views/susu_public/home.html.erb","app/views/susu_public/onboarding.html.erb"]:
    path = Path(file)
    if not path.exists():
        continue
    src = path.read_text().replace("new_susu_group_path", "susu_signup_path")
    path.write_text(src)
PY

python3 <<'PY'
from pathlib import Path
path = Path("config/environments/production.rb")
src = path.read_text()
marker = "# SUSU SMTP CONFIGURATION"
if marker not in src:
    idx = src.rfind("\nend")
    if idx < 0:
        raise SystemExit("ERROR: production.rb final end not found")
    block = '''
  # SUSU SMTP CONFIGURATION
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address: ENV.fetch("SMTP_ADDRESS"),
      port: ENV.fetch("SMTP_PORT", "587").to_i,
      domain: ENV.fetch("SMTP_DOMAIN", "lightekmcg.com"),
      user_name: ENV["SMTP_USERNAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain"),
      enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true"
    }
    config.action_mailer.default_url_options = {
      host: ENV.fetch("APP_HOST", "lightekmcg.com"),
      protocol: ENV.fetch("APP_PROTOCOL", "https")
    }
  end
'''
    path.write_text(src[:idx] + "\n" + block + src[idx:])
PY

cat > lib/tasks/susu_mail.rake <<'RUBY'
namespace :susu do
  task mail_readiness: :environment do
    puts "=== SUSU MAIL READINESS ==="
    puts "SMTP address:    #{ENV["SMTP_ADDRESS"].present? ? "PRESENT" : "MISSING"}"
    puts "SMTP username:   #{ENV["SMTP_USERNAME"].present? ? "PRESENT" : "MISSING"}"
    puts "SMTP password:   #{ENV["SMTP_PASSWORD"].present? ? "PRESENT" : "MISSING"}"
    puts "Mail from:       #{ENV.fetch("MAIL_FROM", "Susu by Lightek <susu@lightekmcg.com>")}"
    puts "Delivery method: #{ActionMailer::Base.delivery_method}"
    puts "Pending invites: #{SusuInvitation.pending.count}"
  end
end
RUBY

echo "=== SYNTAX ==="
for f in "$MIGRATION" app/models/susu_invitation.rb app/controllers/susu_registrations_controller.rb app/controllers/susu_invitations_controller.rb app/mailers/susu_invitation_mailer.rb app/controllers/susu_memberships_controller.rb app/models/susu_group.rb lib/tasks/susu_mail.rake config/routes.rb config/environments/production.rb; do
  ruby -c "$f"
done

echo "=== MIGRATE ==="
bin/rails db:migrate

echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo "=== ROUTES ==="
bin/rails routes | grep -E 'susu_signup|accept_susu_invitation'

echo "=== MAIL READINESS ==="
bin/rails susu:mail_readiness

echo "=== DIFF CHECK ==="
git diff --check

echo "=== STATUS ==="
git status --short

echo "DONE"
echo "Backup: $BACKUP"
