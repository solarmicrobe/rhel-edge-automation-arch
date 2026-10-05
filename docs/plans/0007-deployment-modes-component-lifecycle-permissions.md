# Plan 0007: Deployment Modes, Component Lifecycle, and Permissions

## Status

GitOps/permission/ODF checkpoint implemented and reviewed on the `custom` branch. The bounded Virtualization
connection checkpoint below extends lifecycle ownership to CNV platform objects and retained VM DataSource wiring.
Broader component lifecycle migration remains deferred.

Checkpoint `values-doc-examples` locks the values API names and semantics below. The first implementation checkpoint
wires those names only where needed to prove GitOps permission ownership and ODF lifecycle behavior before broader
component migration.

## Goal

Make the repository's top-level deployment intent explicit: deploy an RFE workload stack managed by a configured GitOps
platform, with a preferred modern path that creates a namespace-scoped RFE ArgoCD and manages only the least-privilege
permissions and component objects required for that stack.

The same model must support BYO cluster ArgoCD, BYO namespace ArgoCD, and repository-created namespace ArgoCD without
silently installing shared platform services or mutating BYO components.

## Governing Context

- [ADR 0001: Modern RFE Architecture Direction](../adr/0001-modern-rfe-architecture.md)
- [Current State Inventory](../current-state-inventory.md)
- [Plan 0001: ArgoCD Targeting, AppProject, and Access Separation](0001-argocd-targeting-appproject-access.md)
- [Plan 0002: Image Builder VM DataSource Modernization](0002-image-builder-datasource-modernization.md)
- [Plan 0003: BuildConfig Inventory and Retirement](0003-buildconfig-inventory-retirement.md)
- [Plan 0004: Artifact Publication Endpoint Modernization](0004-artifact-publication-endpoint-modernization.md)
- [Plan 0005: No-VM Artifact Workflow Evaluation](0005-no-vm-artifact-workflow-evaluation.md)
- [Plan 0006: RHEL Target and Runtime Boundary](0006-rhel-target-runtime-boundary.md)

## Accepted Decisions

- The main purpose is to deploy an RFE workload stack managed by a GitOps platform.
- The GitOps platform may be BYO cluster-scoped ArgoCD, BYO namespace-scoped RFE ArgoCD, or repository-created
  namespace-scoped RFE ArgoCD.
- The preferred modern default is repository-created namespace-scoped RFE ArgoCD.
- BYO ArgoCD modes default to externally managed permissions.
- Repository-created RFE ArgoCD defaults to repository-managed least-privilege permissions.
- Anything that can reasonably be used by other workloads should support `managed | byo | disabled` where it is in the
  RFE dependency graph.
- ODF is the model shared component: use BYO when existing storage is present, or managed installation when the cluster
  needs this repo to stand up required storage.
- Creating objects inside a BYO component must have explicit opt-in switches. BYO must not imply setup jobs,
  repositories, buckets, users, or other mutations.
- The Image Builder VM remains retained and DataSource-backed.
- Future artifact workflow changes should avoid rebuilding images or artifacts when existing configured sources are
  sufficient.

## Scope

### 1. Deployment Mode Defaults

Define the values contract for the top-level deployment mode.

```yaml
deployment:
  mode: managed-rfe-argocd
```

Allowed values:

| Value | Meaning |
|:------|:--------|
| `managed-rfe-argocd` | Preferred modern mode. This repository creates and manages the namespace-scoped RFE ArgoCD control plane and renders the RFE workload stack into it. |
| `byo-cluster-argocd` | The cluster already has a shared or cluster-level ArgoCD control plane. This repository may target it, but must not install or mutate the control plane unless an explicit BYO object switch allows a named integration object. |
| `byo-rfe-argocd` | The RFE namespace already has an ArgoCD control plane. This repository may target it, but must not install or mutate the control plane unless an explicit BYO object switch allows a named integration object. |
| `reference-full-stack` | Compatibility mode for the historical reference environment that installs the broad managed stack used by the existing examples. New modern examples should not use this unless they intentionally demonstrate the legacy reference path. |

