# Plan 0001: ArgoCD Targeting, AppProject, and Access Separation

## Status

Draft implementation plan.

## Goal

Separate ArgoCD application targeting from ArgoCD installation and access control.

The modern path should let RFE `Application` resources target any configured ArgoCD control plane:

- an existing cluster ArgoCD,
- an existing RFE-specific ArgoCD,
- or an RFE-specific ArgoCD installed by this repository.

## Governing Context

- [ADR 0001: Modern RFE Architecture Direction](../adr/0001-modern-rfe-architecture.md)
- [Current State Inventory](../current-state-inventory.md)

## Accepted Decisions

- Create `charts/argocd-integration` as the boundary for ArgoCD control-plane integration.
- Keep `charts/argocd` focused on installing an ArgoCD instance.
- Keep `charts/application-manager` focused on rendering ArgoCD `Application` resources.
- AppProject creation must be optional and restrictive by default.
- Kubernetes RBAC grants for ArgoCD access must be explicit and separate from normal workload deployment.
- Do not solve the full component lifecycle model in this slice.
- Use subagents for bounded implementation workers with disjoint write sets.

## Scope

### 1. Add `charts/argocd-integration`

Create a new chart that can render:

- zero resources by default;
- an optional `AppProject`;
- optional Kubernetes access grants for a configured ArgoCD service account;
- validation for enabled integration features.

The chart should be useful whether the target ArgoCD is BYO or installed by this repository.

### 2. Define ArgoCD target values

Introduce clear target values for Application and AppProject rendering:

```yaml
argocd:
  target:
    namespace: openshift-gitops
    project: rfe
    server: https://kubernetes.default.svc
```

For compatibility during the first slice, existing `common.namespace`, `common.project`, and `common.server` may remain, but the new target model should be the preferred path.

### 3. Move AppProject responsibility

Move AppProject rendering out of `charts/bootstrap` into `charts/argocd-integration`.

The modern AppProject should:

- allow only configured source repositories;
- allow only configured destination namespaces and servers;
- deny cluster-scoped resources by default;
- allow cluster-scoped resources only when explicitly configured.

The first implementation should account for current workflow repos without hard-coding wildcard access:

- tooling repository;
- blueprints repository;
- kickstarts repository.

### 4. Isolate access grants

Add an explicit access-grant model to `charts/argocd-integration`.

The first pass should support a small, reviewable surface:

- target ArgoCD namespace;
- target ArgoCD application-controller service account name;
- allowed workload namespaces;
- optional namespace-scoped role and role binding generation;
- optional named cluster capability grants, defaulting to none.

This slice should not grant `cluster-admin` in modern defaults.

Do not add access for obsolete base-image downloader or PVC/Nexus staging behavior in this slice.

### 5. Retarget Application rendering

Update `charts/application-manager` so ArgoCD `Application` metadata uses the configured ArgoCD target namespace when present.

The destination namespace must remain distinct from the ArgoCD control-plane namespace.

## Non-Goals

- Do not implement the full `components.*.mode` lifecycle model.
- Do not remove BuildConfigs.
- Do not refactor Image Builder, Nexus, Quay, HTTPD, Pulp, or Pipeline workflows except where required for ArgoCD target rendering.
- Do not replace the Image Builder VM with a containerized Buildah, bootc, or no-VM artifact workflow in this slice.
- Do not remove the reference full-stack path.
- Do not change runtime workflow behavior beyond ArgoCD target/AppProject/access rendering.
- Do not commit generated `temp/` manifests or secret material.

## Proposed Work Breakdown

### Component A: ArgoCD Integration Chart

Files likely affected:

- `charts/argocd-integration/Chart.yaml`
- `charts/argocd-integration/values.yaml`
- `charts/argocd-integration/templates/appproject.yaml`
- `charts/argocd-integration/templates/access-role.yaml`
- `charts/argocd-integration/templates/access-rolebinding.yaml`
- `charts/argocd-integration/templates/_helpers.tpl`
- `charts/argocd-integration/templates/_validation.tpl`

Acceptance:

- default values render no resources;
- enabling AppProject renders a restrictive AppProject;
- enabling namespace access renders namespace-scoped grants only for listed namespaces;
- invalid enabled configurations fail at Helm render time.

### Component B: Application Manager Targeting

Files likely affected:

- `charts/application-manager/templates/application.yaml`
- `charts/application-manager/templates/_helpers.tpl`
- `charts/application-manager/values.yaml`
- focused example values as needed.

Acceptance:

