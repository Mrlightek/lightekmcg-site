# Public relations

In Dashboard → Journal & Articles → Public relations, assign the PR SME to the website. Select an active Lightek mailbox you own to delegate media outreach as well. This authority belongs to the assigning operator and website. Pause the assignment or specialist to stop new PR work and block pending outreach before SMTP submission. Messages already accepted by SMTP remain in mail history.

Give the SME confirmed facts, an announcement summary and a public press contact for each release. Choose draft, publish, or archive. To revise a release without changing its URL, pass its entry ID and current article revision with the updated brief. Only published releases appear in the public Journal and press page.

Record the relationship or editorial contact source for each recipient. Use the do-not-contact list to stop future outreach. A pitch is a private draft until you assign it for delivery. The SME sends it from the assigned Lightek mailbox, using the platform mail queue and sending limits. Delivery status records the SMTP submission state. A follow-up can be assigned three days after a pitch is submitted, provided the mailbox has no reply in that thread. Each pitch has one initial message and one follow-up per sender mailbox. Check existing delivery history before moving outreach to a different mailbox.

Log the URL and notes for press coverage. Use **Check a media source** to scan an approved public HTTPS page for a name or phrase and save the source and matching text. You can schedule repeated checks through Workforce with `/agent schedule public_relations 1440 /pr monitor SITE_ID {"url":"https://publisher.example/news","phrase":"Lightek Media"}`. A response brief organizes confirmed facts, proposed wording and the next update in the private Dashboard. Use the release workflow for public statements. The activity report includes published releases, active contacts, coverage and recent pitch delivery and reply status.

Use `Review PR activity for site SITE_ID` in Nevaeh or use a typed command such as `/pr send_pitch SITE_ID {"pitch_id":123}`. Goals preserve assignments and receipts. Use `/guide public_relations` for this page.