The implementation should preserve existing rendered behavior where compatibility requires it, but modern examples
should prefer `managed-rfe-argocd`.

### 2. Permission Ownership

Add a top-level switch that controls whether this repository renders permission resources.

```yaml
permissions:
  mode: auto
```

Allowed values:

| Value | Meaning |
|:------|:--------|
| `auto` | Resolve permission ownership from `deployment.mode`. |
| `managed` | Render this repository's least-privilege, capability-scoped permission resources. This must not imply default `cluster-admin`. |
| `external` | Do not render permission resources owned by this repository; the platform owner or existing GitOps administrator provides them. |

`auto` should resolve to:

- `external` for BYO ArgoCD modes;
- `managed` for `managed-rfe-argocd`;
- explicit historical reference behavior for `reference-full-stack`.

Managed permissions must remain least-privilege and capability-scoped. Do not introduce default `cluster-admin`.

### 3. Component Lifecycle

Introduce a lifecycle shape for shared and RFE-owned components:

```yaml
components:
  odf:
    mode: byo
    connection: {}
```

Allowed `components.<name>.mode` values:

| Value | Meaning |
|:------|:--------|
| `managed` | This repository owns installation or rendered component objects for the component, plus downstream wiring required by the RFE stack. |
| `byo` | The component already exists. This repository consumes `components.<name>.connection` values and does not install or mutate the component. |
| `disabled` | This repository neither installs nor references the component. Dependent workflows must also be disabled or configured to use another component. |

Lifecycle mode is intentionally limited to ownership state. It must not carry a generic BYO mutation switch such as
`components.<name>.byo.createObjects`. When a BYO component needs this repository to create an integration object, the
value must be named for the object or integration being created, such as `argocd.appProject.create`, a future
`objectStorage.bucketClaims.create`, or a component-specific patch flag. Object-specific create switches must default
to `false` in BYO mode unless an explicit mode rule says otherwise.

The first implementation set is intentionally narrow:

- `components.gitops`: the ArgoCD/GitOps control plane selected by `deployment.mode`;
- `permissions`: top-level permission ownership for the GitOps and workload access layer;
- `components.odf`: the model shared component for lifecycle and connection semantics.

Later implementation should extend the same shape to components that directly affect current workflows and existing plan
boundaries:

- OpenShift Virtualization and Image Builder VM;
- OpenShift Pipelines;
- Quay or external registry;
- Nexus produced-artifact storage;
- HTTPD serving/runtime target.

### 4. BYO Object Creation

Separate component connection from component mutation.

Examples:

- BYO GitOps may provide an ArgoCD namespace, project name, and controller service account. Creating GitOps objects such
  as `AppProject` resources requires the existing object-specific `argocd.appProject.create: true`; permission grants
  are still controlled by `permissions.mode`.
- BYO ODF may provide bucket or storage-class details without creating ODF itself.
- BYO Quay or registry may provide a pre-created image path without creating organizations or repositories.
- BYO Nexus may provide credentials and repository URLs without running setup jobs.
- BYO ArgoCD may receive `Application` resources without this repo creating control-plane RBAC unless permissions are
  explicitly managed.

Every BYO object-creation switch should be object-specific and should default to false unless a mode-specific `auto`
rule intentionally resolves it to true. Do not add a generic `components.<name>.byo.createObjects` switch.

### 5. Artifact Rebuild Avoidance

When workflows can consume an existing source image or artifact, prefer that over rebuilding.

The first pass should inventory current rebuild assumptions and map them to lifecycle or endpoint values. Avoid
rewriting the artifact model in this slice unless a narrow values change is required to stop an unnecessary rebuild.

### 6. Checkpoint Examples

Focused values API examples for this checkpoint live in:

