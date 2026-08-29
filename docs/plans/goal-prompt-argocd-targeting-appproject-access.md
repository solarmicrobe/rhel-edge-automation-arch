# Goal Prompt: ArgoCD Targeting, AppProject, and Access Separation

Use this prompt to start or resume the first modernization implementation slice.

```text
Goal: implement Plan 0001 for /Users/russell/src/solarmicrobe/rhel-edge-automation-arch on branch custom.

Authoritative context:
- docs/adr/0001-modern-rfe-architecture.md
- docs/current-state-inventory.md
- docs/plans/0001-argocd-targeting-appproject-access.md

Working rules:
- Commit directly to custom and push origin/custom when verified.
- Keep main mirroring upstream/main.
- Existing historical custom changes are evidence, not design authority.
- Do not commit generated temp manifests or secret material.
- Keep context small: read only the docs and files needed for the active slice.
- Prefer Helm render verification over speculative reasoning.
- Use subagents for independent, bounded passes. Do not give subagents broad repo-wide tasks.

Implementation objective:
Separate ArgoCD application targeting from ArgoCD installation and access control.

Accepted decisions:
- Add charts/argocd-integration as the boundary for AppProject and ArgoCD access grants.
- charts/argocd remains about installing an ArgoCD instance.
- charts/application-manager remains about rendering ArgoCD Application resources.
- AppProject creation is optional and restrictive by default.
- Kubernetes RBAC access grants are explicit, separate, and default to none.
- Do not implement the full component lifecycle model in this slice.

Suggested subagent decomposition:

1. ArgoCD integration chart worker
   Scope:
   - create charts/argocd-integration
   - implement inert defaults
   - implement optional restrictive AppProject
   - implement optional namespace access Role/RoleBinding
   - implement validation for enabled features
   - avoid default cluster-admin and wildcard AppProject access
   Write set:
   - charts/argocd-integration/**
   Non-goals:
   - no application-manager changes
   - no workflow or component lifecycle changes

2. Application manager targeting worker
   Scope:
   - add helpers so Application metadata namespace, project, and destination server can use argocd.target values
   - preserve destination namespace behavior
   - keep reasonable compatibility with current common.* values
   - preserve current source repo/ref selection behavior
   Write set:
   - charts/application-manager/**
   Non-goals:
   - no AppProject rendering
   - no access grant rendering

3. Workflow prerequisite verifier
   Scope:
   - inspect rendered workflow prerequisites that affect AppProject repos, destinations, and access capabilities
   - verify rfe-pipelines and image-builder-vm render names stay stable unless intentionally changed
   - identify any access grants the implementation accidentally adds for obsolete downloader/PVC/Nexus base-image staging
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no BuildConfig migration
   - no artifact publication redesign

4. Bootstrap/examples/docs worker
   Scope:
   - wire or document argocd-integration usage in bootstrap/profile examples
   - remove or deprecate bootstrap AppProject ownership only if the implementation plan chooses that now
   - add focused example values for BYO cluster ArgoCD and standalone RFE ArgoCD integration
   Write set:
   - charts/bootstrap/**
   - examples/values/**
   - docs/**
   Non-goals:
   - no Image Builder, Quay, Nexus, HTTPD, Pulp, or Pipeline workflow refactors

Main-agent responsibilities:
- decide the exact values API before dispatching implementation workers;
- ensure subagent write sets do not overlap;
- integrate patches;
- run Helm render checks;
- review final diff for scope creep;
- commit and push only verified work.

Minimum acceptance criteria:
- charts/argocd-integration default render produces no resources.
- enabling AppProject renders a restrictive AppProject using configured repos, destinations, and project name.
- enabling namespace access renders explicit namespace-scoped access grants only for configured namespaces.
- application-manager can render Applications into argocd.target.namespace while destination namespace remains separate.
- invalid enabled configurations fail at Helm render time with clear messages.
- no default modern path grants cluster-admin.
- no AppProject default requires wildcard source repos, wildcard destinations, or blanket cluster-resource access.
- no access is added for the obsolete downloader/PVC/Nexus base-image path.
- git diff --check passes.
- relevant helm template commands pass and their purpose is recorded in the final response.

Start with:
1. Check git status and current branch.
2. Read the three authoritative docs above.
3. Inspect only the files for the first active component.
4. Draft the concrete values API.
5. Ask for a decision only if a values/API choice changes the accepted architecture or broadens scope.
```
