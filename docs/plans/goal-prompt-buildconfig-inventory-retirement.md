# Goal Prompt: BuildConfig Inventory and Retirement

Use this prompt to start or resume the third modernization implementation slice.

```text
Goal: implement Plan 0003 for /Users/russell/src/solarmicrobe/rhel-edge-automation-arch on branch custom.

Authoritative context:
- docs/adr/0001-modern-rfe-architecture.md
- docs/current-state-inventory.md
- docs/plans/0001-argocd-targeting-appproject-access.md
- docs/plans/0002-image-builder-datasource-modernization.md
- docs/plans/0003-buildconfig-inventory-retirement.md

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
- Prefer the CRC `openshift` preset when validating this repo's OpenShift-specific behavior, including OpenShift GitOps/ArgoCD, OLM-installed operators, Routes, BuildConfig, Tekton, CNV/KubeVirt, and DataSources.
- Use the CRC `microshift` preset only as a narrower smoke-test target for changes that do not depend on the full OpenShift/operator surface.
- CRC was observed installed but not set up yet. Before cluster tests, check `crc status`; if setup is required, ask before running host-mutating commands.
- Do not run `crc setup`, `crc start`, or preset changes without explicit user approval; they mutate `~/.crc`, local virtualization, networking, and cluster state.
- OpenShift preset setup normally requires a pull secret path, for example `crc start --pull-secret-file <path>`.
- If OrbStack is running, it may be used for Docker-compatible helper containers, but it does not replace CRC for OpenShift integration coverage.

Implementation objective:
Inventory every remaining OpenShift BuildConfig path, decide whether each path should be retained, retired, supplied externally, or migrated later, and remove BuildConfig assumptions from the modern path only where the evidence supports a safe bounded change.

Accepted decisions:
- BuildConfig modernization starts with inventory, not direct Tekton translation.
- The Image Builder VM remains the RHEL for Edge compose runtime for now.
- The modern Image Builder VM root disk is DataSource-backed and must not regain a Nexus/PVC base-image staging prerequisite.
- Known BuildConfig candidates are ansible-rfe-runner and HTTPD OSTree image builds.
- Do not redesign artifact publication in this slice.
- Do not introduce bootc/image-mode or no-VM runtime replacement in this slice.
- Do not implement the full component lifecycle model in this slice.
- Do not migrate BuildConfigs unless the inventory proves the build must survive and the replacement is bounded.

Suggested subagent decomposition:

1. BuildConfig inventory worker
   Scope:
   - render and inspect ansible-rfe-runner and httpd chart output
   - list every BuildConfig, ImageStream, output ImageStreamTag, trigger, build source, and secret dependency
   - distinguish source-defined resources from rendered resources
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no implementation changes
   - no Tekton migration

2. Ansible runner consumer worker
   Scope:
   - trace every chart and workflow reference to ansible-rfe-runner
   - identify which consumers need the built image versus the BuildConfig itself
   - propose the narrowest disposition for modern defaults
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no broad image registry redesign
   - no component lifecycle model

3. HTTPD build and publication coupling worker
   Scope:
   - inspect httpd chart, ImageStream trigger, and Ansible roles that locate or write to HTTPD
   - identify whether the custom OSTree-capable HTTPD image build is still needed before artifact endpoint redesign
   - propose retain/externalize/retire/defer disposition
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no artifact publication endpoint redesign
   - no Pulp/Quay/Nexus refactor

4. Implementation worker, only after disposition is decided
   Scope:
   - implement bounded changes supported by the inventory, such as image override values, validation, or explicit reference gating
   - update focused docs/examples
   - preserve current names unless the plan intentionally gates a resource out of the modern path
   Write set:
   - charts/ansible-rfe-runner/**
   - charts/httpd/**
   - focused consumer templates that hard-code ansible-rfe-runner
   - docs/**
   - examples/values/**
   Non-goals:
   - no automatic BuildConfig-to-Tekton translation
   - no no-VM runtime replacement
   - no artifact publication redesign

Main-agent responsibilities:
- decide whether this slice is inventory-only, inventory plus externalized image values, or inventory plus explicit reference gating;
- ensure subagent write sets do not overlap;
- integrate patches only after disposition is evidence-backed;
- run Helm render checks and any negative validation checks added by the implementation;
- review final diff for scope creep;
- commit and push only verified work.

Minimum acceptance criteria:
- all remaining source-defined BuildConfigs are inventoried.
- rendered BuildConfig names and output images are recorded.
- ansible-rfe-runner downstream consumers are identified.
- HTTPD build and serving/publication consumers are identified.
- each BuildConfig has an evidence-backed disposition: retain-reference, externalize, retire, defer-migration, or migrate-later.
- no BuildConfig is removed unless its consumers no longer require it or the same slice provides a clear replacement.
- the modern Image Builder VM DataSource path does not regain downloader/PVC/Nexus base-image prerequisites.
- no bootc, Buildah, or no-VM runtime replacement is implemented in this slice.
- no broad artifact publication endpoint redesign is implemented in this slice.
- relevant Helm template commands pass and their purpose is recorded in the final response.
- git diff --check passes.

Start with:
1. Check git status and current branch.
2. Read the five authoritative docs above.
3. Inspect only the BuildConfig charts, focused consumer templates, and focused Ansible roles needed for this slice.
4. Render ansible-rfe-runner, httpd, image-builder-vm, and rfe-pipelines before deciding disposition.
5. Ask for a decision only if the disposition would broaden scope beyond Plan 0003 or remove a currently required workflow without a replacement.
```
