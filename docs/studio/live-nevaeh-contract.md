# Nevaeh live operations contract

Nevaeh should receive capabilities, never raw platform credentials.

Initial capability namespace:

```text
studio.live.start
studio.live.end
studio.live.respond_to_comment
studio.live.hide_comment
studio.live.pin_comment
studio.live.trigger_scene
studio.live.play_asset
studio.live.publish_link
studio.live.update_lower_third
studio.live.read_stream_health
```

A live session loads show format, approved talking points, moderation rules, response policy, platform policy, campaign context, and relevant KB procedures. Known situations can be handled through approved capabilities. Unknown or ambiguous situations should enter the existing trouble-ticket and knowledge-capture loop.

TikTok is the first external live target. The same capability contract is intended to support Instagram, Facebook, and the future native Lightek Social live stack without changing Nevaeh's reasoning contract.
