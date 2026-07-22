#!/bin/bash
set -e
cd ~/Desktop/Development/lightekmcg-site

echo "Writing expanded Marlon::TicketCategories..."
cat > app/models/marlon/ticket_categories.rb << 'RUBY_CATS_EOF'
# frozen_string_literal: true
module Marlon
  # Fixed taxonomy — structural, not admin-managed data (same reasoning as
  # DymondDispatch::Dispositions' registered kinds). Backs both the employee
  # queue and the real public ticket hub/tracker design.
  module TicketCategories
    ALL = {
      "deployment" => {
        label: "Deployment", icon: "🚀", color: "#C030F8", stripe: "#9820C8",
        sla_hours: 2, team: "Deployment Team", default_rep: "@darius.m",
        desc: "Issues with your live instance, module configuration, onboarding steps, or technical setup.",
        examples: ["Module not loading or timing out", "Custom domain or SSL certificate issue", "New module integration not connecting", "Instance performance or latency problems", "Go-live blocker during onboarding"],
        tips: ["Include your instance URL and the specific module affected", "Share any error messages or console output if available", "Note whether this is a new issue or a regression", "Include your approximate go-live date if on onboarding"],
        teams: [{ avatar: "🔧", name: "@darius.m", role: "LEAD · DEPLOYMENT", status: "green" }, { avatar: "⚡", name: "@tech-malik", role: "INFRA · TECHNICAL", status: "green" }]
      },
      "billing" => {
        label: "Billing", icon: "💳", color: "#10A8D8", stripe: "#0878A8",
        sla_hours: 24, team: "Finance Team", default_rep: "@finance-jen",
        desc: "Questions about invoices, commission statements, payment methods, contract terms, or subscription changes.",
        examples: ["Invoice dispute or billing error", "Commission statement discrepancy", "Payment method update", "Module subscription change — add or remove", "Contract term clarification"],
        tips: ["Attach the relevant invoice or commission statement PDF", "Include the specific line item or transaction in question", "Reference your Lightek reseller ID (LT-DIST-XXXXXX)", "For commission disputes, include the period and deal reference"],
        teams: [{ avatar: "📊", name: "@finance-jen", role: "LEAD · BILLING", status: "green" }, { avatar: "💰", name: "@accounts-mo", role: "ACCOUNTS · AR", status: "away" }]
      },
      "compliance" => {
        label: "Compliance", icon: "⚖️", color: "#E03050", stripe: "#C01030",
        sla_hours: 1, team: "Compliance Team", default_rep: "@compliance-rox",
        desc: "Constitutional violations, Ministry Engine protocol issues, Article I–VIII concerns, or citation violations on your deployment.",
        examples: ["Suspected Article VI attribution violation", "Ministry Engine protocol not activating", "Article VIII access denial for citizen", "Constitutional concern about a deployment config", "Violation registry dispute or appeal"],
        tips: ["Constitutional violations are treated as PRIORITY HIGH by default", "Include specific Article and clause reference (e.g. Art. VI §6.2)", "Document the violation with screenshots or logs if possible", "Compliance tickets trigger automatic review — do not delay filing", "Citizens affected should be documented if known"],
        teams: [{ avatar: "⚖️", name: "@compliance-rox", role: "LEAD · COMPLIANCE", status: "green" }, { avatar: "🏛", name: "@ministry-eng", role: "MINISTRY ENGINE", status: "green" }]
      },
      "onboarding" => {
        label: "Onboarding", icon: "🎯", color: "#18B878", stripe: "#108058",
        sla_hours: 4, team: "Onboarding Team", default_rep: "@onboard-kia",
        desc: "Help with your 90-day onboarding process, white-label setup, citizen migration, or initial configuration.",
        examples: ["White-label branding not applying correctly", "Citizen bulk import assistance needed", "Onboarding milestone blocked", "Custom domain propagation issue", "First deployment configuration walkthrough"],
        tips: ["Include your onboarding tracker milestone (Day X of 90)", "Attach your brand assets if the issue is branding-related", "Reference your dedicated onboarding rep if you have one", "Onboarding tickets get same-day response during business hours"],
        teams: [{ avatar: "🎯", name: "@onboard-kia", role: "LEAD · ONBOARDING", status: "green" }, { avatar: "🎨", name: "@brand-dev", role: "WHITE LABEL · DESIGN", status: "green" }]
      },
      "training" => {
        label: "Training", icon: "📚", color: "#708800", stripe: "#506800",
        sla_hours: 48, team: "Training Team", default_rep: "@training-mo",
        desc: "Request training sessions, certification support, Lightek Institute access, or documentation for your team.",
        examples: ["Schedule a platform training session", "Certification exam — request access", "Technical documentation request", "Team onboarding training for new staff", "Custom training for your specific module set"],
        tips: ["Include the number of team members needing training", "Specify which modules the training should cover", "Training sessions are typically scheduled 3–5 business days out", "Certification exams are taken via the Lightek Institute portal"],
        teams: [{ avatar: "📚", name: "@training-mo", role: "LEAD · TRAINING", status: "green" }, { avatar: "🎓", name: "@cert-dev", role: "CERTIFICATION", status: "away" }]
      },
      "technical" => {
        label: "Technical", icon: "🔧", color: "#7030A8", stripe: "#502080",
        sla_hours: 4, team: "Technical Team", default_rep: "@tech-malik",
        desc: "API integration issues, webhook configuration, module-to-module connection problems, or developer-level technical requests.",
        examples: ["API endpoint returning unexpected response", "Webhook not triggering on expected event", "Module-to-module integration broken", "Custom domain SSL certificate renewal", "Rate limiting or authentication issue"],
        tips: ["Include the API endpoint, request payload, and response received", "Share relevant code snippets if the issue is in integration code", "Note your SDK version and programming language", "Technical tickets may require a screenshare session — note your availability"],
        teams: [{ avatar: "🔧", name: "@tech-malik", role: "LEAD · TECHNICAL", status: "green" }, { avatar: "🖥️", name: "@api-dev", role: "API · INTEGRATION", status: "green" }]
      }
    }.freeze

    module_function

    def ids = ALL.keys
    def for(id) = ALL[id.to_s]
    def label_for(id) = ALL.dig(id.to_s, :label) || id.to_s.humanize
    def sla_label(id)
      h = ALL.dig(id.to_s, :sla_hours)
      return nil unless h
      h < 24 ? "#{h}h" : "#{h / 24}d"
    end
  end
end
RUBY_CATS_EOF

