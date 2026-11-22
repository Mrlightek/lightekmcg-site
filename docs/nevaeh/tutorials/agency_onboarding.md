# Agency onboarding

Open Nevaeh and choose **Agency onboarding**. This workspace tracks onboarding for recurring annual Lightek agency memberships. The existing verified checkout settles payment and activates agency access. The onboarding sweep picks up the committed order and reconciles open cases every five minutes. Renewals on the same checkout reuse its case.

A case completes after the owner opens their own Agency Dashboard and the branded mailbox is sending-ready. Agency access and Dashboard sign-in follow the existing lifecycle and MFA checks. For a public agency trial, the sweep can reuse the same storefront's recorded email confirmation to create a mailbox. An invited member can confirm their sign-in email from the Agency Dashboard. The mailbox is hosted on the shared Lightek service. Dedicated hosting is a separate purchase.

The owner receives one Dashboard reminder after 24 hours if they have yet to open the workspace. The operator can see the case, follow-up status and the reason for an escalation. A revoked or refunded membership leaves the queue without a completion receipt.

## Review a playbook improvement

Nevaeh compares 12-, 24- and 48-hour operator escalation timings for owners who have yet to open their Dashboard. The initial playbook uses 24 hours. The scheduled job trains on the older half of at least 12 mature cases and tests its suggestion on the newer half. A case matures 72 hours after payment. The evaluator penalizes an escalation before an owner arrives within the observation window, and delay for owners who remain absent at the end of the window.

A passing proposal appears under **Playbook improvements**. The operator can approve or decline it. Approval compares the revised timing with the previous timing on roughly half of new cases each. After at least six mature cases in each group, the sweep measures observed escalations. A worse rollout which also loses on a replay of the same cases restores the last accepted timing. Cases that explain a rollback become regression examples for later proposals.

The rollout score measures the timing of internal escalation. Completion still requires the same payment, Dashboard and mailbox evidence, and the automatic Dashboard reminder continues at 24 hours. Details for each version include held-out score, cohort sizes, observed scores and rollback status.