- `examples/values/deployment-mode-managed-rfe-argocd.yaml`
- `examples/values/deployment-mode-byo-cluster-argocd.yaml`
- `examples/values/deployment-mode-byo-rfe-argocd.yaml`
- `examples/values/deployment-mode-reference-full-stack.yaml`

These examples prove the top-level shape and naming. The first implementation checkpoint wires only the GitOps
permission boundary and `components.odf` lifecycle subset; later units must extend the same lifecycle and
object-specific creation rules to the broader component set.

## Non-Goals

- Do not replace the retained Image Builder VM or current Image Builder/composer runtime.
- Do not implement a bootc/image-mode workflow.
- Do not redesign artifact publication beyond lifecycle/endpoint switches needed by this plan.
- Do not remove managed reference paths that are still needed for compatibility.
- Do not run cluster-mutating validation without explicit user approval.
- Do not commit generated `temp/` manifests or secret material.

## Verification Strategy

Use Helm rendering as the primary verification.

Minimum checks should include:

```sh
helm template bootstrap charts/bootstrap --namespace rfe-gitops
helm template application-manager charts/application-manager --namespace rfe-gitops
helm template argocd-integration charts/argocd-integration --namespace rfe-gitops
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
git diff --check
```

Add negative render checks for invalid deployment modes, invalid permission modes, and missing BYO connection values
for every component lifecycle value implemented in this slice.

For the documentation/example portion of this checkpoint, validation is limited to non-mutating local checks:

```sh
ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_file(f) }; puts "ok"' examples/values/deployment-mode-*.yaml
git diff --check
```

Chart implementation units must add schema or template validation that rejects:

- `deployment.mode` outside `managed-rfe-argocd | byo-cluster-argocd | byo-rfe-argocd | reference-full-stack`;
- `permissions.mode` outside `auto | managed | external`;
- `components.<name>.mode` outside `managed | byo | disabled`;
- missing required `components.<name>.connection` values when a component is `byo` and downstream workflows need it.
- object-specific creation flags with non-boolean values.

## Risks

- The existing examples still encode the old reference full-stack deployment deeply.
- A broad lifecycle model can become too large if every component is migrated at once.
- Some charts currently use local flags such as `disabled`, `buildConfig.enabled`, `publicationEndpoints.*.mode`, and
  `legacyPvcSource.enabled`; the plan should align these without rewriting unrelated behavior.
- Permission ownership can accidentally overlap with existing RBAC charts unless the implementation chooses a clear
  boundary.
- External/BYO artifact sources can bypass rebuilds only when existing workflows already have enough endpoint and
  credential information to consume them safely.

## Open Decisions

- Resolved by checkpoint `values-doc-examples`: use `deployment.mode`.
- Resolved by checkpoint `values-doc-examples`: use `permissions.mode`.
- Resolved by checkpoint `values-doc-examples`: first set is `components.gitops`, `permissions`, and
  `components.odf`.
- Resolved after checkpoint review: do not use generic `components.<name>.byo.createObjects`; keep lifecycle to
  `components.<name>.mode` plus `connection`, and use object-specific create flags for any BYO mutation.

## Reviewed Continuation Checkpoint (2026-10-02)

The first component set remains `components.gitops`, GitOps permission ownership, and `components.odf`.
Review found that the original ArgoCD/ODF checkpoint did not connect the values API to Application Manager or
ArgoCD Integration. This continuation closes that boundary without migrating the remaining shared services.

Implemented behavior:

- `components.gitops.mode` must agree with the deployment mode (`managed` for managed/reference deployments,
  `byo` for BYO deployments), or be `disabled`. Disabled GitOps renders no control-plane/integration resources;
  Application Manager rejects it when workload Applications are configured.
- GitOps `connection.namespace`, `project`, and `server` supply Application targeting and integration targeting.
  Application-specific overrides still take precedence. Existing `argocd.target` values remain supported by
  Application Manager and ArgoCD Integration. The install chart requires the explicit connection for BYO mode.
