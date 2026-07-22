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
      h ? "#{h}h" : nil
    end
  end
end
