# Plan 0007: Deployment Modes, Component Lifecycle, and Permissions

## Status

Planned for the `custom` branch.

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

Candidate model:

```yaml
deployment:
  mode: managed-rfe-argocd # managed-rfe-argocd | byo-cluster-argocd | byo-rfe-argocd | reference-full-stack
```

The implementation should preserve existing rendered behavior where compatibility requires it, but modern examples
should prefer `managed-rfe-argocd`.

### 2. Permission Ownership

Add a top-level switch that controls whether this repository renders permission resources.

Candidate model:

```yaml
permissions:
  mode: auto # auto | managed | external
```

`auto` should resolve to:

- `external` for BYO ArgoCD modes;
- `managed` for `managed-rfe-argocd`;
- explicit reference behavior for `reference-full-stack`.

Managed permissions must remain least-privilege and capability-scoped. Do not introduce default `cluster-admin`.

### 3. Component Lifecycle

Introduce a lifecycle shape for shared and RFE-owned components:

```yaml
components:
  odf:
    mode: byo # managed | byo | disabled
    connection: {}
    byo:
      createObjects: false
```

The first implementation should focus on components that directly affect current workflows and existing plan
boundaries:

- ArgoCD/GitOps control plane;
- OpenShift Virtualization and Image Builder VM;
- OpenShift Pipelines;
- ODF/NooBaa storage;
- Quay or external registry;
- Nexus produced-artifact storage;
- HTTPD serving/runtime target.

### 4. BYO Object Creation

Separate component connection from component mutation.

Examples:

- BYO ODF may provide bucket or storage-class details without creating ODF itself.
- BYO Quay or registry may provide a pre-created image path without creating organizations or repositories.
- BYO Nexus may provide credentials and repository URLs without running setup jobs.
- BYO ArgoCD may receive `Application` resources without this repo creating control-plane RBAC unless permissions are
  explicitly managed.

Every BYO object-creation switch should default to false unless a mode-specific `auto` rule intentionally resolves it
to true.

### 5. Artifact Rebuild Avoidance

When workflows can consume an existing source image or artifact, prefer that over rebuilding.

The first pass should inventory current rebuild assumptions and map them to lifecycle or endpoint values. Avoid
rewriting the artifact model in this slice unless a narrow values change is required to stop an unnecessary rebuild.

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

- Should the top-level value be `deployment.mode`, `profile.mode`, or another existing style?
- Should permission ownership be named `permissions.mode`, `access.mode`, or scoped under a GitOps key?
- Which components should be implemented in the first lifecycle pass versus documented for later passes?
- Should BYO object creation use one common shape, such as `byo.createObjects`, or component-specific names?