- Application Manager forwards deployment, permission, and component values to the first component set and nested
  Application Managers. It uses the actual chart path, including `common.chartPath`, and does not forward this
  contract to external Helm repository charts or unrelated workload charts. Parent ownership values override child
  ownership values; other child values are preserved.
- For a generated Bootstrap Application, the same boundary is also forwarded into its `application-manager` and
  `argocdIntegration` dependency values. When rendering Bootstrap directly, Helm's normal subchart scoping applies:
  put the boundary under those keys. Root Bootstrap values alone do not configure its dependencies.
- `permissions.mode=auto` resolves to external for BYO and managed for managed/reference deployment modes.
  External ownership suppresses integration Roles, RoleBindings, ClusterRoles, and ClusterRoleBindings even if
  their local creation flags are enabled. Managed ownership permits the existing explicit grant flags; it does
  not automatically enable them. Controller identity can come from `connection.controllerServiceAccount`.
- Namespace grant defaults enumerate RFE workload resources and verbs instead of wildcard API/resource access.
  Operators must scope grant namespaces and adjust rules for additional workload kinds. Named cluster capabilities
  remain explicit. No default path grants `cluster-admin`; the historical reference grant still requires explicit
  `argocd.clusterAdmin.create=true` and targets the configured control-plane namespace.
- `argocd.appProject.create` stays an independent boolean opt-in, including under external permission ownership.
  Grant creation flags and the reference cluster-admin flag also reject non-boolean values.
- ODF BYO/disabled renders remain empty and BYO storage-class validation is retained. No bucket creation switch or
  broader storage consumer migration is introduced here.

Verification: `ruby tests/plan0007-render.rb` runs positive and negative local Helm renders and manifest assertions
for the above boundary, the four deployment examples, ODF lifecycle, retained VM DataSource sourcing, and configured
runner-image reuse. Bootstrap checks rebuild local file dependencies in a temporary chart copy, remove copied
symlinks, and use non-secret SSH fixtures because this checkout has broken local credential symlinks. No generated
manifests or credentials are committed. `git diff --check` is also required.

Remaining scope: OpenShift Virtualization, Pipelines, registry, Nexus, HTTPD, Image Builder VM lifecycle, broader
workflow dependency validation, and deployment entry-point automation still need separate bounded migration units.
This checkpoint does not claim an end-to-end modern full-stack deployment or live-cluster validation.

## Virtualization Connection Checkpoint (2026-10-04)

This bounded unit adds `components.virtualization.mode: managed | byo | disabled` to `charts/cnv` and
`charts/image-builder-vm`. Managed is the compatibility default. CNV managed rendering retains its Namespace and
HyperConverged manifests, including the former namespace dependency's labels. BYO and disabled CNV render no
resources. BYO CNV requires the nonempty string `components.virtualization.connection.namespace` identifying the
existing platform; its optional `connection.dataSource.name` and `namespace` must be nonempty strings when supplied.

The retained managed VM consumes `components.virtualization.connection.dataSource.name` and `namespace` ahead of
`imageBuilderVM.dataSource`. With no connection override, its existing DataSource defaults remain unchanged.
BYO virtualization with `imageBuilderVM.dataVolumeSource=datasource` requires both connection DataSource fields
explicitly, rather than silently relying on managed reference defaults. The VM rejects disabled virtualization.
The explicit legacy PVC source (`dataVolumeSource=pvc` plus `legacyPvcSource.enabled=true`) remains supported and
does not require DataSource connection fields because it does not consume a DataSource. VM lifecycle ownership is
still deferred; BYO virtualization does not mean BYO Image Builder VM. The repository still creates the VM and
runs its guest setup Job; BYO virtualization only suppresses CNV platform resources.

