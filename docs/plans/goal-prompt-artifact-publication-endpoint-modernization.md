# Goal Prompt: Artifact Publication Endpoint Modernization

Use this prompt to start or resume the fourth modernization implementation slice.

```text
Goal: implement Plan 0004 for /Users/russell/src/solarmicrobe/rhel-edge-automation-arch on branch custom.

Authoritative context:
- docs/adr/0001-modern-rfe-architecture.md
- docs/current-state-inventory.md
- docs/plans/0001-argocd-targeting-appproject-access.md
- docs/plans/0002-image-builder-datasource-modernization.md
- docs/plans/0003-buildconfig-inventory-retirement.md
- docs/plans/0004-artifact-publication-endpoint-modernization.md

Working rules:
- Commit directly to custom and push origin/custom when verified.
- Keep main mirroring upstream/main.
- Existing historical custom changes are evidence, not design authority.
- Do not commit generated temp manifests or secret material.
- Keep context small: read only the docs and files needed for the active slice.
- Prefer Helm render verification over speculative reasoning.
- Treat local cluster integration as additive verification, not a prerequisite for every chart edit.
- Use subagents for independent, bounded passes. Do not give subagents broad repo-wide tasks.

Local integration-test environment:
- This workstation has CRC installed, and CRC supports `openshift` and `microshift` presets.
- Prefer the CRC `openshift` preset when validating this repo's OpenShift-specific behavior, including OpenShift
  GitOps/ArgoCD, OLM-installed operators, Routes, BuildConfig, Tekton, CNV/KubeVirt, and DataSources.
- Use the CRC `microshift` preset only as a narrower smoke-test target for changes that do not depend on the full
  OpenShift/operator surface.
- CRC was observed installed but not set up yet. Before cluster tests, check `crc status`; if setup is required, ask
  before running host-mutating commands.
- Do not run `crc setup`, `crc start`, or preset changes without explicit user approval; they mutate `~/.crc`, local
  virtualization, networking, and cluster state.
- OpenShift preset setup normally requires a pull secret path, for example `crc start --pull-secret-file <path>`.
- If OrbStack is running, it may be used for Docker-compatible helper containers, but it does not replace CRC for
  OpenShift integration coverage.

Implementation objective:
Refactor artifact publication around explicit endpoint contracts so workflows can consume configured registry,
repository storage, and HTTP serving targets instead of assuming repo-managed Quay, Nexus, and HTTPD resources. Start
with endpoint inventory and disposition; make bounded implementation changes only where current workflows can be
preserved.

Accepted decisions:
- The Image Builder VM remains the RHEL for Edge compose runtime for now.
- The modern Image Builder VM root disk is DataSource-backed and must not regain a Nexus/PVC base-image staging
  prerequisite.
- Plan 0003 preserved default BuildConfig rendering for compatibility while externalizing ansible-rfe-runner image
  consumers and allowing HTTPD to use an externally supplied image.
- Artifact publication endpoint modernization is in scope for this slice.
- Nexus is optional produced-artifact storage, not a base-image boot prerequisite.
- HTTPD currently remains part of existing publish and serve flows. oci-publish-content runs OSTree operations through
  the chart-managed HTTPD pod, so an external HTTP URL alone may not replace the current service.
- Quay is a registry target, but repo-managed Quay setup should be separated from registry endpoint consumption.
- Do not migrate surviving BuildConfigs to Tekton in this slice.
- Do not implement the full components.*.mode lifecycle model unless a narrow endpoint mode is required to express one
  local boundary.
- Do not introduce bootc, image-mode, Buildah-only, or no-VM runtime replacement in this slice.

Suggested subagent decomposition:

1. Endpoint inventory worker
   Scope:
   - render and inspect rfe-pipelines, httpd, quay, nexus, and image-builder-vm chart output
   - list every registry, repository storage, and HTTP serving endpoint
   - list every secret, route, service, pod, PVC, URL, Tekton param, Tekton result, and Ansible variable dependency
   - distinguish source-defined assumptions from rendered resources
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no implementation changes
   - no endpoint redesign

2. Registry and Quay worker
   Scope:
   - trace Quay setup, repository creation, image push, and publisher flows
   - identify which consumers need managed Quay setup versus a configured registry endpoint
   - propose the narrowest disposition for modern defaults
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no broad registry abstraction
   - no BuildConfig migration

3. Repository storage and HTTP serving worker
   Scope:
   - trace Nexus upload, kickstart upload, ISO upload, HTTPD serving, and OSTree publication flows
   - identify which consumers need URL-only access, writable storage, route lookup, or pod execution
   - decide whether HTTPD must remain the managed reference for OSTree publication
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no Pulp or ODF redesign unless a direct dependency is found
   - no removal of existing publication workflows without replacement

4. Implementation worker, only after endpoint disposition is decided
   Scope:
   - implement bounded endpoint values, validation, chart wiring, focused Ansible variable wiring, docs, or examples
     supported by the inventory
   - preserve current names unless Plan 0004 intentionally gates a setup path from endpoint consumption
   Write set:
   - charts/rfe-pipelines/**
   - charts/quay/**
   - charts/nexus/**
   - charts/httpd/**
   - focused ansible/playbooks and ansible/roles publication files
   - docs/**
   - examples/values/**
   Non-goals:
   - no no-VM runtime replacement
   - no BuildConfig-to-Tekton migration
   - no broad component lifecycle model
   - no unrelated ArgoCD, MachineSet, access, or Image Builder VM redesign

Main-agent responsibilities:
- decide whether this slice is inventory-only, inventory plus endpoint values, or inventory plus setup/consumption
  separation;
- ensure subagent write sets do not overlap;
- integrate patches only after endpoint disposition is evidence-backed;
- run Helm render checks and any negative validation checks added by the implementation;
- verify the modern Image Builder VM DataSource path does not regress into downloader/PVC/Nexus base-image staging;
- review final diff for scope creep;
- commit and push only verified work.

Minimum acceptance criteria:
- registry, repository storage, and HTTP serving endpoint assumptions are inventoried.
- all direct publication consumers are identified.
- secret, route, service, pod, PVC, URL, Tekton param, Tekton result, and Ansible variable dependencies are recorded.
- each endpoint family has an evidence-backed disposition: managed-reference, externalize, retain-reference,
  defer-redesign, or migrate-later.
- no existing workflow is removed unless the same slice provides a clear replacement.
- the modern Image Builder VM DataSource path does not regain downloader/PVC/Nexus base-image prerequisites.
- no bootc, image-mode, Buildah-only, or no-VM runtime replacement is implemented in this slice.
- no BuildConfig-to-Tekton migration is implemented in this slice.
- relevant Helm template commands pass and their purpose is recorded in the final response.
- any new validation has a negative render check.
- git diff --check passes.

Start with:
1. Check git status and current branch.
2. Read the six authoritative docs above.
3. Inspect focused charts, Tekton templates, playbooks, and roles for registry, repository storage, and HTTP serving
   dependencies.
4. Render rfe-pipelines, httpd, quay, nexus, and image-builder-vm before deciding endpoint disposition.
5. Ask for a decision only if the disposition would broaden scope beyond Plan 0004 or remove a currently required
   workflow without a replacement.
```