echo "Writing real SupportsController..."
cat > app/controllers/supports_controller.rb << 'RUBY_CTRL_EOF'
# frozen_string_literal: true
# The real public ticket hub — replaces the generic Rails scaffold. Talks
# directly to Marlon::Ticket; the old Support model is left untouched/unused.
class SupportsController < ApplicationController
  layout false  # full standalone page (own <html>/<head>), same as store/catalog.

  PRIORITY_ABBR = { "low" => "LOW", "medium" => "MED", "high" => "HIGH", "critical" => "CRIT" }.freeze
  STATUS_MAP    = { "open" => "open", "in_progress" => "progress", "resolved" => "resolved" }.freeze

  def index
    @categories = Marlon::TicketCategories::ALL
    tickets     = Marlon::Ticket.where(submitted_by: current_user).open_first.limit(20)
    @my_tickets_json = tickets.map { |t| ticket_to_hub_json(t) }
  end

  def create
    ticket = Marlon::Ticket.new(ticket_params)
    ticket.submitted_by = current_user
    ticket.organization_name ||= current_user&.full_name

    if ticket.save
      ticket.log!(action: "Ticket submitted", actor: current_user)
      render json: { ok: true, number: ticket.number, id: ticket.id }
    else
      render json: { ok: false, error: ticket.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def reply
    ticket = Marlon::Ticket.find(params[:id])
    ticket.log!(action: "#{current_user.full_name} replied", detail: params[:detail], actor: current_user)
    render json: { ok: true }
  end

  private

  def ticket_params
    params.require(:ticket).permit(:category, :title, :description, :priority, :urgency,
                                    :organization_name, :reseller_id).tap do |p|
      p[:extra_fields] = { "notes" => params.dig(:ticket, :extra_notes) }.compact if params.dig(:ticket, :extra_notes).present?
    end
  end

  def ticket_to_hub_json(ticket)
    meta = ticket.category_meta || {}
    {
      id: ticket.id,
      num: ticket.number,
      cat: ticket.category,
      subject: ticket.title,
      status: STATUS_MAP[ticket.status] || ticket.status,
      time: relative_time(ticket.created_at),
      priority: PRIORITY_ABBR[ticket.priority] || ticket.priority.upcase,
      events: ticket.events.order(:created_at).map { |e| event_to_hub_json(e, meta[:color]) }
    }
  end

  def event_to_hub_json(event, category_color)
    action = event.action.to_s.downcase
    dot = if action.include?("resolved") || action.include?("assigned")
            "#18C870"
          else
            category_color || "#00B4CC"
          end
    { time: event.created_at.strftime("%l:%M %p").strip, dot: dot, action: event.action, detail: event.detail.to_s }
  end

  def relative_time(t)
    diff = Time.current - t
    if diff < 1.hour   then "#{[(diff / 60).round, 1].max}m ago"
    elsif diff < 1.day then "#{(diff / 3600).round}h ago"
    else "#{(diff / 86400).round}d ago"
    end
  end
end
RUBY_CTRL_EOF

echo "Writing real ticket hub view (real design, real data)..."
mkdir -p app/views/supports
cat > app/views/supports/index.html.erb << 'ERB_VIEW_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<%= csrf_meta_tags %>
<title>Lightek MCG — Support Center</title>
<link href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@300;400;500;600;700;800;900&family=IBM+Plex+Mono:ital,wght@0,400;0,500;0,600;0,700;1,400&family=IBM+Plex+Sans:ital,wght@0,300;0,400;0,500;0,600;1,300;1,400&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;cursor:none;}
:root{
  --bg:#030810;--bg2:#060D1A;--panel:#091220;--card:#0B1628;--lift:#0E1C34;
  --cyan:#00B4CC;--cyan2:#00D0EC;--cyan3:#40E8FF;
  --gold:#C09018;--gold2:#D8A828;
  --green:#18C870;--green2:#20E880;
  --red:#CC1818;--red2:#EE2828;
  --orange:#CC6018;--orange2:#EC8028;
  --yellow:#C89010;--yellow2:#E8B020;
  --purple:#6818B8;--purple2:#8828D8;
  --white:#E4EEF8;--off:#B0C4D8;--muted:#3C5068;
  /* category colors */
  --deploy:#0060D0;--deploy2:#2080F0;
  --billing:#B05000;--billing2:#D07020;
  --compliance:#C01030;--compliance2:#E03050;
  --onboard:#108058;--onboard2:#18B878;
  --training:#506800;--training2:#708800;
  --tech:#502080;--tech2:#7030A8;
  --fc:'Barlow Condensed',sans-serif;
  --fm:'IBM Plex Mono',monospace;
  --fb:'IBM Plex Sans',sans-serif;
}
html{scroll-behavior:smooth;}
body{background:var(--bg);color:var(--white);font-family:var(--fb);overflow-x:hidden;}
body::before{content:'';position:fixed;inset:0;background-image:linear-gradient(rgba(0,180,220,.006) 1px,transparent 1px),linear-gradient(90deg,rgba(0,180,220,.006) 1px,transparent 1px);background-size:24px 24px;pointer-events:none;z-index:0;}

#cur{width:7px;height:7px;background:var(--cyan2);position:fixed;z-index:9999;pointer-events:none;transform:translate(-50%,-50%);box-shadow:0 0 12px rgba(0,180,220,.8);transition:width .15s,height .15s;}
#cur2{width:28px;height:28px;border:1px solid rgba(0,180,220,.2);position:fixed;z-index:9998;pointer-events:none;transform:translate(-50%,-50%);transition:left .1s cubic-bezier(.16,1,.3,1),top .1s,width .18s,height .18s;}

@keyframes blink{0%,100%{opacity:1}50%{opacity:.1}}
@keyframes slaCount{from{stroke-dashoffset:283}to{stroke-dashoffset:0}}
@keyframes fadeUp{from{opacity:0;transform:translateY(16px)}to{opacity:1;transform:none}}
@keyframes pulse{0%,100%{opacity:.5}50%{opacity:1}}
.fade-up{opacity:0;animation:fadeUp .7s cubic-bezier(.16,1,.3,1) forwards;}

/* VIEWS */
.view{display:none;}
.view.active{display:block;}

/* ═══════════════════════════════════════
   TOP NAV
═══════════════════════════════════════ */
.topnav{
  position:sticky;top:0;z-index:200;
  background:rgba(3,8,16,.98);
  border-bottom:1px solid rgba(0,180,220,.08);
  height:54px;display:flex;align-items:center;
  justify-content:space-between;padding:0 36px;
}
.topnav::after{content:'';position:absolute;bottom:0;left:0;right:0;height:1px;background:linear-gradient(to right,transparent,rgba(0,180,220,.35),rgba(0,180,220,.55),rgba(0,180,220,.35),transparent);}
.tn-left{display:flex;align-items:center;gap:12px;}
.tn-logo{display:flex;align-items:center;gap:8px;cursor:pointer;}
.tnl-mark{width:26px;height:26px;border:1.5px solid rgba(0,180,220,.4);display:flex;align-items:center;justify-content:center;font-family:var(--fc);font-size:14px;font-weight:800;color:var(--cyan);}
.tnl-name{font-family:var(--fc);font-size:13px;font-weight:800;letter-spacing:.12em;text-transform:uppercase;}
.tn-sep{width:1px;height:16px;background:rgba(0,180,220,.12);}
.tn-section{font-family:var(--fm);font-size:7px;letter-spacing:.22em;text-transform:uppercase;color:var(--muted);}
.tn-right{display:flex;align-items:center;gap:8px;}
.tn-btn{font-family:var(--fm);font-size:7px;letter-spacing:.14em;text-transform:uppercase;border:1px solid rgba(0,180,220,.15);background:rgba(0,180,220,.04);color:rgba(228,238,248,.45);padding:6px 14px;cursor:pointer;transition:all .18s;}
.tn-btn:hover{border-color:rgba(0,180,220,.35);color:var(--cyan);background:rgba(0,180,220,.08);}
.tn-btn.primary{background:var(--cyan);color:var(--bg);border-color:var(--cyan);}
.tn-btn.primary:hover{background:var(--cyan2);}
.tn-user{display:flex;align-items:center;gap:7px;}
.tn-avatar{width:26px;height:26px;border:1px solid rgba(0,180,220,.2);display:flex;align-items:center;justify-content:center;font-size:11px;}
.tn-user-name{font-family:var(--fm);font-size:7px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:rgba(228,238,248,.45);}

/* ═══════════════════════════════════════
   VIEW: HUB (landing)
═══════════════════════════════════════ */
#view-hub{padding:0 0 80px;}
.hub-hero{padding:60px 40px 48px;border-bottom:1px solid rgba(0,180,220,.07);position:relative;z-index:1;}
.hh-eyebrow{font-family:var(--fm);font-size:7px;letter-spacing:.3em;text-transform:uppercase;color:var(--cyan);margin-bottom:8px;}
.hh-title{font-family:var(--fc);font-size:clamp(40px,7vw,88px);font-weight:900;letter-spacing:.04em;line-height:.88;margin-bottom:10px;}
.hh-sub{font-family:var(--fb);font-weight:300;font-size:14px;color:rgba(228,238,248,.42);max-width:560px;line-height:1.9;margin-bottom:24px;}
/* search */
.support-search{display:flex;gap:0;max-width:600px;margin-bottom:0;}
.ss-input{flex:1;background:rgba(0,180,220,.05);border:1px solid rgba(0,180,220,.15);border-right:none;padding:12px 18px;font-family:var(--fb);font-size:14px;color:var(--white);outline:none;transition:border-color .18s;}
.ss-input:focus{border-color:rgba(0,180,220,.4);}
.ss-input::placeholder{color:rgba(228,238,248,.22);}
.ss-btn{font-family:var(--fc);font-size:14px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;background:var(--cyan);color:var(--bg);border:none;padding:12px 22px;cursor:pointer;transition:background .18s;}
.ss-btn:hover{background:var(--cyan2);}

/* category grid */
.hub-categories{padding:32px 40px 0;}
.hc-label{font-family:var(--fm);font-size:7px;letter-spacing:.26em;text-transform:uppercase;color:var(--muted);margin-bottom:16px;}
.category-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:4px;margin-bottom:32px;}
@media(max-width:900px){.category-grid{grid-template-columns:repeat(2,1fr);}}
@media(max-width:600px){.category-grid{grid-template-columns:1fr;}}