Application Manager forwards the existing ownership boundary to the actual `charts/cnv` and
`charts/image-builder-vm` paths, including `common.chartPath`. Parent ownership values take precedence and other
child values remain intact. No virtualization platform setup objects or generic BYO mutation flags are added.
The historical `cnv-operator` Application uses the separate generic operator subscription chart: users choosing
BYO or disabled virtualization must explicitly disable that Application in their deployment values. This unit
controls CNV platform objects and VM boot-source wiring; it does not implicitly suppress operator installation.

The focused example is `examples/values/virtualization-byo-datasource.yaml`. Local verification compares managed
CNV and VM manifests against the starting revision and exercises lifecycle validation, empty BYO output, required
connections, invalid enum/type values, DataSource overrides, disabled dependency rejection, legacy PVC compatibility,
and Application Manager forwarding. The original 58 render checks remain included. No cluster commands are run.

Remaining scope: VM lifecycle, Pipelines, registry, Nexus, HTTPD, broader workflow dependency validation, operator
entry-point selection, and modern deployment entry-point automation. This unit does not claim full Plan 0007
completion or live-cluster validation.

## Image Builder Guest Lifecycle Checkpoint (2026-10-04)

`components.imageBuilderVM.mode: managed | byo | disabled` now controls the retained guest independently of
Virtualization. Managed remains the compatibility default, preserving the VM DataSource, Service and guest setup
Job manifests. BYO and disabled render no VM-chart resources, including the legacy downloader when its old flags
are enabled. They bypass managed-only virtualization, boot-source, replica and RHEL guest configuration checks.
BYO requires explicit nonempty strings `connection.host` (DNS name or IPv4 address) and `connection.sshSecretName`
(existing Kubernetes Secret name). Values contain references only; the Secret uses the existing `ssh-privatekey`
key and existing `cloud-user` SSH connection on port 22. The external guest must already provide the supported
Image Builder tools, repositories and privileges. No guest setup or BYO mutation flag is introduced.

RFE compose pipelines reject disabled guest mode because compose remains mandatory. BYO compose Tasks pass the
host as quoted JSON extra-vars through an environment variable, and the inventory role directly creates
`pipeline_target_host` and writes the existing `image-builder-host` result. Both inventory discovery and the
scheduler's second VMI query are bypassed. The same existing Secret flows through image compose/push and installer
compose/autoboot ISO tasks; names and results stay stable. BYO adds an image pipeline Secret parameter and compose
Task environment entries. Managed pipeline manifests retain their previous behavior and output.

Application Manager propagates the ownership boundary to the actual `charts/rfe-pipelines` path, including
`common.chartPath`. The focused example `examples/values/image-builder-vm-byo.yaml` uses a public dummy host and
explicitly selects this fork's `custom` tooling revision. BYO requires a compatible tooling revision containing
this inventory/playbook implementation: the historical default upstream `main` tooling clone does not supply it.
Default repository references are preserved; operators should pin a verified compatible revision for deployment.
BYO/disabled virtualization still requires separately disabling the historical `cnv-operator` Application.

Verification: all 128 checks in `ruby tests/plan0007-render.rb` pass, including the original 84 checks, lifecycle
resource suppression, mode/type/connection rejection, host/Secret task wiring and actual chart-path propagation.
Managed VM and pipeline parsed manifests match the starting checkpoint. `ruby tests/plan0007-byo-inventory.rb`
executes the real role locally for DNS/IPv4 hosts and rejects shell punctuation and trailing newline inputs. It
asserts inventory and host results and checks both scheduler guards, without SSH, cluster API calls or compose.
Full compose runtime and cluster validation remain unperformed; local installations lack the legacy
`community.kubernetes` and `infra.osbuild` collections needed by the managed/full-compose paths. No dependencies
are installed for this unit. `git diff --check` is required before integration.

Plan 0007 remains incomplete: Pipelines platform lifecycle, registry, Nexus, HTTPD, broader workflow dependency
validation and modern deployment/operator entry-point wiring remain separate bounded units.
