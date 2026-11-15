# Salah and Quran study periods

Open **Digital Factory → Salah & Study**. Configure six daily periods: **Fajr, Dhuhr, Asr, Maghrib, Isha and Tahajjud**. Each period can access the reviewed Quran source and optionally train the native neural model on approved batches.

## Use the server clock

The application server clock is the authority. The time zone is read from `Rails.application.config.time_zone`, currently **Eastern Time (US & Canada)**. The screen shows the current server time and zone. Browser time, browser location, geolocation and external prayer-time APIs are not used.

These are fixed clock appointments, not an astronomical prayer calculator. Set the six times you want and adjust them as prayer times change. Tahajjud uses its configured server clock time as well. Times are deliberately blank on a new routine so a guessed prayer timetable cannot be enabled accidentally.

## Configure a routine

1. Import and review the Quran edition in **Quran & Hadith**.
2. Open **Salah & Study**, give the routine a name and choose that source.
3. Set all six distinct clock times in 24-hour `HH:MM` format.
4. Choose a study duration of 5–60 minutes and 1–50 verses per reading session.
5. For reading only, leave neural training disabled.
6. For neural training, select an enabled model and approved batches from the same source. The source must have recorded training permission. Create, review and approve batches in the existing training workspace first.
7. Choose training epochs. Leave **Activate passing checkpoints automatically** selected for cumulative learning, or clear it to inspect and activate candidates manually.
8. Enable the routine and save.

The existing Sidekiq scheduler checks every minute. A routine is created paused by default. Enabling it during an open period permits that period to run; periods already closed are not backfilled. Each named period has a unique receipt per routine and server-local date, so repeated ticks or duplicate jobs do not repeat the reading or create duplicate training runs.

## What each period does

Reading loads the next source passages, verifies each checksum, stores their references and advances the reading position. The next period continues from that position; after the last passage, a later session starts again at the beginning. Reading receipts show exact source access, not a claim that weights changed or that the model understood the text.

When training is enabled, the session chooses the next approved batch in the saved selection order and requests real neural training through the existing worker. The batch queue cycles independently of the reading position. The optimizer records loss, vocabulary coverage, retention and checkpoint lineage. When enabled, automatic activation applies only to a passing checkpoint and rechecks routine settings, source/dataset approval, model lineage and the creator's current authority. An external checkpoint change blocks stale automatic activation.

If the trainer is already queued or running another task, this session retries inside its period without reading the same verses again. It does not create a backlog of additional competing training requests. Training candidates that fail acceptance remain candidates; a receipt reports the outcome without claiming improved knowledge or ethical reliability.

## End times, pause and recovery

A period closes at its configured duration or the next configured period, whichever comes first. Midnight-crossing periods retain the date on which they started. A missing spring-forward clock time is skipped; a repeated fall-back period runs only once. Recheck saved times after any intentional change to the server time-zone configuration.

Queued work expires at the cutoff. The scheduled optimizer checks the deadline before each gradient step; no new weight-update step starts after the cutoff. Evaluation and receipt bookkeeping may finish afterward. A partially completed epoch is not counted as a completed epoch. Existing training-time budgets still apply. Current routine authority/settings are rechecked during training, about once per second, and before automatic activation.

Use **Pause study routine** to stop future sessions and invalidate pending work. This action remains available even if a source or dataset later becomes invalid. Changing routine settings invalidates an already reserved session; the next named period uses the new settings. Existing receipts are preserved. Crashed study jobs without a linked training run can be retried after five minutes inside the remaining period. The existing training recovery sweep handles linked trainer jobs; expired queued trainers are cancelled.

## Inspect receipts

The workspace lists recent sessions, exact reading references/checksums, source identity, server zone, training-run status, checkpoint activation and any block/error. Completed reading, completed optimizer execution and accepted checkpoint activation are separate pieces of evidence.

## Deployment and checks

Run migration `20261114220000_create_nevaeh_study_routines`, then restart the application and existing Sidekiq scheduler/worker so it reloads `config/schedule.yml`. No new service or prayer-time API key is needed. The scheduled entry is `nevaeh_salah_study`.

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/nevaeh_salah_study_test.rb --name '/NevaehSalahStudyTest/'
```

The controlled persistence tests cover six periods, server-zone behavior, midnight/DST, duplicate jobs, expiry, paused/revoked work, reading continuity, trainer contention, approved neural execution, cumulative checkpoint activation, and stopping gradient updates at the period cutoff. They do not replace installed-server acceptance of its real worker/scheduler configuration.
