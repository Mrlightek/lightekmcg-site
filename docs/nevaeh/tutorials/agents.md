# Agents, delegation and scheduled workers

An agent has a persistent identity, instructions, enabled state, autonomy mode and optional capability restrictions. The agent's owner remains the authority for every task. Empty capability assignments inherit the owner's permitted actions.

## Delegate your first task

```text
/agents
/delegate sage susu.list
/status
```

This creates a real agent worker and a run snapshot. The receipt follows the agent action into Dispatch. In the Agent workforce panel, inspect the last status and use Run or Pause. Selecting an agent before issuing an ordinary executable command also records that agent on the action.

## Repeat a saved instruction

```text
/agent schedule warden 60 susu.list
/agent run WORKER_ID
/agent pause WORKER_ID
```

The interval is minutes, with a minimum of five. A schedule repeats the saved inputs; it does not test whether data changed. Scheduling explicitly enables scheduled autonomy. Use a watcher when a change should trigger the action.

Pausing stops future runs. It does not cancel work already submitted or undo results. A paused agent, lost owner permission or a failed/blocked prior run prevents future scheduled execution and requires attention.

## Restrict an agent

Read `/read agents` to obtain its record ID, then update it. For a watcher agent that can observe and plan package changes:

```text
/update agents AGENT_ID {"allowed_capabilities":["watcher.poll","ubuntu.plan"]}
```

A watcher with automatic package setup also needs `ubuntu.setup`. Restrictions use exact names or prefixes such as `studio.*`. Changing an agent's assignments is checked again at execution. Restrictions never grant capabilities the account lacks.

## Build a structured worker

Administrators can create a caption worker:

```text
/create workers {"name":"Opening night caption","status":"active","sections":[{"id":"caption","action":"content.generate","inputs":{"format":"caption","context":{"topic":"Opening night"}},"depends_on":[]}]}
/run WORKER_ID
/delegate muse /run WORKER_ID
```

Replace WORKER_ID with the created ID. Structured workers use the existing ticket and acceptance pipeline. Control Center provides the visual builder. Agent workers can call these structured workers as part of the same operating environment.
