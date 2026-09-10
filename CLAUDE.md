# CLAUDE.md — tarot

Shared Runik concepts live in the [root guide](../../../CLAUDE.md). This file documents only Tarot's workflow-composition contract.

## Responsibility

Tarot turns a **reading** into a self-contained Argo `WorkflowTemplate`. It composes reusable **cards**, validates their contracts and dependencies, and renders the execution RBAC and workflow-owned storage/configuration.

Tarot does not own event infrastructure. `EventSource` and `Sensor` remain responsibilities of the `argo-events` glyph.

## Registration and value routing

Register Tarot under its own Librarian key:

```yaml
trinkets:
  tarot:
    key: tarot
    repository: ...
    path: .
    revision: upstream
```

Librarian passes the effective `tarot` subkey plus the ordinary `spellbook`, `chapter`, and `lexicon` contexts. It does not interpret readings or cards.

Tarot resolves its configuration with this precedence:

```text
chart defaults < spellbook.tarot < chapter.tarot < spell.tarot
```

`tarot.cards` follows the same scoped merge. There is no global card registry, `appendix.cards`, library, or deck.

## Model

- A **card** is one reusable executable definition.
- A **reading** arranges card executions into a process.
- A reading entry uses a reusable card with `uses`, or declares one inline implementation.
- `depends` defines ordering explicitly; Tarot rejects missing dependencies and cycles.
- `with` and `artifacts` bind the inputs accepted by the card contract.

A card resolves to exactly one implementation:

| Implementation | Meaning |
|---|---|
| `container` | Native Kubernetes container definition |
| `script` | Native Argo script template |
| `resource` | Native Argo resource template |
| `suspend` | Native Argo suspension |
| `ref` | Existing `WorkflowTemplate` or `ClusterWorkflowTemplate` template |

Reusable cards may declare `contract.inputs` and `contract.outputs`. The supported contract groups are `parameters`, `artifacts`, and `secrets`. Workflow resources such as secrets, ConfigMaps, and volumes belong under `tarot`, not inside individual cards.

## Retention and lifecycle

Tarot applies workflow retention policy at the invocation level. Both fields
are native Argo `WorkflowSpec` values and follow the ordinary Tarot precedence:

```yaml
tarot:
  ttlStrategy:
    secondsAfterSuccess: 86400
    secondsAfterFailure: 604800
  podGC:
    strategy: OnWorkflowCompletion
    deleteDelayDuration: 30m
```

The chart defaults retain successful Workflow objects for one day and failed
ones for seven days. Pods are removed thirty minutes after the Workflow
completes. A spellbook, chapter, or spell may override either policy; setting
a policy to `null` disables that default.

Retention is not process cleanup. A reading that must release locks, remove
workspace data, or publish its final state declares one exit card execution:

```yaml
tarot:
  cards:
    finalize:
      contract:
        inputs:
          parameters:
            status: {required: true}
      container:
        image: alpine:3.22
        command: [sh, -c]
        args: ['echo "workflow finished: {{inputs.parameters.status}}"']
  reading:
    onExit:
      uses: finalize
      with:
        status: "{{workflow.status}}"
    cards:
      run:
        container:
          image: alpine:3.22
          command: [sh, -c]
          args: ["do-work"]
```

`reading.onExit` runs after the main reading for success, failure, or error.
It accepts one reusable or inline card execution and may bind parameters and
secrets, but it cannot depend on DAG cards or consume their artifacts.

## Readings

### Local or inherited reading

```yaml
tarot:
  cards:
    greet:
      contract:
        inputs:
          parameters:
            message: {required: true}
      container:
        image: alpine:3.22
        command: [sh, -c]
        args: ["echo {{inputs.parameters.message}}"]

  with:
    message: hello

  reading:
    inputs:
      parameters:
        message: {required: true}
    cards:
      hello:
        uses: greet
        with:
          message: "{{workflow.parameters.message}}"
```

A scope may define one `defaultReading`. An invocation without `reading` inherits the effective default. This is the short path for the organizational CI/CD reading; it does not make other processes global defaults.

An inherited or local reading may expose named `extensionPoints`. `tarot.extend.<point>.cards` inserts a subgraph between that point's `after` and `before` boundaries without replacing the base reading.

### Selecting a published reading

Named organizational readings publish only a small reference in `appendix.lexicon`:

```yaml
appendix:
  lexicon:
    organization-ci:
      type: tarot-reading
      labels:
        process: ci
        profile: standard
        version: v1
      scope: namespace
      namespace: organization-ci
      template: main
      contract:
        inputs:
          parameters:
            repository: {required: true}
```

Another spell selects it explicitly:

```yaml
tarot:
  reading:
    selector:
      process: ci
      profile: standard
      version: v1
  with:
    repository: ssh://git@example/apps/service.git
```

The lexicon entry is the reference: its key supplies `name`, while `scope`, `namespace`, `template`, and `contract` are direct fields. The cards and complete reading never enter the lexicon. Selection requires one exact match; lexicon fallbacks are rejected for named readings. Selected readings cannot be extended by the caller.

A namespaced reading can only be selected from that same namespace. Use
`scope: cluster` only for an independently provided
`ClusterWorkflowTemplate`; Tarot-composed readings are namespaced.

## Execution modes

| Mode | Shape | Use |
|---|---|---|
| `dag` | One Argo DAG task per card | Independent pods, template references, artifacts and per-card policies |
| `containerSet` | All cards are containers in one pod | Shared volumes and lower pod overhead |

`containerSet` accepts only native `container` cards. It does not support template references, template arguments, artifacts, `when`, or per-card retry/timeout because those are not representable with the same semantics inside one pod.

## Event-driven execution

A workflow owner publishes a `workflow-trigger` reference. Its `sensorSelector` points back to the single infrastructure-owned Sensor, while `readingSelector` resolves the target `tarot-reading`:

```yaml
appendix:
  lexicon:
    service-ci-trigger:
      type: workflow-trigger
      sensorSelector:
        source: forgejo
        purpose: workflow-execution
      readingSelector:
        process: ci
        profile: standard
        version: v1
      parameters:
        repository:
          from: body.repository.ssh_url
```

During Sensor rendering, the `argo-events` glyph performs the inverse lookup and adds every matching trigger. Librarian only delivers the consolidated lexicon. This extends one Sensor rather than creating a Sensor per workflow.

The Sensor ServiceAccount still needs permission to submit the resulting workflow. Bind it with `tarot.rbac.triggerServiceAccounts` on the reading owner.

## Generated resources

Tarot renders:

- one namespaced `WorkflowTemplate` for a composed or selected reading;
- the runner ServiceAccount and execution RBAC when enabled;
- declared Secrets, ConfigMaps, and PVCs.

The generic `workflow.template` glyph supplies the WorkflowTemplate resource envelope. Tarot owns composition; the glyph does not interpret cards or readings.

## Testing

The files under `examples/v2-*.yaml` cover reusable and inline cards, selected readings, default extension, executable kinds, and both execution modes. Render them through the repository Make targets.