.cat-card{
  background:var(--panel);border:1px solid rgba(0,180,220,.07);
  padding:24px 22px;position:relative;overflow:hidden;
  cursor:pointer;transition:all .22s;
}
.cat-card:hover{border-color:rgba(0,180,220,.22);transform:translateY(-2px);}
.cat-card::before{content:'';position:absolute;top:0;left:0;right:0;height:3px;}
.cc-top{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:12px;}
.cc-icon{font-size:28px;}
.cc-sla{font-family:var(--fm);font-size:6px;letter-spacing:.12em;text-transform:uppercase;border:1px solid;padding:2px 7px;}
.cc-name{font-family:var(--fc);font-size:clamp(18px,2.5vw,26px);font-weight:900;letter-spacing:.06em;margin-bottom:5px;}
.cc-desc{font-family:var(--fb);font-weight:300;font-size:12px;color:rgba(228,238,248,.4);line-height:1.65;margin-bottom:12px;}
.cc-examples{display:flex;flex-direction:column;gap:3px;}
.cce-item{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.32);display:flex;align-items:flex-start;gap:5px;line-height:1.4;}
.cce-item::before{content:'→';color:rgba(0,180,220,.4);font-family:var(--fm);font-size:9px;margin-top:1px;flex-shrink:0;}
.cc-action{display:flex;justify-content:space-between;align-items:center;margin-top:14px;padding-top:12px;border-top:1px solid rgba(0,180,220,.06);}
.cca-text{font-family:var(--fm);font-size:7px;letter-spacing:.12em;text-transform:uppercase;}
.cca-arrow{font-family:var(--fc);font-size:20px;font-weight:900;color:rgba(0,180,220,.3);}

/* my tickets preview */
.hub-tickets{padding:0 40px;}
.ht-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;}
.ht-title{font-family:var(--fc);font-size:18px;font-weight:800;letter-spacing:.07em;}
.ht-action{font-family:var(--fm);font-size:7px;letter-spacing:.14em;text-transform:uppercase;color:var(--cyan);cursor:pointer;background:none;border:none;}
.ticket-preview{display:flex;flex-direction:column;gap:3px;}
.tp-item{display:grid;grid-template-columns:auto 1fr auto auto auto;gap:12px;align-items:center;padding:12px 16px;background:var(--panel);border:1px solid rgba(0,180,220,.07);cursor:pointer;transition:all .18s;}
.tp-item:hover{border-color:rgba(0,180,220,.2);}
.tp-cat-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;}
.tp-info{}
.tpi-num{font-family:var(--fm);font-size:7px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-bottom:2px;}
.tpi-subject{font-family:var(--fb);font-size:13px;font-weight:500;color:rgba(228,238,248,.75);}
.tp-cat{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;border:1px solid;padding:2px 7px;}
.tp-status{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;border:1px solid;padding:2px 7px;}
.st-open{border-color:rgba(200,24,24,.3);color:var(--red2);}
.st-progress{border-color:rgba(200,144,16,.3);color:var(--yellow2);}
.st-resolved{border-color:rgba(24,200,112,.3);color:var(--green);}
.tp-time{font-family:var(--fm);font-size:7px;color:var(--muted);text-align:right;}

/* ═══════════════════════════════════════
   VIEW: TICKET FORM
═══════════════════════════════════════ */
#view-form{padding:0;}
.form-layout{display:grid;grid-template-columns:1fr 340px;min-height:calc(100vh - 54px);}
@media(max-width:1000px){.form-layout{grid-template-columns:1fr;}}
.form-main{padding:36px 40px;border-right:1px solid rgba(0,180,220,.06);}
.fm-back{font-family:var(--fm);font-size:7px;letter-spacing:.14em;text-transform:uppercase;color:var(--cyan);cursor:pointer;margin-bottom:20px;display:flex;align-items:center;gap:5px;opacity:.7;transition:opacity .18s;background:none;border:none;}
.fm-back:hover{opacity:1;}
.fm-category-badge{display:inline-flex;align-items:center;gap:8px;padding:5px 14px;border:1px solid;margin-bottom:14px;}
.fmcb-icon{font-size:14px;}
.fmcb-text{font-family:var(--fm);font-size:7px;letter-spacing:.16em;text-transform:uppercase;font-weight:700;}
.fm-title{font-family:var(--fc);font-size:clamp(28px,4vw,52px);font-weight:900;letter-spacing:.04em;line-height:.88;margin-bottom:6px;}
.fm-sub{font-family:var(--fb);font-weight:300;font-size:13px;color:rgba(228,238,248,.38);margin-bottom:28px;line-height:1.8;}
/* form groups */
.fg{margin-bottom:14px;}
.fg-label{font-family:var(--fm);font-size:6px;letter-spacing:.2em;text-transform:uppercase;color:rgba(228,238,248,.35);margin-bottom:5px;display:block;}
.fg-label.req::after{content:' *';color:var(--cyan);}
.fg-input{width:100%;background:rgba(0,180,220,.04);border:1px solid rgba(0,180,220,.12);padding:11px 14px;font-family:var(--fb);font-size:13px;color:var(--white);outline:none;transition:border-color .18s;}
.fg-input:focus{border-color:rgba(0,180,220,.38);background:rgba(0,180,220,.06);}
.fg-input::placeholder{color:rgba(228,238,248,.2);}
.fg-select{width:100%;background:rgba(0,180,220,.04);border:1px solid rgba(0,180,220,.12);padding:11px 14px;font-family:var(--fm);font-size:10px;letter-spacing:.06em;color:rgba(228,238,248,.6);outline:none;-webkit-appearance:none;}
.fg-select:focus{border-color:rgba(0,180,220,.38);}
.fg-textarea{width:100%;background:rgba(0,180,220,.04);border:1px solid rgba(0,180,220,.12);padding:11px 14px;font-family:var(--fb);font-size:13px;color:var(--white);outline:none;resize:vertical;line-height:1.7;transition:border-color .18s;}
.fg-textarea:focus{border-color:rgba(0,180,220,.38);}
.fg-textarea::placeholder{color:rgba(228,238,248,.2);}
.fg-row{display:grid;gap:12px;}
.fg-row.two{grid-template-columns:1fr 1fr;}
.fg-row.three{grid-template-columns:1fr 1fr 1fr;}
/* priority selector */
.priority-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:4px;}
.prio-card{padding:12px 10px;border:1px solid;cursor:pointer;transition:all .18s;text-align:center;}
.prio-card.sel{background:rgba(0,180,220,.08);}
.pc-label{font-family:var(--fm);font-size:6px;letter-spacing:.12em;text-transform:uppercase;display:block;margin-bottom:3px;}
.pc-desc{font-family:var(--fb);font-weight:300;font-size:10px;line-height:1.4;}
/* urgency scale */
.urgency-scale{display:flex;gap:0;margin-top:4px;}
.us-step{flex:1;padding:10px 6px;border:1px solid rgba(0,180,220,.1);cursor:pointer;text-align:center;transition:all .18s;border-right:none;}
.us-step:last-child{border-right:1px solid rgba(0,180,220,.1);}
.us-step.sel{background:rgba(0,180,220,.08);border-color:rgba(0,180,220,.3);}
.us-num{font-family:var(--fm);font-size:11px;font-weight:700;display:block;color:rgba(228,238,248,.4);}
.us-step.sel .us-num{color:var(--cyan);}
.us-lbl{font-family:var(--fm);font-size:5px;letter-spacing:.1em;text-transform:uppercase;color:rgba(228,238,248,.25);margin-top:2px;}
/* file attach */
.file-drop{border:1px dashed rgba(0,180,220,.2);padding:20px;text-align:center;cursor:pointer;transition:all .18s;margin-top:4px;background:rgba(0,180,220,.02);}
.file-drop:hover{border-color:rgba(0,180,220,.4);background:rgba(0,180,220,.05);}
.fd-icon{font-size:22px;display:block;margin-bottom:6px;opacity:.4;}
.fd-text{font-family:var(--fb);font-weight:300;font-size:12px;color:rgba(228,238,248,.35);}
.fd-sub{font-family:var(--fm);font-size:6px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-top:4px;}
/* constitutional flag */
.const-flag{background:rgba(192,144,24,.05);border:1px solid rgba(192,144,24,.2);padding:14px 16px;margin-bottom:14px;display:flex;gap:10px;align-items:flex-start;}
.cf-icon{font-size:16px;flex-shrink:0;}
.cf-body{}
.cfb-title{font-family:var(--fc);font-size:14px;font-weight:700;letter-spacing:.06em;color:var(--gold2);margin-bottom:3px;}
.cfb-text{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.45);line-height:1.6;}
/* submit button */
.submit-btn{display:block;width:100%;font-family:var(--fc);font-size:16px;font-weight:800;letter-spacing:.12em;text-transform:uppercase;background:var(--cyan);color:var(--bg);border:none;padding:14px;cursor:pointer;transition:all .22s;margin-top:20px;position:relative;overflow:hidden;}
.submit-btn::before{content:'';position:absolute;inset:0;background:linear-gradient(90deg,transparent,rgba(255,255,255,.15),transparent);transform:translateX(-100%);transition:transform .5s;}
.submit-btn:hover{background:var(--cyan2);}
.submit-btn:hover::before{transform:translateX(100%);}

