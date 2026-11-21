# TV network carriage and Nielsen measurement

Manage the company portfolio, affiliate carriage, programming rights, and audience reports in **Live Studio → Network lineup and viewership**. The platform operator can install the company division hierarchy in People without reparenting existing departments. Participating stations keep independent schedules and policies.

## Connected installations

Connect a managed installation using its existing Lightek federation credential. The station requests carriage and the platform operator approves it. The station syncs its current schedule every minute. Once accepted, the hub relays the station’s public HLS playlist from its registered HTTPS host. This path carries managed Channel Playout streams. The station can withdraw carriage from its dashboard.

A station can offer a specific MP4 proxy through the programming board. The named recipient accepts the license and streams a checksum-verified copy into its protected playout library. The limit is 256 MB per program. Imported rights are checked against the broker before a new booking. The transfer does not include the station’s other Studio assets.

### Configure a hub backup

On the network lineup, assign a published, hub-owned, managed channel as the hosted station's backup. Keep a rundown on air on that channel during the affiliate's coverage window. A stalled or unreachable station switches to fresh hub segments on the same HLS URL. The hub switches back when the station resumes producing fresh segments. Removing carriage or disabling a station's federation connection ends access. Backup segments carry no affiliate audience or ad attribution.

### Publish clips and offer sublicenses

Accept the program license first. Under Programming rights, select **Publish a clip** on an eligible grant, enter a start and duration, and open the resulting share link after it processes. Playback uses the recipient station's watch policy. A withdrawn or expired grant disables the link, including for an imported license. Choose **Remove clip** to withdraw that specific excerpt.

Use **Offer a sublicense** when the parent grant includes syndication. The recipient must be a participating station. The offer can use only the parent's original media, permitted rights, and date range. The broker handles onward offers from hosted installations. Withdrawal of a parent closes descendant grants to new bookings.

### Verify a release

On two deployed installations, approve a station and verify the same affiliate channel through Web TV and Octavia on a Roku. With a hub backup airing, drop and restore the station feed while watching. Confirm that the guide entry and playback URL stay the same and the backup receives no affiliate credit. Withdraw carriage and confirm viewers lose access.

For payment acceptance, follow a real authorized sponsor booking from the hosted checkout through a complete public airing, captured payment, and the recipients' Dymond Bank settlement. Use the operator export to reconcile the amounts. Confirm Nielsen events with the issued certification App IDs and approved test devices before enabling production measurement.

## Activate Nielsen DCR

Use the app-specific identifier supplied by Nielsen. Add a Vault record called `nielsen-dcr-web-<site id>` for the web player, or `nielsen-dcr-roku-<site id>` for the native client. Use purpose `nielsen_measurement` and authorize only consumer `Studio::Broadcasting::Nielsen` for that purpose.

The payload is:

```json
{
  "app_id": "<Nielsen App ID>",
  "environment": "certification",
  "enabled": true
}
```

Set production only after Nielsen authorizes the app and measurement mode. Audience measurement metadata on each rundown identifies the program, episode, airdate, rights originator, and ad load. Roku DCR cloud measurement uses the provider’s OTT genre code and currently covers the dynamic-ad-load configuration. The web player asks the viewer to allow Nielsen measurement and uses the actual HLS playback clock. The first-party audience reports remain separate.

Digital TV Ratings that depend on Nielsen ID3 or watermark data require the appropriate Nielsen-approved signal and client configuration. The Digital Content Ratings adapter does not generate those signals.
