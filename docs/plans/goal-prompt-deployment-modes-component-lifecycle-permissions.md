# Goal Prompt: Deployment Modes, Component Lifecycle, and Permissions

Use this prompt to start or resume the seventh modernization implementation slice.

```text
Goal: implement Plan 0007 for /Users/russell/src/solarmicrobe/rhel-edge-automation-arch on branch custom.

Read and follow docs/plans/goal-prompt-deployment-modes-component-lifecycle-permissions.md. Start by stating the goal
in your own words, then proceed from this prompt file's "Start with" checklist.

Authoritative context:
- docs/adr/0001-modern-rfe-architecture.md
- docs/current-state-inventory.md
- docs/plans/0001-argocd-targeting-appproject-access.md
- docs/plans/0002-image-builder-datasource-modernization.md
- docs/plans/0003-buildconfig-inventory-retirement.md
- docs/plans/0004-artifact-publication-endpoint-modernization.md
- docs/plans/0005-no-vm-artifact-workflow-evaluation.md
- docs/plans/0006-rhel-target-runtime-boundary.md
- docs/plans/0007-deployment-modes-component-lifecycle-permissions.md

Working rules:
- Commit directly to custom and push origin/custom when verified.
- Keep main mirroring upstream/main.
- Existing historical custom changes are evidence, not design authority.
- Do not commit generated temp manifests or secret material.
- Keep context small: read only the docs and files needed for the active slice.
- Prefer Helm render verification over speculative reasoning.
- Treat local CRC/OpenShift integration as additive verification, not a prerequisite for every chart edit.
- Do not run crc setup/start, preset changes, privileged Pipeline runs, or cluster-mutating commands without explicit
  user approval.
- Use subagents for independent, bounded passes. Do not give subagents broad repo-wide tasks.

Implementation objective:
Define and implement the next values boundary for deployment mode, component lifecycle, permission ownership, and BYO
object creation so this repo deploys an RFE workload stack managed by a configured GitOps platform.

Accepted decisions:
- The main purpose is to deploy an RFE workload stack managed by GitOps.
- Support BYO cluster-scoped ArgoCD, BYO namespace-scoped RFE ArgoCD, and repository-created namespace-scoped RFE
  ArgoCD.
- The preferred modern default is repository-created namespace-scoped RFE ArgoCD.
- BYO ArgoCD defaults to externally managed permissions.
- Repository-created RFE ArgoCD defaults to repository-managed least-privilege permissions.
- Shared components should support managed/byo/disabled where they are in the RFE dependency graph.
- Creating objects inside BYO components must be explicit; BYO does not imply setup jobs or mutation.
- ODF is the model shared dependency: use existing cluster storage when present, otherwise stand it up when managed.
- Image Builder VM remains retained and DataSource-backed.
- Prefer configured existing images/artifacts over rebuilds when workflows can consume them directly.

Suggested subagent decomposition:

1. Values API worker
   Scope:
   - inspect existing values style across bootstrap, application-manager, argocd, argocd-integration, rfe-pipelines,
     image-builder-vm, odf, quay, nexus, and httpd
   - propose the smallest values API for deployment.mode, permissions.mode, components.*.mode, and BYO object creation
   Write set:
   - none by default; report findings unless main agent assigns patches

2. Permission boundary worker
   Scope:
   - inspect current argocd-integration, argocd, rbac, and bootstrap permission resources
   - map BYO ArgoCD external permissions and managed RFE ArgoCD least-privilege permissions
   - identify overlap with existing RBAC charts
   Write set:
   - charts/argocd-integration/**
   - charts/argocd/**
   - charts/bootstrap/** only if assigned

3. Component lifecycle worker
   Scope:
   - map current disabled/buildConfig/publicationEndpoints/legacyPvcSource flags to the component lifecycle model
   - start with direct workflow dependencies: ODF/NooBaa, OpenShift Virtualization, Pipelines, Quay/registry, Nexus,
     HTTPD, Image Builder VM
   - avoid broad refactors outside the first selected component set
   Write set:
   - focused chart values/templates assigned by the main agent

4. Artifact reuse worker
   Scope:
   - identify rebuild points that can already consume existing configured images/artifacts
   - propose only narrow switches that avoid unnecessary rebuilds without redesigning the artifact model
   Write set:
   - none by default; patch only if main agent assigns

Main-agent responsibilities:
- choose exact value names before patching;
- keep this slice bounded if full lifecycle migration is too large;
- ensure subagent write sets do not overlap;
- run positive and negative Helm render checks;
- verify no default path grants cluster-admin;
- verify BYO modes do not render setup jobs or mutate BYO services unless explicitly enabled;
- review final diff for scope creep;
- commit and push only verified work.

Minimum acceptance criteria:
- deployment mode values are explicit and validated.
- preferred modern defaults target repository-created namespace-scoped RFE ArgoCD.
- BYO ArgoCD modes default to external permission ownership.
- managed RFE ArgoCD defaults to least-privilege managed permissions.
- at least the first selected shared component lifecycle values are implemented with clear BYO connection validation.
- BYO object creation is separately controlled and defaults to no mutation.
- DataSource-backed Image Builder VM remains the default modern path.
- existing source images/artifacts can be used where the implemented workflow boundary supports it.
- invalid modes and missing required BYO details fail at Helm render time.
- relevant helm template commands pass and their purpose is recorded in the final response.
- git diff --check passes.

Start with:
1. Check git status and current branch.
2. Read the authoritative docs above, prioritizing ADR 0001 and Plan 0007.
3. Inspect current values/templates only for the first selected component set.
4. Draft the exact values API and compare it to existing local flags.
5. Ask for a decision only if the component set, value names, or permission boundary would broaden scope.
```