/* form sidebar — context panel */
.form-sidebar{padding:24px 20px;background:rgba(5,10,20,.98);border-left:1px solid rgba(0,180,220,.06);position:sticky;top:54px;height:calc(100vh - 54px);overflow-y:auto;display:flex;flex-direction:column;gap:0;}
.form-sidebar::-webkit-scrollbar{width:0;}
.fs-section{padding-bottom:16px;margin-bottom:16px;border-bottom:1px solid rgba(0,180,220,.06);}
.fs-section:last-child{border-bottom:none;}
.fss-title{font-family:var(--fm);font-size:7px;letter-spacing:.2em;text-transform:uppercase;color:var(--muted);margin-bottom:10px;display:flex;align-items:center;gap:5px;}
.fss-title::before{content:'◈';color:var(--cyan);font-size:8px;}
/* SLA indicator */
.sla-display{text-align:center;padding:14px 0;}
.sla-ring{position:relative;width:80px;height:80px;margin:0 auto 8px;}
.sla-svg{width:80px;height:80px;}
.sla-track{fill:none;stroke:rgba(0,180,220,.08);stroke-width:4;}
.sla-fill{fill:none;stroke-width:4;stroke-linecap:round;transform:rotate(-90deg);transform-origin:center;}
.sla-label{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;}
.sla-time{font-family:var(--fc);font-size:16px;font-weight:900;letter-spacing:.04em;}
.sla-unit{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);}
.sla-desc{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.38);line-height:1.6;}
/* assigned team */
.team-item{display:flex;gap:8px;align-items:center;margin-bottom:8px;}
.ti-avatar{width:28px;height:28px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:12px;flex-shrink:0;border:1px solid rgba(0,180,220,.15);}
.ti-body{}
.tib-name{font-family:var(--fm);font-size:8px;font-weight:700;letter-spacing:.06em;}
.tib-role{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);}
.ti-status{width:6px;height:6px;border-radius:50%;margin-left:auto;flex-shrink:0;}
/* tips */
.tip-item{display:flex;gap:7px;align-items:flex-start;margin-bottom:8px;font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.38);line-height:1.5;}
.tip-item::before{content:'→';color:var(--cyan);font-family:var(--fm);font-size:9px;flex-shrink:0;margin-top:1px;}

/* ═══════════════════════════════════════
   VIEW: CONFIRMATION
═══════════════════════════════════════ */
#view-confirm{padding:60px 40px;text-align:center;max-width:800px;margin:0 auto;position:relative;z-index:1;}
.conf-icon{font-size:52px;display:block;margin:0 auto 18px;filter:drop-shadow(0 0 18px rgba(0,180,220,.4));}
.conf-eyebrow{font-family:var(--fm);font-size:7px;letter-spacing:.32em;text-transform:uppercase;color:var(--cyan);margin-bottom:8px;}
.conf-title{font-family:var(--fc);font-size:clamp(36px,6vw,72px);font-weight:900;letter-spacing:.04em;line-height:.88;margin-bottom:10px;}
.conf-sub{font-family:var(--fb);font-weight:300;font-size:14px;color:rgba(228,238,248,.42);max-width:520px;margin:0 auto 24px;line-height:2;}
.conf-ticket-num{font-family:var(--fm);font-size:13px;font-weight:700;letter-spacing:.14em;color:var(--cyan);border:1px solid rgba(0,180,220,.22);padding:10px 24px;display:inline-block;margin-bottom:28px;}
/* confirmation card */
.conf-card{background:var(--panel);border:1px solid rgba(0,180,220,.1);text-align:left;margin-bottom:24px;overflow:hidden;}
.confcard-stripe{height:3px;}
.confcard-body{padding:22px 24px;}
.ccb-header{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:16px;}
.ccbh-left{}
.ccbhl-cat{font-family:var(--fm);font-size:6px;letter-spacing:.18em;text-transform:uppercase;margin-bottom:3px;}
.ccbhl-subject{font-family:var(--fc);font-size:clamp(16px,2.5vw,22px);font-weight:800;letter-spacing:.05em;}
.ccbh-sla{text-align:right;}
.ccbhs-label{font-family:var(--fm);font-size:6px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin-bottom:3px;}
.ccbhs-time{font-family:var(--fc);font-size:clamp(18px,2.5vw,26px);font-weight:900;}
.ccbhs-sub{font-family:var(--fm);font-size:6px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);}
.conf-detail-row{display:flex;justify-content:space-between;align-items:center;padding:7px 0;border-bottom:1px solid rgba(0,180,220,.05);}
.conf-detail-row:last-child{border-bottom:none;}
.cdr-label{font-family:var(--fb);font-weight:300;font-size:12px;color:rgba(228,238,248,.42);}
.cdr-val{font-family:var(--fm);font-size:8px;font-weight:700;color:var(--cyan);}
/* what happens next */
.what-next{display:grid;grid-template-columns:repeat(3,1fr);gap:4px;margin-bottom:24px;}
.wn-step{background:var(--panel);border:1px solid rgba(0,180,220,.07);padding:18px 16px;position:relative;}
.wn-step::before{content:'';position:absolute;top:0;left:0;right:0;height:2px;}
.wns-num{font-family:var(--fc);font-size:26px;font-weight:900;color:rgba(0,180,220,.12);margin-bottom:5px;}
.wns-title{font-family:var(--fc);font-size:14px;font-weight:800;letter-spacing:.06em;margin-bottom:4px;}
.wns-desc{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.35);line-height:1.6;}
/* buttons */
.conf-btns{display:flex;gap:8px;justify-content:center;}
.cb-p{font-family:var(--fc);font-size:14px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;background:var(--cyan);color:var(--bg);border:none;padding:12px 28px;cursor:pointer;transition:background .2s;}
.cb-p:hover{background:var(--cyan2);}
.cb-s{font-family:var(--fc);font-size:13px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;background:transparent;color:rgba(228,238,248,.38);border:1px solid rgba(0,180,220,.12);padding:12px 24px;cursor:pointer;transition:all .2s;}
.cb-s:hover{border-color:rgba(228,238,248,.2);color:rgba(228,238,248,.65);}

/* ═══════════════════════════════════════
   VIEW: TICKET STATUS TRACKER
═══════════════════════════════════════ */
#view-tracker{padding:36px 40px 80px;max-width:960px;}
.tracker-hdr{margin-bottom:28px;}
.tracker-title{font-family:var(--fc);font-size:clamp(28px,4vw,52px);font-weight:900;letter-spacing:.04em;margin-bottom:6px;}
.tracker-sub{font-family:var(--fb);font-weight:300;font-size:13px;color:rgba(228,238,248,.38);}
/* ticket detail */
.ticket-detail{background:var(--panel);border:1px solid rgba(0,180,220,.08);margin-bottom:4px;overflow:hidden;}
.td-header{display:grid;grid-template-columns:auto 1fr auto auto auto;gap:12px;align-items:center;padding:14px 18px;border-bottom:1px solid rgba(0,180,220,.06);cursor:pointer;transition:background .15s;}
.td-header:hover{background:rgba(0,180,220,.03);}
.td-cat-stripe{width:3px;height:32px;border-radius:2px;flex-shrink:0;}
.td-main{}
.tdm-num{font-family:var(--fm);font-size:6px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin-bottom:2px;}
.tdm-subject{font-family:var(--fb);font-size:13px;font-weight:500;color:rgba(228,238,248,.78);}
.td-cat-badge{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;border:1px solid;padding:2px 8px;}
.td-status-badge{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;border:1px solid;padding:2px 8px;}
.td-time{font-family:var(--fm);font-size:7px;color:var(--muted);text-align:right;}
/* expanded */
.td-body{padding:16px 18px;display:none;}
.td-body.open{display:block;}
.tdb-timeline{display:flex;flex-direction:column;gap:0;}
.tdb-event{display:flex;gap:12px;align-items:flex-start;padding:9px 0;border-bottom:1px solid rgba(0,180,220,.04);}
.tdb-event:last-child{border-bottom:none;}
.tdbe-time{font-family:var(--fm);font-size:7px;font-weight:700;color:var(--muted);flex-shrink:0;min-width:52px;padding-top:2px;}
.tdbe-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;margin-top:3px;}
.tdbe-body{flex:1;}
.tdbeb-action{font-family:var(--fb);font-size:12px;font-weight:500;color:rgba(228,238,248,.72);margin-bottom:2px;}
.tdbeb-detail{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.38);line-height:1.5;}
/* reply area */
.tdb-reply{margin-top:12px;border-top:1px solid rgba(0,180,220,.06);padding-top:12px;}
.tdbr-label{font-family:var(--fm);font-size:7px;letter-spacing:.16em;text-transform:uppercase;color:var(--muted);margin-bottom:6px;}
textarea.tdbr-input{width:100%;background:rgba(0,180,220,.04);border:1px solid rgba(0,180,220,.1);padding:10px 12px;font-family:var(--fb);font-size:12px;color:var(--white);outline:none;resize:none;line-height:1.6;}
textarea.tdbr-input:focus{border-color:rgba(0,180,220,.35);}
.tdbr-send{font-family:var(--fc);font-size:13px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;background:var(--cyan);color:var(--bg);border:none;padding:9px 20px;cursor:pointer;margin-top:7px;transition:background .18s;}
.tdbr-send:hover{background:var(--cyan2);}
</style>
</head>
<body>
<div id="cur"></div><div id="cur2"></div>

