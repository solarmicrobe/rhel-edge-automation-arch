# Goal Prompt: No-VM Artifact Workflow Evaluation

Use this prompt to start or resume the fifth modernization implementation slice.

```text
Goal: implement Plan 0005 for /Users/russell/src/solarmicrobe/rhel-edge-automation-arch on branch custom.

Authoritative context:
- docs/adr/0001-modern-rfe-architecture.md
- docs/current-state-inventory.md
- docs/plans/0001-argocd-targeting-appproject-access.md
- docs/plans/0002-image-builder-datasource-modernization.md
- docs/plans/0003-buildconfig-inventory-retirement.md
- docs/plans/0004-artifact-publication-endpoint-modernization.md
- docs/plans/0005-no-vm-artifact-workflow-evaluation.md

External context to verify from primary sources:
- current Red Hat RHEL image-mode documentation
- current Red Hat RHEL for Edge migration documentation
- current Red Hat bootc-image-builder documentation
- OpenShift Pipeline privileged execution constraints, only if a no-VM Pipeline implementation is considered

Working rules:
- Commit directly to custom and push origin/custom when verified.
- Keep main mirroring upstream/main.
- Existing historical custom changes are evidence, not design authority.
- Do not commit generated temp manifests or secret material.
- Keep context small: read only the docs and files needed for the active slice.
- Prefer Helm render verification over speculative reasoning.
- Treat local cluster integration as additive verification, not a prerequisite for every chart edit.
- Use subagents for independent, bounded passes. Do not give subagents broad repo-wide tasks.
- Use current primary Red Hat documentation before making claims about bootc, image mode, bootc-image-builder, or
  RHEL for Edge support boundaries.

Local integration-test environment:
- This workstation has CRC installed, and CRC supports `openshift` and `microshift` presets.
- Prefer the CRC `openshift` preset when validating this repo's OpenShift-specific behavior, including OpenShift
  GitOps/ArgoCD, OLM-installed operators, Routes, BuildConfig, Tekton, CNV/KubeVirt, DataSources, and privileged
  Pipeline behavior.
- Use the CRC `microshift` preset only as a narrower smoke-test target for changes that do not depend on the full
  OpenShift/operator surface.
- CRC was observed installed but not set up yet. Before cluster tests, check `crc status`; if setup is required, ask
  before running host-mutating commands.
- Do not run `crc setup`, `crc start`, preset changes, privileged Pipeline runs, or cluster-mutating commands without
  explicit user approval; they mutate local virtualization, networking, cluster state, or target cluster resources.
- OpenShift preset setup normally requires a pull secret path, for example `crc start --pull-secret-file <path>`.
- If OrbStack is running, it may be used for Docker-compatible helper containers, but it does not replace CRC for
  OpenShift integration coverage.

Implementation objective:
Evaluate whether a no-VM RHEL for Edge artifact workflow should replace, supplement, or remain deferred relative to
the retained Image Builder VM compose runtime. Inventory the current VM-backed artifact workflows, verify current
Red Hat image-mode, bootc, and bootc-image-builder support boundaries, decide the architecture disposition, and only
make bounded implementation changes if the evidence supports them.

Accepted decisions:
- Plans 0001 through 0004 are implemented on the custom branch and define the current modernization baseline.
- The Image Builder VM remains the default compose runtime until this plan produces a verified replacement decision.
- The modern VM root disk remains OpenShift Virtualization DataSource-backed.
- The PVC/Nexus base-image staging path remains legacy/reference behavior and must not return to the modern path.
- Artifact publication has explicit endpoint values for registry, Nexus produced-artifact storage, and managed HTTPD
  serving assumptions.
- Managed Quay, Nexus, and HTTPD remain reference defaults unless a replacement workflow preserves required behavior.
- Current rpm-ostree and composer-cli workflows must not be silently translated to bootc/image-mode; the RHEL target
  version, artifact type, deployment method, and support boundary must be explicit.
- No cluster-mutating CRC, OpenShift, or virtualization commands may run without explicit approval.

Suggested subagent decomposition:

1. Current workflow inventory worker
   Scope:
   - inspect rfe-pipelines, image-builder-vm, and focused Ansible playbooks/roles
   - list every VM-backed workflow and direct composer-cli, osbuild-composer, SSH, Image Builder host, registry,
     HTTPD, Nexus, and publication endpoint dependency
   - map produced artifact types and current RHEL target assumptions
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no runtime replacement
   - no chart or Ansible edits

2. Red Hat capability review worker
   Scope:
   - verify current image-mode, bootc, bootc-image-builder, and RHEL for Edge support boundaries from primary Red Hat
     documentation
   - map supported artifact outputs to the repo's required OCI, ISO, OSTree, kickstart, disk-image, and publication
     workflows
   - identify privileged execution, subscription, entitlement, base-image, registry, and licensing constraints
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no implementation changes
   - no claims from stale memory or secondary sources when primary sources are available

3. Runtime disposition worker
   Scope:
   - compare retained VM, privileged bootc-image-builder Pipeline, external CI/build host, prebuilt bootc image, and
     hybrid RHEL 8/9 plus RHEL 10 models
   - recommend one disposition: retain-vm, add-experimental-bootc, add-managed-bootc-pipeline, replace-vm-later, or
     defer
   - identify the first safe implementation slice if a no-VM path is viable
   Write set:
   - docs/plans/0005-no-vm-artifact-workflow-evaluation.md only if asked to record the decision
   Non-goals:
   - no broad lifecycle model
   - no artifact publication redesign beyond direct no-VM requirements

4. Implementation worker, only after disposition is decided
   Scope:
   - implement bounded values, validation, examples, docs, or a focused Pipeline/Task skeleton supported by the
     disposition
   - preserve existing VM-backed workflow names unless the decision explicitly replaces them
   - reuse Plan 0004 publication endpoint values instead of hard-coding Quay, Nexus, or HTTPD assumptions
   Write set:
   - charts/rfe-pipelines/**
   - focused ansible/playbooks and ansible/roles files only if still required
   - docs/**
   - examples/values/**
   Non-goals:
   - no VM removal unless every enabled workflow has a verified replacement
   - no automatic composer-cli to bootc translation
   - no cluster-mutating validation without approval

Main-agent responsibilities:
- decide whether this slice is decision-only, decision plus docs/examples, or decision plus bounded implementation;
- ensure subagent write sets do not overlap;
- verify Red Hat support claims with primary sources before relying on them;
- ask for a decision if the RHEL target version, privileged Pipeline allowance, or replacement scope is not clear;
- run Helm render checks and any negative validation checks added by the implementation;
- verify the modern Image Builder VM DataSource path does not regress into downloader/PVC/Nexus base-image staging;
- review final diff for scope creep;
- commit and push only verified work.

Minimum acceptance criteria:
- every current VM-backed artifact workflow is inventoried.
- direct composer-cli, osbuild-composer, SSH, Image Builder host, registry, HTTPD, Nexus, and publication endpoint
  dependencies are recorded.
- current RHEL target assumptions are identified as observed facts, not inferred intent.
- current image-mode, bootc, bootc-image-builder, and RHEL for Edge support boundaries are verified from primary
  sources.
- the plan records a disposition: retain-vm, add-experimental-bootc, add-managed-bootc-pipeline, replace-vm-later, or
  defer.
- no existing workflow is removed unless the same slice provides a clear verified replacement.
- the modern Image Builder VM DataSource path does not regain downloader/PVC/Nexus base-image prerequisites.
- Plan 0004 publication endpoint values are reused for any new publication behavior.
- no unsupported RHEL target, artifact type, or privileged runtime assumption becomes a default.
- relevant Helm template commands pass and their purpose is recorded in the final response.
- any new validation has a negative render check.
- git diff --check passes.

Start with:
1. Check git status and current branch.
2. Read the seven authoritative docs above.
3. Search focused source files for composer-cli, osbuild-composer, image-builder-host, image-builder-secret, bootc,
   bootc-image-builder, rhel-edge, ostree, iso-url, and publicationEndpoints.
4. Verify current Red Hat image-mode, bootc, bootc-image-builder, and RHEL for Edge support boundaries from primary
   documentation.
5. Render rfe-pipelines, image-builder-vm, and httpd before deciding whether any implementation is safe.
6. Ask for a decision if the no-VM disposition would remove or replace a currently required workflow, require
   privileged cluster execution, or depend on an unresolved RHEL target-version choice.
```