- `Application.metadata.namespace` can come from `argocd.target.namespace`;
- `Application.spec.project` can come from `argocd.target.project`;
- `Application.spec.destination.server` can come from `argocd.target.server`;
- existing values continue to work during transition where reasonable;
- destination namespace remains independently configurable.

### Component C: Bootstrap Boundary

Files likely affected:

- `charts/bootstrap/Chart.yaml`
- `charts/bootstrap/templates/appproject.yaml`
- `charts/bootstrap/values.yaml`
- README or docs snippets as needed.

Acceptance:

- bootstrap no longer owns AppProject rendering for the modern path;
- any retained reference behavior is explicit;
- chart dependency wiring includes `argocd-integration` only when needed.

### Component D: Workflow Compatibility Checks

Files likely inspected:

- `charts/rfe-pipelines/**`
- `charts/image-builder-vm/**`
- `charts/quay/**`
- `charts/nexus/**`
- `charts/httpd/**`
- focused Ansible playbooks and roles where access assumptions need confirmation.

Acceptance:

- existing `rfe-pipelines` render output keeps current Pipeline and Task names;
- existing `image-builder-vm` render output keeps current VM/service/job names unless a later scoped change intentionally gates a job;
- the retained Image Builder VM remains the compose runtime and is treated as DataSource-backed in the modern path;
- AppProject/source access accounts for tooling, blueprints, and kickstarts repos;
- no wildcard source repos, wildcard destinations, or blanket cluster-resource access are required for modern examples;
- no new access is added for the obsolete downloader/PVC/Nexus base-image path.

### Component E: Verification and Examples

Files likely affected:

- `examples/values/profiles/` or focused examples under `examples/values/`;
- docs under `docs/`.

Acceptance:

- render checks cover default inert integration;
- render checks cover BYO cluster ArgoCD with AppProject creation;
- render checks cover standalone RFE ArgoCD integration values;
- render checks cover at least one invalid configuration.

## Verification Strategy

Use Helm rendering as the primary verification.

Minimum checks:

```shell
helm template argocd-integration charts/argocd-integration
helm template argocd-integration charts/argocd-integration -f <enabled-appproject-values>
helm template app-manager charts/application-manager -f <targeted-application-values>
helm template bootstrap charts/bootstrap -f <modern-profile-values>
helm template rfe-pipelines charts/rfe-pipelines
helm template image-builder-vm charts/image-builder-vm
```

If dependency charts are involved, run dependency update only where required.

Also run:

```shell
git diff --check
```

## Risks

- The current examples encode the reference install deeply, so keeping backward compatibility may expand the slice.
- AppProject restrictions may expose missing resource allowlists that are currently hidden by wildcard access.
- Namespace access grants can drift into a general RBAC redesign if not kept intentionally narrow.
- ArgoCD service account names differ between upstream ArgoCD and OpenShift GitOps conventions; values must make this explicit.
- Current workflows assume `git-clone` exists as a Tekton `ClusterTask`; this slice should document that prerequisite rather than solve it.
- `rfe-pipelines` currently mutates `openshift-pipelines/config-defaults`; that should be treated as a named Pipelines control-plane capability if it remains enabled.
- `quay`, `nexus`, and `httpd` render checks may require dependency preparation before they can be used as hard gates.

## Open Decisions

- Should `argocd-integration` create AppProject and access grants from one values tree, or should each feature have a separate top-level enable flag?
- What exact AppProject destination namespaces should the first modern example include?
- Which cluster-scoped capabilities are needed in the first slice, if any?
- Should the old bootstrap AppProject template be removed immediately or left behind for reference compatibility until profiles exist?
- Should the first implementation parameterize hard-coded `rfe` workflow namespace values, or preserve them until the component lifecycle slice?

## Planning Receipts

Subagent planning passes were used to keep component context bounded.

| Component | Receipt summary | Impact on this plan |
| --- | --- | --- |
| `argocd-control-plane-access-boundary` | ArgoCD install, AppProject, broad ClusterRoleBinding, user management, and RBAC are separate concerns. | Confirms `charts/argocd-integration` should own AppProject/access and modern defaults must avoid `cluster-admin`. |
| `application-manager-argocd-targeting` | Application metadata namespace, project, and destination server can be shifted to `argocd.target` while preserving destination namespace behavior. | Confirms application-manager can be its own worker with a narrow write set. |
| `argocd-targeting-appproject-access-workflow-prereqs` | Workflows require explicit repos, destinations, and named capabilities, but should not force broad access or obsolete downloader support. | Adds workflow compatibility checks and AppProject source/destination constraints. |

## Next Bounded Action

Plan the `charts/argocd-integration` values API and template contract before writing implementation code.
