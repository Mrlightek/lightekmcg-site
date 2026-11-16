# Page specialists and Nevaeh as manager

Nevaeh uses the Dashboard page as the task boundary. A page contract identifies the available services, typed inputs, current application or scene, specialist role, documentation source and execution receipts. Nevaeh coordinates; the page specialist delegates to the existing service and retains its result.

## Use a page task

Open Nevaeh from a Dashboard page. **Tasks for this page** lists services with a registered native adapter, a reviewed input schema and a matching enabled specialist. Choose a task, provide its missing inputs and select **Delegate to …**. Selecting a task does not execute it.

Application and scene IDs already known from the page are filled automatically. If only one application is accessible and the task needs an application, it is selected automatically. Otherwise provide the actual application ID. Form values are not harvested from unrelated Dashboard inputs. Account permissions are checked again by the service; page context never grants access.

Supported short phrases can select a page task too. In Communications, “show messages” delegates to the Mail Operator when the application is already known. In Studio, “create a project” asks for the missing project name. Those phrases are matched against the current page's registered task set. Unknown or ambiguous phrases keep the normal conversational/documentation path.

The same task form appears in the shared workspace when Nevaeh needs inputs. It uses the page or Studio scene currently brought into that workspace. **Decide** and **Reflect** show a proposed task without dispatching it. Explicit commands remain available in the command reference.

## Specialists and their work

| Page/service family | Specialist | Examples with reviewed schemas |
| --- | --- | --- |
| Mail and messaging | Mail Operator | List/open conversations, list people, mark a conversation read |
| Finance / Susu | Finance Operator | List/open groups, contribution quote and checkout |
| Studio projects and workspaces | Studio Workspace Operator | Create a project, list assets, inspect runtime and writing profiles, save declared workspace inputs |

The directory now includes 28 default roles. These are task identities and capability assignments, not a separate language model running for every page. Existing roles retain their customizations. A page task reuses an existing saved instruction when its page, specialist, inputs and contract match; each new explicit request gets its own run and receipt. Paused roles/tasks remain paused, and deleted roles are not silently restored.

Each task follows the existing manager action → specialist assignment/run → operating action → native service receipt chain. **Queued** means submitted. The result is complete only when the downstream service reports completion. These tasks appear in **Workforce & goals** with the page area and service name.

## Knowledge stays tied to execution

A task fingerprint binds the signed-in account, page/application context, service schema and handler binding, specialist key, and the current page guide's SHA-256. Before dispatch and again when executing, Nevaeh rechecks the contract, specialist, payload and account authority. Changed schemas/bindings/manuals and paused/deleted specialists stop stale work and require a fresh request.

Forms submit typed values rather than inventing command payloads from prose. Whole numbers, finite numbers, booleans, JSON objects and arrays are checked before work is dispatched. A task tied to the current application cannot be redirected to another application by changing its form payload. Unchanged form retries reuse their request key; changing inputs creates a new request.

## Expand coverage page by page

**Workflows need page contracts** lists registered workflows that lack a reviewed schema, enabled adapter or assigned page specialist. Built-in command examples remain documented workflows until a typed page contract is added; a manual alone does not make its workflow executable through this form.

The first release exposes typed tasks from the existing native capability registry, including declared input schemas added there. It does not certify that every Dashboard operation has a page worker. To expand a page: connect its actual service, register its input schema, assign the specialist's capability scope, document the workflow and verify its downstream result. This lets the same manager reuse the page's accumulated knowledge without guessing how its features work.

See [SME reports and lessons](worker_reports.md) for each specialist’s accumulated experience and owner feedback. Page-task contracts themselves need no migration; the reports feature has its own migration. Restart Rails/workers after deployment. Open the assistant again to refresh its contract and current page inputs.
