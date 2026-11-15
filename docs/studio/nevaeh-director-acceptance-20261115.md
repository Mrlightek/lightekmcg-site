# Nevaeh Director acceptance — November 15, 2026

This is local implementation evidence, not production deployment or live social-account acceptance.

## Focused automated results

| Suite | Tests | Assertions | Result |
| --- | ---: | ---: | --- |
| Nevaeh OS | 52 | 596 | Passed |
| Campaign producer | 7 | 65 | Passed, including real MP4 rendering |
| Recipe Director | 7 | 66 | Passed with real local English/Arabic speech enabled |
| Episode finishing | 10 | 75 | Passed, including real 1080p episode concatenation and audio probing |
| Story workers and continuity | 5 | 38 | Passed, including actual saved worker/run/action handoffs |
| Social transports | 6 | 34 | Passed against controlled HTTP boundaries |
| Manual conversation regression | 7 | 29 | Passed |
| Existing native publication regression | 1 | 6 | Passed |
| **Ruby total** | **95** | **909** | **No failures, errors or skips** |
| JavaScript task input/review receipt tests | 3 | — | Passed |

Real eSpeak NG testing used the installed local speech binary with `DIRECTOR_TEST_REAL_SPEECH=1`. Integration harnesses use SQLite/Active Storage and controlled host/provider boundaries; the complete private-engine application suite was not run. Older umbrella harness fixture failures are outside this focused result.

## Real Blender execution

`blender --background --factory-startup --python-exit-code 1 --python test/operations/studio_spatial_blender_checks.py`

Verified with Blender 4.3.2:

1. Reciprocal speaker facing, authored motion, a parent-relative camera, perspective projection and tracked focal depth.
2. Personal-space violations and explicit close-contact exceptions.
3. Character mesh collision detection.
4. Environment collision, including a solid enclosing a character.
5. Registered head-bone eyeline mismatch stopping the shot.

These are scene and geometry checks. They do not establish a full rigid-body simulator, collision avoidance, continuous subframe detection or artistic final acting.

## Browser checks

Playwright/Chromium checked the rendered workspace at 1440×1000 and 390×844: connected state, draft starters, request/response display, agent dialog, no JavaScript exceptions or horizontal overflow. Screenshots were inspected and a mobile composer overlap was corrected.

The Studio social form was exercised with controlled connected-account responses: account choice, live creator options, no preselected TikTok privacy, disabled creator interactions, explicit review, and typed publication inputs. No live provider credentials or social posts were used.

## Runtime acceptance still required

Deploy the updated host/worker code and Studio media image. Configure/reconnect social accounts and required app scopes/host verification. Review an actual registered character/set and a finished episode on the production worker. Run a deliberately reviewed small social test through approved provider accounts before using full campaigns. Publisher receipts distinguish processing, confirmed publication, failure and uncertain outcomes.

Operating guides: [Director](../nevaeh/tutorials/production_director.md), [Story simulation and spatial direction](../nevaeh/tutorials/story_simulation.md), [Social delivery](../nevaeh/tutorials/social_delivery.md).