<!-- TOP NAV -->
<nav class="topnav">
  <div class="tn-left">
    <div class="tn-logo" onclick="showView('hub')">
      <div class="tnl-mark">L</div>
      <div class="tnl-name">LIGHTEK MCG</div>
    </div>
    <div class="tn-sep"></div>
    <div class="tn-section">◈ SUPPORT CENTER</div>
  </div>
  <div class="tn-right">
    <button class="tn-btn" onclick="showView('tracker')">MY TICKETS</button>
    <button class="tn-btn" onclick="showView('hub')">KNOWLEDGE BASE</button>
    <div class="tn-sep"></div>
    <div class="tn-user">
      <div class="tn-avatar">👤</div>
      <div class="tn-user-name"><%= current_user&.full_name&.upcase || "GUEST" %></div>
    </div>
    <button class="tn-btn primary" onclick="showView('hub')">+ NEW TICKET</button>
  </div>
</nav>

<!-- ═══════ VIEW: HUB ═══════ -->
<div class="view active" id="view-hub">
  <div class="hub-hero">
    <div class="hh-eyebrow">◈ LIGHTEK MCG · PARTNER SUPPORT CENTER</div>
    <div class="hh-title">HOW CAN<br>WE HELP?</div>
    <div class="hh-sub">Every ticket has a human behind it. Every issue has a timeline. Every resolution is documented. Select your issue category below — your ticket will be routed, prioritized, and assigned before you finish submitting it.</div>
    <div class="support-search">
      <input class="ss-input" type="text" placeholder="Search knowledge base — e.g. 'how to add a custom domain' or 'commission dispute'" />
      <button class="ss-btn">SEARCH</button>
    </div>
  </div>

  <div class="hub-categories">
    <div class="hc-label">SELECT YOUR ISSUE CATEGORY TO BEGIN</div>
    <div class="category-grid" id="cat-grid">
      <!-- Rendered by JS -->
    </div>
  </div>

  <div class="hub-tickets">
    <div class="ht-header">
      <div class="ht-title">RECENT TICKETS</div>
      <button class="ht-action" onclick="showView('tracker')">VIEW ALL →</button>
    </div>
    <div class="ticket-preview" id="ticket-preview">
      <!-- Rendered by JS -->
    </div>
  </div>
</div>

<!-- ═══════ VIEW: TICKET FORM ═══════ -->
<div class="view" id="view-form">
  <div class="form-layout">
    <div class="form-main" id="form-main"></div>
    <div class="form-sidebar" id="form-sidebar"></div>
  </div>
</div>

<!-- ═══════ VIEW: CONFIRMATION ═══════ -->
<div class="view" id="view-confirm">
  <span class="conf-icon">📋</span>
  <div class="conf-eyebrow">◈ SUPPORT TICKET SUBMITTED</div>
  <div class="conf-title">TICKET<br>FILED.</div>
  <div class="conf-sub">Your support ticket has been submitted and routed to the appropriate Lightek team. You will receive a response within the SLA window for your ticket category.</div>
  <div class="conf-ticket-num" id="conf-ticket-num">TICKET: LT-0000</div>

  <div class="conf-card">
    <div class="confcard-stripe" id="conf-stripe"></div>
    <div class="confcard-body">
      <div class="ccb-header">
        <div class="ccbh-left">
          <div class="ccbhl-cat" id="conf-cat-label">CATEGORY</div>
          <div class="ccbhl-subject" id="conf-subject">Your subject line</div>
        </div>
        <div class="ccbh-sla">
          <div class="ccbhs-label">SLA RESPONSE TIME</div>
          <div class="ccbhs-time" id="conf-sla">4h</div>
          <div class="ccbhs-sub">GUARANTEED</div>
        </div>
      </div>
      <div class="conf-detail-row"><div class="cdr-label">Ticket number</div><div class="cdr-val" id="conf-num2">LT-0000</div></div>
      <div class="conf-detail-row"><div class="cdr-label">Category</div><div class="cdr-val" id="conf-cat-val">—</div></div>
      <div class="conf-detail-row"><div class="cdr-label">Priority</div><div class="cdr-val" id="conf-priority">MEDIUM</div></div>
      <div class="conf-detail-row"><div class="cdr-label">Assigned team</div><div class="cdr-val" id="conf-team">—</div></div>
      <div class="conf-detail-row"><div class="cdr-label">Assigned rep</div><div class="cdr-val" id="conf-rep">—</div></div>
      <div class="conf-detail-row"><div class="cdr-label">Submitted</div><div class="cdr-val" id="conf-time">—</div></div>
    </div>
  </div>

  <div class="what-next">
    <div class="wn-step"><div style="position:absolute;top:0;left:0;right:0;height:2px;background:var(--cyan);"></div><div class="wns-num">01</div><div class="wns-title">CONFIRMATION EMAIL</div><div class="wns-desc">A confirmation with your ticket number and SLA commitment has been sent to your registered email address.</div></div>
    <div class="wn-step"><div style="position:absolute;top:0;left:0;right:0;height:2px;background:var(--green);"></div><div class="wns-num">02</div><div class="wns-title">REP ASSIGNMENT</div><div class="wns-desc">Your assigned rep will review the ticket and reach out within the SLA window — often faster for HIGH priority issues.</div></div>
    <div class="wn-step"><div style="position:absolute;top:0;left:0;right:0;height:2px;background:var(--gold2);"></div><div class="wns-num">03</div><div class="wns-title">TRACK YOUR TICKET</div><div class="wns-desc">Monitor status, respond to your rep, and view resolution history in the My Tickets section of the support center.</div></div>
  </div>

  <div class="conf-btns">
    <button class="cb-p" onclick="showView('tracker')">VIEW MY TICKETS →</button>
    <button class="cb-s" onclick="showView('hub')">SUBMIT ANOTHER TICKET</button>
  </div>
</div>

<!-- ═══════ VIEW: TICKET TRACKER ═══════ -->
<div class="view" id="view-tracker">
  <div class="tracker-hdr">
    <div class="tracker-title">MY TICKETS</div>
    <div class="tracker-sub">All support tickets submitted by your organization. Click any ticket to view timeline and respond to your assigned rep.</div>
  </div>
  <div id="tracker-list"></div>
</div>

<script>
// ── CURSOR ──────────────────────────────────
const cur=document.getElementById('cur'),cur2=document.getElementById('cur2');
let mx=0,my=0,rx=0,ry=0;
document.addEventListener('mousemove',e=>{mx=e.clientX;my=e.clientY;cur.style.left=mx+'px';cur.style.top=my+'px';});
(function l(){rx+=(mx-rx)*.12;ry+=(my-ry)*.12;cur2.style.left=rx+'px';cur2.style.top=ry+'px';requestAnimationFrame(l);})();

