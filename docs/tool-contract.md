# Tool contract

## Conventions

All tool names use the `spec_kitty_` prefix to avoid collisions in hosts with
multiple MCP servers. Inputs are JSON objects with `additionalProperties:
false`. Common identifiers use these shapes:

| Field | Type | Meaning |
|---|---|---|
| `mission` | string | Spec Kitty mission slug |
| `wp` | string | Work-package identifier such as `WP01` |
| `actor` | string | Auditable identity requesting a mutation |
| `note` | string | Human-readable audit note |

The server binds to a project root at startup; tools do not accept a path.

Successful calls return the complete Spec Kitty JSON envelope as structured
content. A compact text rendering may accompany it for clients that do not yet
display structured content. Spec Kitty envelopes with `success: false` are
returned with MCP `isError: true`, while preserving `error_code` and
`correlation_id`.

## Tool catalog

### `spec_kitty_contract_version`

Checks compatibility with the Spec Kitty orchestrator API.

| Input | Type | Required | Notes |
|---|---|:---:|---|
| `provider_version` | string | No | Defaults to the adapter version |

Maps to `orchestrator-api contract-version --provider-version ...`.

### `spec_kitty_mission_state`

Returns every work package, lane, dependency, and mission summary exposed by
Spec Kitty.

| Input | Type | Required |
|---|---|:---:|
| `mission` | string | Yes |

### `spec_kitty_list_ready`

Returns planned work packages whose dependencies satisfy Spec Kitty's ready
rules.

| Input | Type | Required |
|---|---|:---:|
| `mission` | string | Yes |

### `spec_kitty_resolve_workspace`

Resolves the lane workspace and prompt for an existing work package without
allocating, creating, cleaning, or transitioning anything.

| Input | Type | Required |
|---|---|:---:|
| `mission` | string | Yes |
| `wp` | string | Yes |

This tool requires Spec Kitty orchestrator contract support for
`resolve-workspace` and is omitted from `tools/list` when unavailable.

### `spec_kitty_start_implementation`

Requests Spec Kitty's atomic, idempotent
`planned -> claimed -> in_progress` operation.

| Input | Type | Required |
|---|---|:---:|
| `mission` | string | Yes |
| `wp` | string | Yes |
| `actor` | string | Yes |
| `policy` | policy object | Yes |

The response may identify a workspace and prompt path. Their meaning remains
defined by Spec Kitty; the MCP server does not manually create Git worktrees.

### `spec_kitty_start_review`

Claims a work package review through Spec Kitty.

| Input | Type | Required |
|---|---|:---:|
| `mission` | string | Yes |
| `wp` | string | Yes |
| `actor` | string | Yes |
| `policy` | policy object | Yes |
| `review_ref` | string | No |

### `spec_kitty_transition`

Requests one explicit lane transition.

| Input | Type | Required | Notes |
|---|---|:---:|---|
| `mission` | string | Yes | |
| `wp` | string | Yes | |
| `to` | string | Yes | Target lane; validated by Spec Kitty |
| `actor` | string | Yes | |
| `note` | string | No | |
| `policy` | policy object | Conditional | Required for run-affecting lanes |
| `review_ref` | string | No | |
| `review_result` | object | No | Serialized to `--review-result-json` |
| `evidence` | object | No | Serialized to `--evidence-json` |
| `subtasks_complete` | boolean | No | Adds its flag only when true |
| `implementation_evidence_present` | boolean | No | Adds its flag only when true |

The initial release intentionally does not expose `--force`.

### `spec_kitty_append_history`

Appends an auditable work-package history entry through Spec Kitty.

| Input | Type | Required |
|---|---|:---:|
| `mission` | string | Yes |
| `wp` | string | Yes |
| `actor` | string | Yes |
| `note` | string | Yes |

### `spec_kitty_accept_mission`

Requests mission acceptance after Spec Kitty validates that all work packages
are approved or done.

| Input | Type | Required |
|---|---|:---:|
| `mission` | string | Yes |
| `actor` | string | Yes |

### `spec_kitty_merge_mission`

Runs Spec Kitty's merge preflights and merge operation.

| Input | Type | Required | Default |
|---|---|:---:|---|
| `mission` | string | Yes | — |
| `target` | string | No | Spec Kitty auto-detection |
| `strategy` | `merge`, `squash`, or `rebase` | No | `merge` |
| `push` | boolean | No | `false` |

This tool has destructive potential. A host should require confirmation,
especially when `push` is true. The adapter does not add retries.

## Policy object

Run-affecting operations pass a structured policy object with the fields
required by Spec Kitty:

| Field | Type | Required |
|---|---|:---:|
| `orchestrator_id` | string | Yes |
| `orchestrator_version` | string | Yes |
| `agent_family` | string | Yes |
| `approval_mode` | string | Yes |
| `sandbox_mode` | string | Yes |
| `network_mode` | string | Yes |
| `dangerous_flags` | array of strings | Yes |
| `tool_restrictions` | string or null | No |

The adapter validates this object, serializes it once, and passes the resulting
JSON as the `--policy` argv value. It never logs policy contents. Spec Kitty's
own validation remains authoritative.

## Error rules

| Condition | MCP representation |
|---|---|
| Unknown MCP method or tool | JSON-RPC error |
| Malformed tool arguments | JSON-RPC invalid-params error |
| Spec Kitty `success: false` envelope | Tool result with `isError: true` and preserved envelope |
| Spec Kitty success envelope | Tool result with `isError: false` and preserved envelope |
| Timeout | Tool result with `isError: true`; outcome marked indeterminate for mutations |
| Invalid or mixed child stdout | Tool result with `isError: true`; bounded diagnostics only |
| Adapter defect | JSON-RPC internal error |

The adapter must not infer success solely from exit code zero or failure solely
from a nonzero exit code. A valid Spec Kitty envelope is the primary command
contract.
