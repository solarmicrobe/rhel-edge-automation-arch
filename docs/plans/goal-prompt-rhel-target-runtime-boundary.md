# Goal Prompt: RHEL Target and Runtime Boundary

Use this prompt to start or resume the sixth modernization implementation slice.

```text
Goal: implement Plan 0006 for /Users/russell/src/solarmicrobe/rhel-edge-automation-arch on branch custom.

Read and follow docs/plans/goal-prompt-rhel-target-runtime-boundary.md. Start by stating the goal in your own words,
then proceed from this prompt file's "Start with" checklist.

Authoritative context:
- docs/adr/0001-modern-rfe-architecture.md
- docs/current-state-inventory.md
- docs/plans/0001-argocd-targeting-appproject-access.md
- docs/plans/0002-image-builder-datasource-modernization.md
- docs/plans/0003-buildconfig-inventory-retirement.md
- docs/plans/0004-artifact-publication-endpoint-modernization.md
- docs/plans/0005-no-vm-artifact-workflow-evaluation.md
- docs/plans/0006-rhel-target-runtime-boundary.md

External context to verify from primary sources:
- current Red Hat RHEL 8/9 RHEL for Edge and Image Builder documentation, only for claims about supported targets
- current Red Hat RHEL 10 image-mode and bootc documentation, only for negative validation or future-boundary claims
- current OpenShift Virtualization DataSource documentation, only if RHEL 9 DataSource defaults are proposed

Working rules:
- Commit directly to custom and push origin/custom when verified.
- Keep main mirroring upstream/main.
- Existing historical custom changes are evidence, not design authority.
- Do not commit generated temp manifests or secret material.
- Keep context small: read only the docs and files needed for the active slice.
- Prefer Helm render verification over speculative reasoning.
- Treat local cluster integration as additive verification, not a prerequisite for every chart edit.
- Use subagents for independent, bounded passes. Do not give subagents broad repo-wide tasks.
- Use current primary Red Hat documentation before making claims about RHEL target versions, Image Builder, image mode,
  bootc, bootc-image-builder, or RHEL for Edge support boundaries.

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
Make the repository's RHEL target version and artifact runtime assumptions explicit. Preserve the current RHEL
8-oriented Image Builder VM default intentionally, model only safe RHEL 9 Image Builder continuity if the values and
rendered output support it, and reject RHEL 10 image-mode/bootc combinations until a later plan implements a separate
runtime boundary.

Accepted decisions:
- Plans 0001 through 0005 are implemented on the custom branch and define the current modernization baseline.
- Plan 0005 disposition is retain-vm.
- The Image Builder VM remains the supported default artifact runtime.
- Current workflow behavior is RHEL 8-oriented and rpm-ostree/Image Builder based.
- RHEL 10 image mode and bootc are future paths, not default behavior.
- Current composer-cli, osbuild-composer, SSH, OSTree publication, kickstart, and autoboot ISO workflows must not be
  silently translated to bootc.
- The modern VM root disk remains OpenShift Virtualization DataSource-backed.
- The PVC/Nexus base-image staging path remains legacy/reference behavior and must not return to the modern path.
- Plan 0004 publicationEndpoints values remain the current publication boundary.
- No cluster-mutating CRC, OpenShift, or virtualization commands may run without explicit approval.

Suggested subagent decomposition:

1. Target-assumption inventory worker
   Scope:
   - inspect charts/image-builder-vm, charts/rfe-pipelines, charts/httpd, focused Ansible roles, docs, and examples
   - list every RHEL major, RHSM repo, architecture, OSTree ref, Image Builder image type, DataSource, base image, and
     boot media assumption in the active workflow surface
   - classify each as preserve, parameterize, document, legacy, or defer
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no bootc implementation
   - no broad docs rewrite

2. Values and validation worker
   Scope:
   - propose the smallest values API that prevents ambiguous runtime behavior
   - identify exact Helm validation cases and negative render checks
   - inspect existing chart helper and validation style before recommending changes
   Write set:
   - charts/rfe-pipelines/**
   - charts/image-builder-vm/** only if assigned by the main agent
   Non-goals:
   - no global lifecycle model unless local chart values cannot express the boundary

3. Documentation/examples worker
   Scope:
   - draft focused examples and documentation updates after the values boundary is chosen
   - keep RHEL 8 defaults described as observed implementation facts, not fresh support claims
   - describe RHEL 10/image-mode as unsupported for current composer paths
   Write set:
   - docs/**
   - examples/values/**
   Non-goals:
   - no broad walkthrough rewrite unless the main agent assigns a specific correction

Main-agent responsibilities:
- decide whether `rhelTarget` is chart-local or shared;
- prevent any change that implies RHEL 10 support for current Image Builder workflows;
- ensure subagent write sets do not overlap;
- verify Red Hat support claims with primary sources before relying on them;
- run Helm render checks and negative validation checks;
- verify the modern Image Builder VM DataSource path does not regress into downloader/PVC/Nexus base-image staging;
- verify existing VM-backed Pipeline and Task names remain stable unless intentionally changed;
- review final diff for scope creep;
- commit and push only verified work.

Minimum acceptance criteria:
- every active RHEL target/version assumption is inventoried.
- current RHEL 8-oriented defaults are explicit as implementation facts.
- no RHEL 10 image-mode or bootc behavior becomes a default.
- unsupported target/runtime combinations fail at Helm render time.
- any new validation has a negative render check.
- current default renders still include the retained VM-backed workflow names.
- the modern Image Builder VM DataSource path does not regain downloader/PVC/Nexus base-image prerequisites.
- Plan 0004 publicationEndpoints values remain the publication boundary for current workflows.
- relevant Helm template commands pass and their purpose is recorded in the final response.
- git diff --check passes.

Start with:
1. Check git status and current branch.
2. Read the eight authoritative docs above.
3. Search focused source files for rhel8, rhel8.5, rhel-8, rhel/8/x86_64/edge, rhel-edge-container,
   rhel-edge-installer, rhel-edge-commit, rhelTarget, imageMode, bootc, DataSource, composer-cli, and
   publicationEndpoints.
4. Verify current Red Hat target/version support boundaries from primary documentation before making product support
   claims.
5. Render rfe-pipelines, image-builder-vm, and httpd before deciding what parameterization is safe.
6. Add only bounded values, validation, examples, and docs that make the retained Image Builder runtime boundary
   explicit.
7. Run positive Helm renders and negative validation renders for every new validation path.
8. Ask for a decision if RHEL 9 support, RHEL 10 rejection semantics, or shared-versus-chart-local values are not clear
   from current evidence.
```