// ── CATEGORY DATA ───────────────────────────
// ── CATEGORY DATA — real, from Marlon::TicketCategories, not hardcoded ─────
const CATEGORIES = <%= raw @categories.map { |id, meta|
  {
    id: id, icon: meta[:icon], name: meta[:label].upcase, color: meta[:color], stripeBg: meta[:stripe],
    sla: Marlon::TicketCategories.sla_label(id), slaColor: meta[:color], team: meta[:team], rep: meta[:default_rep],
    desc: meta[:desc], examples: meta[:examples], fields: id, tips: meta[:tips], teams: meta[:teams]
  }
}.to_json %>;
// ── EXISTING TICKETS DATA ────────────────────
// ── EXISTING TICKETS DATA — real, from Marlon::Ticket, not hardcoded ───────
const MY_TICKETS = <%= raw @my_tickets_json.to_json %>;

let selectedCategory=null;
let selectedPriority='medium';
let urgencyLevel=5;

// ── VIEW MANAGER ────────────────────────────
function showView(id){
  document.querySelectorAll('.view').forEach(v=>v.classList.remove('active'));
  document.getElementById('view-'+id).classList.add('active');
  window.scrollTo(0,0);
  if(id==='hub'){renderHub();}
  if(id==='tracker'){renderTracker();}
}

// ── HUB ─────────────────────────────────────
function renderHub(){
  // category grid
  const grid=document.getElementById('cat-grid');
  grid.innerHTML=CATEGORIES.map(c=>`
    <div class="cat-card" onclick="openForm('${c.id}')" style="">
      <div style="position:absolute;top:0;left:0;right:0;height:3px;background:${c.stripeBg};"></div>
      <div class="cc-top">
        <div class="cc-icon">${c.icon}</div>
        <div class="cc-sla" style="border-color:${c.color}30;color:${c.color};">SLA: ${c.sla}</div>
      </div>
      <div class="cc-name" style="color:${c.color};">${c.name}</div>
      <div class="cc-desc">${c.desc}</div>
      <div class="cc-examples">
        ${c.examples.slice(0,3).map(e=>`<div class="cce-item">${e}</div>`).join('')}
      </div>
      <div class="cc-action">
        <div class="cca-text" style="color:${c.color};">SUBMIT TICKET →</div>
        <div class="cca-arrow" style="color:${c.color};">→</div>
      </div>
    </div>`).join('');
  // tickets preview
  const preview=document.getElementById('ticket-preview');
  preview.innerHTML=MY_TICKETS.map(t=>{
    const cat=CATEGORIES.find(c=>c.id===t.cat);
    return `<div class="tp-item" onclick="showView('tracker')">
      <div class="tp-cat-dot" style="background:${cat.color};"></div>
      <div class="tp-info">
        <div class="tpi-num">${t.num}</div>
        <div class="tpi-subject">${t.subject}</div>
      </div>
      <div class="tp-cat" style="border-color:${cat.color}40;color:${cat.color};">${cat.name}</div>
      <div class="tp-status ${t.status==='open'?'st-open':t.status==='progress'?'st-progress':'st-resolved'}">${t.status==='open'?'OPEN':t.status==='progress'?'IN PROGRESS':'RESOLVED'}</div>
      <div class="tp-time">${t.time}</div>
    </div>`;
  }).join('');
  addHoverFX();
}

// ── FORM ─────────────────────────────────────
function openForm(catId){
  selectedCategory=CATEGORIES.find(c=>c.id===catId);
  if(!selectedCategory)return;
  renderForm();
  showView('form');
}

