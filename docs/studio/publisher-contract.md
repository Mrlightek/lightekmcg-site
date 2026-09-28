# Studio publisher contract

A publisher adapter accepts a `StudioPublication` and owns platform-specific API transport only.

It must not:

- store raw credentials in Studio records;
- bypass Gatekeeper authorization;
- mutate the source artifact;
- treat upload acceptance as proof of final publication when the platform is asynchronous.

It may:

- check out scoped credentials through `Studio::Credentials`;
- upload an artifact;
- create platform metadata/captions;
- return external IDs/URLs;
- report asynchronous state for later reconciliation.

The initial registry reserves TikTok, Instagram, Facebook, Lightek Social, and Lightek Streaming.
