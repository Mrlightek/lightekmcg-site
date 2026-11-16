# Build and extend Nevaeh tasks

Open **Control Center → Task builder**, or `/employee/nevaeh/factory?tab=tasks`.
Use an account authorized to manage Nevaeh workflows. Keep tasks in that account;
another administrator does not inherit your phrases or worker assignments.

## Prepare a task without writing code

1. Choose an executable action and click **Use this action**. Start with the ten
   page/campaign/review actions, a Studio project, a support ticket or a caption.
   Installed, connected capabilities with scalar input schemas appear too.
   Disabled adapters, missing schemas, nested object/array inputs and ticket-only
   construction capabilities do not appear as direct actions.
   **Prepare a seven-day marketing kit** also supports a variable or fixed
   website ID; see [Marketing copilot](marketing_copilot.md) for the saved outputs
   and the distinction between preparing a kit and publishing its content.
   **Execute a saved marketing kit** and **Build a feature page and overview
   videos** take a website ID and saved kit ID. Assign the existing Campaign
   Producer or Website Operator respectively, then use the same test/review
   lifecycle before activating your own phrases.
2. Name the task and choose an existing enabled worker with the required
   capability. Select the installed manual defining the task. Do not add a role
   to manufacture an executor or expand a worker's permissions to pass the test.
3. Set fixed inputs, or leave them blank to become typed variables. For example,
   fix `site_id` to your actual website ID, leave `title` variable and use
   `prepare my service page called {title}`. Include every variable once in each
   phrase, one phrase per line. Change the words around the placeholders to add
   paraphrases. A capability's `context_site_id` supplies application context;
   its other fields become capability payload inputs.
4. Enter a literal example such as `prepare my service page called About us`,
   and independently enter `About us` as the expected title. Enter expected
   values for all variable inputs. Save the draft revision.
5. Click **Test routing & permissions**. Inspect the exact compiled command and
   persisted test evidence. The test checks the manual fingerprint, executable
   contract, typed example, assigned worker and current account permissions. It
   does not dispatch work or certify a business output. Correct any mismatch by
   saving another revision; never activate an untested revision.
6. Activate the tested revision. Type its phrase in Nevaeh, or start the literal
   prefix before the first placeholder to open the existing typed input form.
   Use Decide/Reflect to preview. Operate/Converse can dispatch the task. Read its
   action receipt and downstream worker report to confirm actual completion and
   accepted output. Inputs remain data; they cannot insert executable code.

## Reuse, revise and recover

- Download the task package to inspect or retain its phrases, typed inputs,
  worker assignment, pinned source, command and test evidence. The download is
  evidence/configuration; it is not an automatically installable executor.
- Open a saved task, change its fields and save a new revision. Keep the old
  revision active until its replacement passes testing and is activated.
  Activating a revision pauses the other active revision in that task family.
  Old rows and execution reports remain available; queued actions pinned to a
  paused revision block instead of silently adopting changed inputs.
- Pause a task to stop future execution through its binding. Pausing does not
  undo completed work. Changing its manual, adapter or worker permissions blocks
  stale execution. Review the change and save/test a new revision.
- Use `every 60 minutes, YOUR_COMPLETE_PHRASE` for an explicitly recurring task.
  It retains this task's assigned worker and the existing scheduler guards.
  Pausing its binding blocks later runs. No schedule is created merely by
  saving or activating a task.
- Keep custom task phrases specific. Several matching actions request
  clarification. Exact builder phrases take priority over generic ten-task
  interpretation when starting a new request. Finish/cancel any existing
  follow-up dialogue before starting a custom task.

## Build a missing executor

Open **Construction factory** from Task builder. Define typed inputs, supported
transformations and exact expected outputs; build and verify a release before
activating its capability and creating its ticket-workflow worker. Invoke that
worker through the existing ticket/Gatekeeper workflow. Do not call its
capability with a fabricated ticket or treat it as a direct builder action.

Add new factory primitives or domain integrations in Ruby when the existing
operations cannot perform the work. Roles, manuals and trained phrases do not
create missing executors. Task builder reuses executable contracts; neural
training and the ten-label task model remain separate, explicit workflows.
Custom builder tasks do not automatically become neural labels or durable-goal
steps. All actual dispatches retain UUID reservations, Gatekeeper enforcement,
journal read-back and typed dependency rules.

## Deploy the builder

Apply the normal database migrations before restarting Rails, then restart the
workers. The builder adds JSON configuration and verification columns to the
existing phrase bindings; existing bindings keep empty defaults and their
current behavior. No task, phrase, worker or neural model is activated by the
migration. Check one saved draft, its routing test and one real worker report
after deployment before scheduling it repeatedly.