function renderForm(){
  const c=selectedCategory;
  const fm=document.getElementById('form-main');
  // category-specific extra fields
  let extraFields='';
  if(c.id==='deployment'){
    extraFields=`
      <div class="fg-row two">
        <div class="fg"><label class="fg-label req">AFFECTED MODULE(S)</label>
          <select class="fg-select"><option>Select module…</option><option>Bank Module (SKU-001)</option><option>Church Module (SKU-008)</option><option>Streaming Module (SKU-014)</option><option>Connect Module (SKU-004)</option><option>Wellness Module (SKU-009)</option><option>Multiple modules</option><option>Entire instance</option></select></div>
        <div class="fg"><label class="fg-label req">ENVIRONMENT</label>
          <select class="fg-select"><option>Lightek Cloud (Managed)</option><option>Hybrid Deployment</option><option>Dedicated Node</option></select></div>
      </div>
      <div class="fg-row two">
        <div class="fg"><label class="fg-label">INSTANCE URL</label><input class="fg-input" placeholder="app.yourorganization.com" /></div>
        <div class="fg"><label class="fg-label">ERROR CODE / MESSAGE</label><input class="fg-input" placeholder="e.g. 503, timeout, auth failed" /></div>
      </div>
      <div class="fg"><label class="fg-label">IS THIS BLOCKING YOUR GO-LIVE?</label>
        <select class="fg-select"><option>No — affecting an existing live deployment</option><option>Yes — blocking our scheduled go-live</option><option>Yes — we are in active onboarding</option></select></div>`;
  } else if(c.id==='billing'){
    extraFields=`
      <div class="fg-row two">
        <div class="fg"><label class="fg-label req">INVOICE OR STATEMENT NUMBER</label><input class="fg-input" placeholder="e.g. LT-INV-2026-Q1-001" /></div>
        <div class="fg"><label class="fg-label req">AMOUNT IN QUESTION</label><input class="fg-input" placeholder="e.g. $1,680.00" /></div>
      </div>
      <div class="fg"><label class="fg-label req">ISSUE TYPE</label>
        <select class="fg-select"><option>Select issue type…</option><option>Incorrect amount on invoice</option><option>Commission statement discrepancy</option><option>Missing payment credit</option><option>Payment method update needed</option><option>Subscription change request</option><option>Contract term question</option></select></div>
      <div class="fg"><label class="fg-label">BILLING PERIOD</label><input class="fg-input" placeholder="e.g. Q1 2026, January 2026" /></div>`;
  } else if(c.id==='compliance'){
    extraFields=`
      <div class="const-flag">
        <div class="cf-icon">⚖️</div>
        <div class="cf-body">
          <div class="cfb-title">CONSTITUTIONAL PRIORITY — ARTICLE VI–VIII</div>
          <div class="cfb-text">Compliance tickets involving Constitutional violations are treated as PRIORITY HIGH by default and will trigger immediate review by the Compliance team and the Ministry Engine governance layer. Do not delay filing if a citizen's rights are at stake.</div>
        </div>
      </div>
      <div class="fg-row two">
        <div class="fg"><label class="fg-label req">ARTICLE REFERENCE</label>
          <select class="fg-select"><option>Select article…</option><option>Article I — Freedom of Ownership</option><option>Article II — Economic Participation</option><option>Article III — Freedom of Faith</option><option>Article IV — Right to Infrastructure</option><option>Article V — Cultural Sovereignty</option><option>Article VI — Cultural Attribution</option><option>Article VII — Reparations Fund</option><option>Article VIII — Universal Access</option><option>Ministry Engine Protocol Violation</option></select></div>
        <div class="fg"><label class="fg-label req">CLAUSE (IF KNOWN)</label><input class="fg-input" placeholder="e.g. §6.2, §8.1" /></div>
      </div>
      <div class="fg"><label class="fg-label req">PARTY ALLEGEDLY IN VIOLATION</label><input class="fg-input" placeholder="Organization name or entity responsible" /></div>
      <div class="fg"><label class="fg-label">CITIZENS AFFECTED</label><input class="fg-input" placeholder="Approximate number of citizens impacted (if known)" /></div>`;
  } else if(c.id==='onboarding'){
    extraFields=`
      <div class="fg-row two">
        <div class="fg"><label class="fg-label req">ONBOARDING DAY</label><input class="fg-input" type="number" placeholder="Day X of 90" min="1" max="90" /></div>
        <div class="fg"><label class="fg-label">ASSIGNED ONBOARDING REP</label><input class="fg-input" placeholder="Rep name if you have one" /></div>
      </div>
      <div class="fg"><label class="fg-label req">ONBOARDING MILESTONE BLOCKED</label>
        <select class="fg-select"><option>Select milestone…</option><option>White-label branding setup</option><option>Custom domain configuration</option><option>Module activation</option><option>Citizen bulk import</option><option>Payment/billing configuration</option><option>Staff training scheduling</option><option>Go-live final checks</option></select></div>`;
  } else if(c.id==='training'){
    extraFields=`
      <div class="fg-row two">
        <div class="fg"><label class="fg-label req">NUMBER OF TEAM MEMBERS</label><input class="fg-input" type="number" placeholder="How many people need training?" min="1" /></div>
        <div class="fg"><label class="fg-label req">TRAINING TYPE</label>
          <select class="fg-select"><option>Select type…</option><option>Platform overview training</option><option>Module-specific deep dive</option><option>Lightek Associate Certification</option><option>Lightek Distributor Certification</option><option>Ministry Engine training</option><option>API / Developer training</option><option>Custom training program</option></select></div>
      </div>
      <div class="fg"><label class="fg-label">PREFERRED TRAINING DATES</label><input class="fg-input" placeholder="e.g. Any weekday AM, prefer March 25–28" /></div>`;
  } else if(c.id==='technical'){
    extraFields=`
      <div class="fg-row two">
        <div class="fg"><label class="fg-label req">API ENDPOINT OR FEATURE</label><input class="fg-input" placeholder="e.g. /v1/bank/accounts, Webhook: citizen.created" /></div>
        <div class="fg"><label class="fg-label">HTTP STATUS / ERROR CODE</label><input class="fg-input" placeholder="e.g. 401, 500, ECONNREFUSED" /></div>
      </div>
      <div class="fg"><label class="fg-label">REQUEST / RESPONSE (paste or describe)</label><textarea class="fg-textarea" rows="3" placeholder="Paste the request payload and the response you received. Remove any sensitive tokens before pasting."></textarea></div>
      <div class="fg-row two">
        <div class="fg"><label class="fg-label">SDK / LANGUAGE</label><input class="fg-input" placeholder="e.g. Node.js v18, Python 3.11, REST" /></div>
        <div class="fg"><label class="fg-label">IS A SCREENSHARE NEEDED?</label><select class="fg-select"><option>No — I can explain in writing</option><option>Possibly — depends on complexity</option><option>Yes — this needs a live session</option></select></div>
      </div>`;
  }

  fm.innerHTML=`
    <button class="fm-back" onclick="showView('hub')">← ALL CATEGORIES</button>
    <div class="fm-category-badge" style="border-color:${c.color}40;background:${c.color}10;">
      <div class="fmcb-icon">${c.icon}</div>
      <div class="fmcb-text" style="color:${c.color};">${c.name} SUPPORT</div>
    </div>
    <div class="fm-title" style="color:${c.color};">SUBMIT ${c.name}<br>TICKET</div>
    <div class="fm-sub">${c.desc} Response within <strong style="color:${c.color};">${c.sla}</strong>. Assigned to: <strong style="color:${c.color};">${c.team}</strong>.</div>

    <!-- STANDARD FIELDS -->
    <div class="fg"><label class="fg-label req">SUBJECT LINE</label><input class="fg-input" id="ticket-subject" placeholder="Brief, specific description of the issue — e.g. 'Bank module 503 error on Compton instance'" /></div>
    <div class="fg-row two">
      <div class="fg"><label class="fg-label req">ORGANIZATION NAME</label><input class="fg-input" placeholder="Your organization" value="Apex Digital Agency" /></div>
      <div class="fg"><label class="fg-label req">RESELLER ID</label><input class="fg-input" placeholder="LT-DIST-XXXXXX" value="LT-DIST-004821" /></div>
    </div>
    <div class="fg-row two">
      <div class="fg"><label class="fg-label req">YOUR NAME</label><input class="fg-input" placeholder="Full name" /></div>
      <div class="fg"><label class="fg-label req">EMAIL ADDRESS</label><input class="fg-input" type="email" placeholder="your@organization.com" /></div>
    </div>

    <!-- CATEGORY-SPECIFIC FIELDS -->
    ${extraFields}

    <!-- PRIORITY -->
    <div class="fg">
      <label class="fg-label req">PRIORITY LEVEL</label>
      <div class="priority-grid">
        <div class="prio-card" style="border-color:rgba(200,144,16,.2);" onclick="selPriority(this,'low')">
          <div class="pc-label" style="color:var(--yellow2);">LOW</div>
          <div class="pc-desc">General question, no operational impact</div>
        </div>
        <div class="prio-card" style="border-color:rgba(0,180,220,.2);" onclick="selPriority(this,'medium')">
          <div class="pc-label" style="color:var(--cyan);">MEDIUM</div>
          <div class="pc-desc" style="color:rgba(228,238,248,.5);">Affecting operations but workaround exists</div>
        </div>
        <div class="prio-card sel" style="border-color:rgba(200,96,24,.3);background:rgba(200,96,24,.06);" onclick="selPriority(this,'high')">
          <div class="pc-label" style="color:var(--orange2);">HIGH</div>
          <div class="pc-desc" style="color:rgba(228,238,248,.5);">Operations impacted, no workaround</div>
        </div>
        <div class="prio-card" style="border-color:rgba(200,24,24,.25);" onclick="selPriority(this,'critical')">
          <div class="pc-label" style="color:var(--red2);">CRITICAL</div>
          <div class="pc-desc" style="color:rgba(228,238,248,.5);">Deployment down or citizen data affected</div>
        </div>
      </div>
    </div>

    <!-- URGENCY SCALE -->
    <div class="fg">
      <label class="fg-label">URGENCY SCALE (1–10)</label>
      <div class="urgency-scale" id="urgency-scale">
        ${[1,2,3,4,5,6,7,8,9,10].map(n=>`<div class="us-step ${n===5?'sel':''}" onclick="selUrgency(this,${n})"><span class="us-num">${n}</span><div class="us-lbl">${n===1?'LOW':n===5?'MED':n===10?'CRIT':''}</div></div>`).join('')}
      </div>
    </div>

    <!-- DESCRIPTION -->
    <div class="fg"><label class="fg-label req">DETAILED DESCRIPTION</label><textarea class="fg-textarea" id="ticket-desc" rows="5" placeholder="Describe the issue in detail. Include what you expected to happen, what actually happened, and any steps you've already tried. The more context you provide, the faster we can help."></textarea></div>

    <!-- FILE ATTACH -->
    <div class="fg">
      <label class="fg-label">ATTACHMENTS (optional)</label>
      <div class="file-drop" onclick="this.querySelector('input').click()">
        <input type="file" multiple style="display:none;" onchange="handleFiles(this)" />
        <span class="fd-icon">📎</span>
        <div class="fd-text">Drop files here or click to upload</div>
        <div class="fd-sub">Screenshots · Logs · Invoices · Error reports · Max 25MB each</div>
      </div>
      <div id="file-list" style="margin-top:6px;"></div>
    </div>

    <button class="submit-btn" onclick="submitTicket()" style="background:${c.color};">SUBMIT ${c.name} TICKET →</button>`;

  // sidebar
  const fs=document.getElementById('form-sidebar');
  fs.innerHTML=`
    <div class="fs-section">
      <div class="fss-title">RESPONSE SLA</div>
      <div class="sla-display">
        <div class="sla-ring">
          <svg class="sla-svg" viewBox="0 0 90 90">
            <circle class="sla-track" cx="45" cy="45" r="36"/>
            <circle class="sla-fill" cx="45" cy="45" r="36" stroke="${c.color}" stroke-dasharray="226" stroke-dashoffset="${c.id==='compliance'?0:c.id==='deployment'?56:c.id==='technical'?56:113}" />
          </svg>
          <div class="sla-label"><div class="sla-time" style="color:${c.color};">${c.sla}</div><div class="sla-unit">RESPONSE</div></div>
        </div>
        <div class="sla-desc">You will receive a first response from the <strong>${c.team}</strong> within ${c.sla} of submission. Critical issues are often addressed within 30 minutes.</div>
      </div>
    </div>
    <div class="fs-section">
      <div class="fss-title">ASSIGNED TEAM</div>
      ${c.teams.map(t=>`
        <div class="team-item">
          <div class="ti-avatar">${t.avatar}</div>
          <div class="ti-body"><div class="tib-name">${t.name}</div><div class="tib-role">${t.role}</div></div>
          <div class="ti-status" style="background:${t.status==='green'?'var(--green)':t.status==='away'?'var(--yellow)':'var(--muted)'};"></div>
        </div>`).join('')}
    </div>
    <div class="fs-section">
      <div class="fss-title">TIPS FOR FASTER RESOLUTION</div>
      ${c.tips.map(t=>`<div class="tip-item">${t}</div>`).join('')}
    </div>
    <div class="fs-section">
      <div class="fss-title">RELATED RESOURCES</div>
      <div class="tip-item">Lightek Knowledge Base — lightek.io/docs</div>
      <div class="tip-item">Module integration guides — lightek.io/integrations</div>
      <div class="tip-item">Ministry Engine protocol reference — lightek.io/ministry-engine</div>
      <div class="tip-item">Constitutional Articles I–VIII — blackhouse.gov/constitution</div>
    </div>`;

  addHoverFX();
}

