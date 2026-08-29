# Goal Prompt: Image Builder VM DataSource Modernization

Use this prompt to start or resume the second modernization implementation slice.

```text
Goal: implement Plan 0002 for /Users/russell/src/solarmicrobe/rhel-edge-automation-arch on branch custom.

Authoritative context:
- docs/adr/0001-modern-rfe-architecture.md
- docs/current-state-inventory.md
- docs/plans/0001-argocd-targeting-appproject-access.md
- docs/plans/0002-image-builder-datasource-modernization.md

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
Make the modern Image Builder VM path explicitly DataSource-backed and remove or legacy-gate PVC/Nexus base-image staging from the modern path.

Accepted decisions:
- The Image Builder VM remains the RHEL for Edge compose runtime for now.
- The modern root disk source is an OpenShift Virtualization DataSource.
- Nexus may still be used for produced artifacts, but it must not be required for modern VM boot.
- The PVC/Nexus base-image staging path is legacy/reference behavior, not a first-class modern option.
- Re-analyze no-VM bootc/image-mode artifact workflows only after the initial modernization work is complete.
- Do not implement the full component lifecycle model in this slice.
- Do not migrate BuildConfigs in this slice.
- Do not redesign artifact publication in this slice.

Suggested subagent decomposition:

1. Image Builder values and validation worker
   Scope:
   - add explicit DataSource values
   - add Helm render-time validation for supported source modes and required DataSource fields
   - correct replica validation if the current predicate/message disagree
   Write set:
   - charts/image-builder-vm/values.yaml
   - charts/image-builder-vm/templates/_helpers.tpl
   - charts/image-builder-vm/templates/_validation.tpl
   Non-goals:
   - no pipeline changes
   - no artifact publication changes

2. Image Builder VM template worker
   Scope:
   - update DataVolume source rendering to use configured DataSource values
   - remove or legacy-gate the PVC/Nexus boot source branch according to the chosen compatibility shape
   - keep VM, service, and configure-job names stable for the modern path
   Write set:
   - charts/image-builder-vm/templates/image-builder-vm.yaml
   - charts/image-builder-vm/templates/redhat-image-downloader-ansible-job.yaml
   Non-goals:
   - no no-VM runtime redesign
   - no Quay/Nexus/HTTPD/Pulp refactors

3. Workflow prerequisite verifier
   Scope:
   - inspect rendered image-builder-vm and rfe-pipelines output
   - verify no modern render path includes redhat-image-downloader, rfe-rhel-media, or Nexus base-image boot URLs
   - verify rfe-pipelines rendered names remain stable
   - preserve the current Image Builder VM compose-runtime model
   Write set:
   - none by default; report findings only unless asked to patch docs
   Non-goals:
   - no BuildConfig migration
   - no artifact publication redesign

4. Examples/docs worker
   Scope:
   - add a focused DataSource-backed Image Builder VM values example
   - document the DataSource override values and legacy PVC/Nexus boundary
   - keep README/docs updates focused on this slice
   Write set:
   - examples/values/**
   - docs/**
   Non-goals:
   - no full profile rewrite
   - no component lifecycle model

Main-agent responsibilities:
- decide whether to remove the PVC/Nexus boot path now or retain it behind explicit legacy values;
- ensure subagent write sets do not overlap;
- integrate patches;
- run Helm render checks;
- review final diff for scope creep;
- commit and push only verified work.

Minimum acceptance criteria:
- default image-builder-vm render uses a DataSource-backed root disk.
- default image-builder-vm render uses configurable DataSource name and namespace values.
- default image-builder-vm render does not include redhat-image-downloader-ansible-job.
- default image-builder-vm render does not include rfe-rhel-media or the Nexus base-image URL.
- invalid source mode fails at Helm render time with a clear message.
- missing DataSource name or namespace fails at Helm render time with a clear message.
- retained image-builder-vm VM/service/configuration-job names remain stable for the modern path.
- rfe-pipelines rendered Pipeline and Task names remain stable.
- no modern path adds access or workflow prerequisites for obsolete downloader/PVC/Nexus base-image staging.
- no bootc, Buildah, or no-VM runtime replacement is implemented in this slice.
- git diff --check passes.
- relevant helm template commands pass and their purpose is recorded in the final response.

Start with:
1. Check git status and current branch.
2. Read the four authoritative docs above.
3. Inspect only the Image Builder VM chart files and focused workflow files needed for the active slice.
4. Decide the compatibility shape for the legacy PVC/Nexus source path.
5. Ask for a decision only if the compatibility choice changes the accepted architecture or broadens scope.
```