function selPriority(el,val){
  selectedPriority=val;
  document.querySelectorAll('.prio-card').forEach(p=>{
    p.classList.remove('sel');
    p.style.background='transparent';
  });
  el.classList.add('sel');
  const colors={low:'rgba(200,144,16,.08)',medium:'rgba(0,180,220,.06)',high:'rgba(200,96,24,.08)',critical:'rgba(200,24,24,.08)'};
  el.style.background=colors[val];
}

function selUrgency(el,n){
  urgencyLevel=n;
  document.querySelectorAll('.us-step').forEach(s=>{s.classList.remove('sel');s.querySelector('.us-num').style.color='rgba(228,238,248,.4)';});
  el.classList.add('sel');
  el.querySelector('.us-num').style.color='var(--cyan)';
}

function handleFiles(input){
  const list=document.getElementById('file-list');
  if(!list)return;
  list.innerHTML=Array.from(input.files).map(f=>`<div style="display:flex;align-items:center;gap:7px;padding:5px 9px;background:rgba(0,180,220,.05);border:1px solid rgba(0,180,220,.1);margin-bottom:3px;font-family:var(--fm);font-size:7px;letter-spacing:.08em;color:rgba(228,238,248,.5);">📎 ${f.name} <span style="color:var(--muted);">${(f.size/1024).toFixed(0)}KB</span></div>`).join('');
}

function submitTicket(){
  const c=selectedCategory;
  if(!c)return;
  const subject=document.getElementById('ticket-subject')?.value||'Support ticket';
  const description=document.getElementById('ticket-desc')?.value||'';
  const csrf=document.querySelector('meta[name="csrf-token"]')?.content;

  fetch('/supports',{
    method:'POST',
    headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf},
    body:JSON.stringify({ticket:{category:c.id,title:subject,description:description,priority:selectedPriority,urgency:urgencyLevel}})
  }).then(r=>r.json()).then(data=>{
    if(!data.ok){alert(data.error||'Could not submit ticket.');return;}
    const ticketNum=data.number;
    const now=new Date().toLocaleTimeString('en-US',{hour:'2-digit',minute:'2-digit'});
    // Reflect the new ticket locally so the tracker shows it without a reload.
    MY_TICKETS.unshift({id:data.id,num:ticketNum,cat:c.id,subject:subject,status:'open',time:'just now',
      priority:selectedPriority.toUpperCase(),
      events:[{time:now,dot:c.color,action:'Ticket submitted',detail:description}]});
    // populate confirm
    document.getElementById('conf-ticket-num').textContent='TICKET: '+ticketNum;
    document.getElementById('conf-num2').textContent=ticketNum;
    document.getElementById('conf-stripe').style.background=c.stripeBg;
    document.getElementById('conf-cat-label').textContent=c.name+' SUPPORT';
    document.getElementById('conf-cat-label').style.color=c.color;
    document.getElementById('conf-subject').textContent=subject||`${c.name} support request`;
    document.getElementById('conf-sla').textContent=c.sla;
    document.getElementById('conf-sla').style.color=c.color;
    document.getElementById('conf-cat-val').textContent=c.name;
    document.getElementById('conf-cat-val').style.color=c.color;
    document.getElementById('conf-priority').textContent=selectedPriority.toUpperCase();
    document.getElementById('conf-priority').style.color=selectedPriority==='critical'?'var(--red2)':selectedPriority==='high'?'var(--orange2)':selectedPriority==='medium'?'var(--cyan)':'var(--yellow2)';
    document.getElementById('conf-team').textContent=c.team;
    document.getElementById('conf-rep').textContent=c.rep;
    document.getElementById('conf-time').textContent='Today '+now;
    showView('confirm');
  }).catch(()=>alert('Network error — ticket was not submitted.'));
}

// ── TRACKER ─────────────────────────────────
function renderTracker(){
  const list=document.getElementById('tracker-list');
  list.innerHTML=MY_TICKETS.map(t=>{
    const cat=CATEGORIES.find(c=>c.id===t.cat);
    return `
    <div class="ticket-detail">
      <div class="td-header" onclick="toggleTicket('${t.num}',this)">
        <div class="td-cat-stripe" style="background:${cat.color};"></div>
        <div class="td-main">
          <div class="tdm-num">${t.num}</div>
          <div class="tdm-subject">${t.subject}</div>
        </div>
        <div class="td-cat-badge" style="border-color:${cat.color}40;color:${cat.color};">${cat.name}</div>
        <div class="td-status-badge ${t.status==='open'?'st-open':t.status==='progress'?'st-progress':'st-resolved'}">${t.status==='open'?'OPEN':t.status==='progress'?'IN PROGRESS':'RESOLVED'}</div>
        <div class="td-time">${t.time}</div>
      </div>
      <div class="td-body" id="body-${t.num}">
        <div class="tdb-timeline">
          ${t.events.map(e=>`
            <div class="tdb-event">
              <div class="tdbe-time">${e.time}</div>
              <div class="tdbe-dot" style="background:${e.dot};"></div>
              <div class="tdbe-body">
                <div class="tdbeb-action">${e.action}</div>
                <div class="tdbeb-detail">${e.detail}</div>
              </div>
            </div>`).join('')}
        </div>
        ${t.status!=='resolved'?`
        <div class="tdb-reply">
          <div class="tdbr-label">REPLY TO YOUR REP</div>
          <textarea class="tdbr-input" rows="3" placeholder="Add additional context, confirm information, or ask a follow-up question…"></textarea>
          <button class="tdbr-send" onclick="sendReply(this,${t.id})">SEND REPLY →</button>
        </div>`:'<div style="font-family:var(--fm);font-size:7px;letter-spacing:.14em;text-transform:uppercase;color:var(--green);padding:12px 0;">✓ TICKET RESOLVED — Closed '+t.time+'</div>'}
      </div>
    </div>`;
  }).join('');
  addHoverFX();
}

function toggleTicket(num,header){
  const body=document.getElementById('body-'+num);
  if(body)body.classList.toggle('open');
}

function sendReply(btn,ticketId){
  const textarea=btn.parentElement.querySelector('.tdbr-input');
  const detail=textarea?.value||'';
  const csrf=document.querySelector('meta[name="csrf-token"]')?.content;
  btn.disabled=true;
  fetch(`/supports/${ticketId}/reply`,{
    method:'PATCH',
    headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf},
    body:JSON.stringify({detail:detail})
  }).then(r=>r.json()).then(data=>{
    if(data.ok){
      btn.textContent='✓ REPLY SENT';
      btn.style.background='var(--green)';
    }else{
      btn.disabled=false;
      alert('Could not send reply.');
    }
  }).catch(()=>{btn.disabled=false;alert('Network error — reply was not sent.');});
}

// ── UTILS ────────────────────────────────────
function addHoverFX(){
  document.querySelectorAll('button,.cat-card,.tp-item,.prio-card,.us-step,.td-header,.bc-chip').forEach(el=>{
    el.addEventListener('mouseenter',()=>{cur.style.width='10px';cur.style.height='10px';cur2.style.width='34px';cur2.style.height='34px';});
    el.addEventListener('mouseleave',()=>{cur.style.width='7px';cur.style.height='7px';cur2.style.width='28px';cur2.style.height='28px';});
  });
}

// ── INIT ─────────────────────────────────────
renderHub();
</script>
</body>
</html>
ERB_VIEW_EOF

echo "Removing old generic scaffold views (index/show/new/edit for supports)..."
rm -f app/views/supports/show.html.erb app/views/supports/new.html.erb app/views/supports/edit.html.erb app/views/supports/_form.html.erb
rm -f app/views/supports/index.json.jbuilder app/views/supports/show.json.jbuilder app/views/supports/_support.json.jbuilder 2>/dev/null || true

echo "Fixing routes — explicit actions only, avoids the same 'unknown action' bug we hit with tickets..."
if grep -q "resources :supports$" config/routes.rb; then
  sed -i '' 's/resources :supports$/resources :supports, only: %i[index create] do\n    member { patch :reply }\n  end/' config/routes.rb
  echo "  OK — routes.rb patched"
else
  echo "  WARNING: could not find 'resources :supports' line to patch automatically."
  echo "  Replace it manually with:"
  echo "    resources :supports, only: %i[index create] do"
  echo "      member { patch :reply }"
  echo "    end"
fi

echo ""
echo "Done. Restart:"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
echo ""
echo "Visit /supports"
