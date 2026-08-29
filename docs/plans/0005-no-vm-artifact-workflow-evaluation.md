# Plan 0005: No-VM Artifact Workflow Evaluation

## Status

Implemented on the `custom` branch.

## Goal

Evaluate whether a no-VM RHEL for Edge artifact workflow should replace, supplement, or remain deferred relative to the
retained Image Builder VM compose runtime.

This slice is decision-first. It must inventory the current VM-backed workflow, compare it against current Red Hat
image-mode, bootc, and `bootc-image-builder` capabilities, and only implement bounded repository changes when the
evidence supports them without breaking the existing RHEL for Edge artifact workflows.

## Governing Context

- [ADR 0001: Modern RFE Architecture Direction](../adr/0001-modern-rfe-architecture.md)
- [Current State Inventory](../current-state-inventory.md)
- [Plan 0001: ArgoCD Targeting, AppProject, and Access Separation](0001-argocd-targeting-appproject-access.md)
- [Plan 0002: Image Builder VM DataSource Modernization](0002-image-builder-datasource-modernization.md)
- [Plan 0003: BuildConfig Inventory and Retirement](0003-buildconfig-inventory-retirement.md)
- [Plan 0004: Artifact Publication Endpoint Modernization](0004-artifact-publication-endpoint-modernization.md)

## External References To Verify

Use current primary Red Hat documentation before deciding the workflow direction:

- [RHEL 10 image mode for RHEL](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/introducing-image-mode-for-rhel)
- [RHEL 10 RHEL for Edge migration to bootc](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/composing_installing_and_managing_rhel_for_edge_images/migrating-from-rpm-ostree-based-deployed-systems-to-bootc-based-systems)
- [RHEL 9 bootc-image-builder documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/creating-bootc-compatible-base-disk-images-with-bootc-image-builder_building-and-managing-physically-bound-images)

The known 2026-08-29 documentation signal is that RHEL 10 image mode replaces RHEL Image Builder for edge image
creation, while RHEL 9 still supports RHEL Image Builder for RHEL for Edge images. Re-check this during
implementation; do not rely on stale memory for product support boundaries.

## Accepted Decisions

- Plans 0001 through 0004 are implemented on the `custom` branch and define the current modernization baseline.
- The Image Builder VM remains the default compose runtime until this plan produces a verified replacement decision.
- The modern VM root disk remains OpenShift Virtualization `DataSource` backed.
- The PVC/Nexus base-image staging path remains legacy/reference behavior and must not return to the modern path.
- Artifact publication now has explicit endpoint values for registry, Nexus produced-artifact storage, and managed
  HTTPD serving assumptions.
- Managed Quay, Nexus, and HTTPD remain reference defaults unless a replacement workflow preserves required behavior.
- The current rpm-ostree and `composer-cli` workflows must not be silently translated to bootc/image-mode; the RHEL
  target version, artifact type, deployment method, and support boundary must be explicit.
- No cluster-mutating CRC, OpenShift, or virtualization commands may run without explicit approval.

## Scope

### 1. Inventory Current VM-Backed Artifact Workflows

Trace the workflows that currently require the Image Builder VM, `osbuild-composer`, `composer-cli`, SSH access, and
HTTPD/registry publication.

Known workflow surfaces:

- `rfe-oci-image-pipeline`
- `rfe-oci-iso-pipeline`
- `rfe-oci-publish-content-pipeline`
- `rfe-oci-stage-pipeline`
- `rfe-kickstart-pipeline`
- `ansible/playbooks/build-rfe-rpm-ostree.yaml`
- `ansible/playbooks/oci-create-image.yaml`
- `ansible/playbooks/oci-build-installer-image.yaml`
- `ansible/playbooks/oci-build-auto-iso.yaml`
- `ansible/playbooks/oci-push-image.yaml`
- `ansible/playbooks/oci-publish-content.yaml`
- `ansible/playbooks/oci-stage-content.yaml`
- `ansible/roles/image-builder/**`
- `ansible/roles/oci-build-image/**`
- `ansible/roles/oci-build-installer-image/**`
- `ansible/roles/oci-push-image/**`
- `ansible/roles/oci-build-auto-iso/**`

For each workflow, record:

- produced artifact types;
- consumed blueprint, kickstart, OSTree, registry, and serving inputs;
- VM-specific dependencies;
- OpenShift/KubeVirt dependencies;
- secret and entitlement requirements;
- publication endpoint requirements;
- whether a no-VM equivalent exists, is partial, or is unsupported.

### 2. Verify Current Red Hat Support Boundaries

Confirm the relevant RHEL version and image workflow boundaries from primary sources.

Questions to answer:

- Is this repo's target still RHEL 8, RHEL 9, RHEL 10, or intentionally multi-version?
- Which target versions support the current `composer-cli` and rpm-ostree blueprint workflow?
- Which target versions support image mode, `bootc`, and `bootc-image-builder` for the required artifact types?
- Does `bootc-image-builder` require privileged container execution, root access, subscription material, or host
  bind mounts that affect OpenShift Pipeline feasibility?
- Which artifact outputs are supported: OCI image, raw disk, qcow2, AMI/VMDK, ISO, offline installer, and kickstart
  customization?
- What licensing or redistribution limits affect generated images and base images?

### 3. Compare Candidate Runtime Models

Evaluate candidates against current workflow requirements.

Candidate dispositions:

- `retain-vm`: keep the Image Builder VM as the supported default because no no-VM path preserves required behavior.
- `add-experimental-bootc`: add an explicitly experimental bootc/image-mode path without replacing the VM.
- `add-managed-bootc-pipeline`: add a supported no-VM Pipeline path for a bounded artifact type.
- `replace-vm-later`: document that replacement is viable but too broad for this slice.
- `defer`: record blockers and leave the VM untouched.

Candidate runtime models:

- retained Image Builder VM with `composer-cli`;
- Tekton task running a privileged `bootc-image-builder` container;
- external CI or build host producing bootc-compatible artifacts;
- prebuilt bootc image consumed by this repo only for publication and installer generation;
- hybrid path where bootc handles RHEL 10 image-mode artifacts while the VM remains for RHEL 8/9 rpm-ostree artifacts.

### 4. Decide The Next Architecture Boundary

Produce a clear disposition before editing runtime behavior.

The decision must state:

- whether the repo should keep the VM as default;
- whether any bootc/image-mode path is supported, experimental, or deferred;
- which artifact type the next implementation should target first, if any;
- which existing workflows remain authoritative;
- which values API is needed to express the boundary;
- what validation should fail early for unsupported combinations.

### 5. Implement Only Bounded Supported Changes

Implementation is optional and must follow the decision evidence.

Candidate bounded changes:

- add docs recording the no-VM workflow decision and support matrix;
- add example values for an experimental no-VM path if no runtime behavior changes are required;
- add Helm values and validation that keep no-VM behavior disabled unless explicitly configured;
- add a skeleton Pipeline or Task only if the required runtime privileges, secrets, image source, artifact output, and
  publication endpoints are all understood;
- add verification-only scripts or comments only when they reduce ambiguity for a later implementation slice.

Avoid broad runtime replacement, application-manager lifecycle rewrites, or replacing multiple artifact workflows at
once.

## Non-Goals

- Do not remove the Image Builder VM unless the same slice provides a verified replacement for every enabled workflow.
- Do not make bootc/image-mode the default without explicit RHEL target and support-boundary evidence.
- Do not convert every rpm-ostree or `composer-cli` workflow to bootc.
- Do not reintroduce Nexus/PVC base-image staging into the modern Image Builder VM boot path.
- Do not redesign ArgoCD targeting, AppProject, access grants, component lifecycle, or publication endpoints except
  where a no-VM boundary directly requires a narrow value or validation change.
- Do not remove Quay, Nexus, HTTPD, Pulp, ODF, or OpenShift Virtualization broadly.
- Do not run privileged cluster, CRC, or host-mutating validation without explicit approval.
- Do not commit generated `temp/` manifests or secret material.

## Proposed Work Breakdown

### Component A: Current Workflow Inventory

Files likely inspected:

- `charts/rfe-pipelines/**`
- `charts/image-builder-vm/**`
- `ansible/playbooks/**`
- `ansible/roles/image-builder/**`
- `ansible/roles/oci-build-image/**`
- `ansible/roles/oci-build-installer-image/**`
- `ansible/roles/oci-push-image/**`
- `ansible/roles/oci-build-auto-iso/**`
- `ansible/roles/oci-publish-content/**`
- `ansible/roles/content-download-upload/**`
- `docs/**`
- `examples/values/**`

Acceptance:

- every VM-backed workflow is listed;
- every direct `composer-cli`, `osbuild-composer`, SSH, VM service, and Image Builder host dependency is recorded;
- produced artifact types and publication endpoints are mapped to workflows;
- current RHEL target assumptions are recorded as observed facts, not inferred intent.

### Component B: External Capability Review

Sources likely inspected:

- current Red Hat RHEL image-mode documentation;
- current Red Hat RHEL for Edge migration documentation;
- current Red Hat `bootc-image-builder` documentation;
- current OpenShift Pipeline security context and privileged execution constraints, only if implementation is
  considered.

Acceptance:

- support boundaries are cited from primary sources;
- bootc/image-mode capabilities are mapped to required artifact outputs;
- privileged execution, subscription, entitlement, base-image, and registry requirements are recorded;
- unsupported or version-specific behavior is not treated as a default architecture.

### Component C: Decision Record

Files likely changed:

- `docs/plans/0005-no-vm-artifact-workflow-evaluation.md`
- possibly `docs/current-state-inventory.md`
- possibly a focused ADR if the decision changes the architecture rather than only sequencing future work

Acceptance:

- the plan records a disposition: `retain-vm`, `add-experimental-bootc`, `add-managed-bootc-pipeline`,
  `replace-vm-later`, or `defer`;
- the decision explains why each current artifact workflow is preserved, replaced, or deferred;
- the decision identifies the first safe implementation slice if a no-VM path is viable.

### Component D: Optional Bounded Implementation

Files likely changed only if the decision supports implementation:

- `charts/rfe-pipelines/values.yaml`
- `charts/rfe-pipelines/templates/_validation.tpl`
- focused `charts/rfe-pipelines/templates/*bootc*` or existing task/pipeline files
- focused Ansible files only if still required by the selected path
- `examples/values/**`
- `docs/**`

Acceptance:

- no-VM behavior is disabled or experimental by default unless explicitly approved as the new default;
- Helm validation rejects unsupported RHEL target, runtime, or artifact combinations;
- existing VM-backed pipelines still render and retain names unless the decision explicitly replaces them;
- publication endpoint values from Plan 0004 are reused instead of hard-coding Quay, Nexus, or HTTPD assumptions.

### Component E: Verification

Minimum verification:

```sh
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template httpd charts/httpd --namespace rfe
git diff --check
```

If new values or validation are added, include focused positive and negative Helm render checks.

If a no-VM Pipeline or Task is added, also verify rendered output contains only the intended new resources and that the
existing VM-backed Pipeline and Task names remain stable unless explicitly replaced.

## Verification Strategy

Use documentation review and Helm rendering as the primary verification path.

Recommended checks:

```sh
rg -n "composer-cli|osbuild-composer|image-builder-host|image-builder-secret|bootc|bootc-image-builder|rhel-edge|ostree|iso-url|quay_image_path|publicationEndpoints" ansible charts docs examples
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template httpd charts/httpd --namespace rfe
git diff --check
```

Cluster integration is additive. Before any cluster validation, check `crc status`; do not run `crc setup`,
`crc start`, preset changes, privileged Pipeline runs, or cluster-mutating commands without explicit approval.

## Resolved Decision

Disposition: `retain-vm`.

The retained Image Builder VM remains the supported default runtime for the current RHEL for Edge workflows. A no-VM
bootc/image-mode workflow is not added in this slice because the current repository behavior is still RHEL 8
rpm-ostree/Image Builder based, while current Red Hat documentation makes the bootc/image-mode path version-specific
and materially different from the existing blueprint, `composer-cli`, OSTree publication, kickstart, and ISO
post-processing flows.

This slice is therefore decision plus documentation only. It does not remove the Image Builder VM, add a privileged
`bootc-image-builder` Pipeline, add experimental bootc values, or change runtime defaults. The first safe future slice,
if this fork chooses RHEL 10 image mode explicitly, should define a separate RHEL target/runtime boundary before adding
any bootc Pipeline or external build-host integration.

## Current Workflow Inventory

The current artifact workflows use an Image Builder VM for compose work and then use separate OpenShift, registry,
Nexus, and HTTPD paths for publication.

| Workflow | Current artifacts | VM and composer dependencies | Publication and platform dependencies | Observed RHEL target assumptions | No-VM disposition |
| --- | --- | --- | --- | --- | --- |
| Image Builder VM configuration | Configured Image Builder host | `charts/image-builder-vm` renders `VirtualMachine/image-builder-000`, `Service/image-builder-000`, and `Job/image-builder-vm-ansible-job`; `ansible/roles/image-builder/tasks/main.yaml` installs `osbuild-composer`, `composer-cli`, `cockpit-composer`, `genisoimage`, `httpd`, and `syslinux`; SSH uses `image-builder-ssh-key`; RHSM uses `redhat-portal-credentials` | OpenShift Virtualization `DataSource/rhel8` in `openshift-virtualization-os-images`; Kubernetes API access for router CA, proxy, and ingress data | VM annotations, labels, machine type, DataSource, RHSM repositories, and package repos are RHEL 8 oriented | Preserve; this is the required runtime for current compose workflows |
| `rfe-oci-image-pipeline` | RHEL for Edge OCI container image pushed to a registry; build commit and tag results | `rfe-oci-build-image` SSHes to the Image Builder VM and runs `ansible/playbooks/oci-create-image.yaml`; `ansible/roles/oci-build-image/tasks/main.yaml` pushes blueprints, runs `composer-cli blueprints depsolve`, `composer-cli blueprints freeze`, and `composer-cli compose start-ostree ... rhel-edge-container`; `rfe-oci-push-image` runs `composer-cli compose image` against the VM build ID | `rfe-oci-quay-repository` and `rfe-oci-push-image` consume `publicationEndpoints.registry.*`, `publisher`, and, in managed-reference mode, `quay-rfe-setup`; tasks use the `ansible-rfe-runner` image and `git-clone` ClusterTask | Default repositories are `rhel-8-for-x86_64-baseos-rpms` and `rhel-8-for-x86_64-appstream-rpms`; output type is `rhel-edge-container` | Preserve; bootc OCI image creation is not a drop-in replacement for rpm-ostree blueprint compose plus existing push flow |
| `rfe-oci-iso-pipeline` | Installer compose ID and autoboot ISO URL | `rfe-oci-build-installer-image` SSHes to the VM and runs `ansible/playbooks/oci-build-installer-image.yaml`; `ansible/roles/oci-build-installer-image/tasks/main.yaml` runs `composer-cli compose start-ostree --ref rhel/8/x86_64/edge --url ... rhel-edge-installer`; `rfe-oci-build-auto-iso` runs `composer-cli compose image` and post-processes the ISO with `mkisofs` and `isohybrid` | Consumes a kickstart URL and OSTree repo URL; optional produced-artifact upload uses `publicationEndpoints.artifactRepository.nexus.*`; serving URL comes from `publicationEndpoints.httpServing.route*` and the managed HTTPD route | Hard-coded OSTree ref is `rhel/8/x86_64/edge`; output type is `rhel-edge-installer` | Preserve; bootc ISO output exists, but the current embedded kickstart and ISO post-processing flow is not replaced here |
| `rfe-oci-stage-pipeline` | Temporary staged OSTree HTTP route for an existing image tag | Does not compose on the VM, but consumes images produced by the VM-backed OCI workflow | `ansible/roles/oci-stage-content/tasks/main.yaml` creates or updates OpenShift `ImageStream`, `Deployment`, `Service`, and `Route` resources and uses `publicationEndpoints.httpServing.podNamespace` plus `stageServiceAccountName` | Stages OSTree content from the RHEL for Edge image model | Preserve; it remains coupled to OpenShift ImageStream/Route behavior |
| `rfe-oci-publish-content-pipeline` | Published OSTree repository URL | Does not compose on the VM, but publishes content from VM-produced image tags | `ansible/roles/oci-publish-content/tasks/main.yaml` waits for the staged service, runs `ostree init`, `ostree remote add`, `ostree pull --mirror`, and `ostree summary` inside the managed HTTPD web root; uses `publicationEndpoints.httpServing.webRoot` and route values | Pulls `rhel/8/x86_64/edge` from the staged OSTree service | Preserve; a bootc registry artifact does not replace this OSTree mirror operation without a publication redesign |
| `rfe-kickstart-pipeline` | Kickstart artifact repository URL and serving URL | Does not compose on the VM, but consumes an OSTree repo URL usually produced by the current RHEL for Edge publish flow | `upload-kickstart` runs `ansible/playbooks/upload-kickstart.yaml`; `ansible/roles/content-download-upload/tasks/upload-rfe-artifact.yaml` optionally uploads to Nexus and copies to the HTTPD pod using `publicationEndpoints.artifactRepository.*` and `publicationEndpoints.httpServing.*` values | Kickstart examples use RHEL for Edge `ostreesetup` with `rhel/8/x86_64/edge` | Preserve; still depends on the current OSTree installer model |
| `ansible/playbooks/build-rfe-rpm-ostree.yaml` | RHEL for Edge commit/build ID | Runs `ansible/roles/build-rpm-ostree`, which uses `composer-cli blueprints push`, `composer-cli blueprints depsolve`, `composer-cli blueprints freeze`, `composer-cli compose start ... rhel-edge-commit`, and `composer-cli compose status` | Consumes blueprint content and Image Builder host configuration | Role paths and compose type are rpm-ostree/RHEL for Edge oriented | Preserve as legacy/reference evidence; not translated to bootc in this slice |

Direct current dependencies recorded by this inventory:

- `composer-cli`: `ansible/roles/build-rpm-ostree`, `ansible/roles/oci-build-image`,
  `ansible/roles/oci-build-installer-image`, `ansible/roles/oci-build-auto-iso`,
  `ansible/roles/oci-push-image`, `ansible/roles/content-download-upload`,
  `ansible/roles/pipeline-scheduler`, and `ansible/roles/image-builder-content-sources`.
- `osbuild-composer`: installed and enabled by `ansible/roles/image-builder/tasks/main.yaml`.
- SSH and Image Builder host access: Pipeline tasks use `image-builder-secret`, `image-builder-host`, and
  `image-builder-ssh-key` to run playbooks against the VM.
- Registry publication: `rfe-oci-quay-repository`, `rfe-oci-push-image`, `rfe-oci-stage-image`, and
  `rfe-oci-publish-content` consume image paths/tags and `publicationEndpoints.registry.*`.
- HTTPD publication: `rfe-oci-publish-content`, `rfe-oci-stage-image`, `rfe-oci-build-auto-iso`, and
  `upload-kickstart` depend on managed HTTPD route, pod, PVC-backed web root, and OSTree tooling assumptions.
- Nexus produced-artifact storage: `upload-kickstart`, `rfe-oci-build-auto-iso`, and `content-download-upload` use
  `publicationEndpoints.artifactRepository.nexus.*` when Nexus upload is not disabled.

## Red Hat Support Boundary Review

Primary documentation reviewed on 2026-08-29:

- [RHEL 10 image mode for RHEL](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/introducing-image-mode-for-rhel)
- [RHEL 10 RHEL for Edge migration to bootc](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/composing_installing_and_managing_rhel_for_edge_images/migrating-from-rpm-ostree-based-deployed-systems-to-bootc-based-systems)
- [RHEL 9 bootc-image-builder documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/creating-bootc-compatible-base-disk-images-with-bootc-image-builder_building-and-managing-physically-bound-images)
- [Red Hat OpenShift Pipelines security context documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.19/html-single/securing_openshift_pipelines/securing_openshift_pipelines)

Current Red Hat documentation supports these boundaries:

| Boundary | Verified support signal | Impact on this repo |
| --- | --- | --- |
| RHEL 10 edge image creation | RHEL 10 documentation says image mode replaces RHEL Image Builder for creating edge images, and that RHEL 10 and later no longer support composing customized RHEL rpm-ostree images optimized for Edge with RHEL Image Builder | A RHEL 10 path must be bootc/image-mode explicit; it cannot silently reuse this repo's current `composer-cli` rpm-ostree workflow |
| RHEL 9 RHEL for Edge | The same RHEL 10 migration documentation states that RHEL Image Builder can still be used on RHEL 9 to build RHEL for Edge images | The retained VM is still the matching architecture for Image Builder based RHEL for Edge continuity; this repo's RHEL 8 references are observed implementation facts, not a refreshed support claim |
| Image mode and bootc | RHEL 10 image mode uses OCI container images based on `registry.redhat.io/rhel10/rhel-bootc`; Red Hat documents `bootc` as intended to supersede `rpm-ostree`; it also warns that using `rpm-ostree` to make changes or install content is unsupported in image mode | Existing `rhel-edge-container`, `rhel-edge-installer`, and OSTree mirror workflows need an explicit version/runtime boundary before bootc can be introduced |
| bootc-image-builder outputs | RHEL 9 `bootc-image-builder` documentation supports converting bootc images into disk image formats including ISO, QCOW2, AMI, raw, and VMI, and the RHEL 10 image-mode overview lists OCI, AMI, QCOW2, VMDK, Anaconda ISO, raw, VHD, and GCE formats | Supported output formats overlap with some repo needs, but the source model is a bootc image, not a composer blueprint/rpm-ostree commit |
| bootc-image-builder runtime constraints | Red Hat documents `bootc-image-builder` as a containerized tool from the Red Hat registry, requiring authenticated registry access; it uses local container storage by default and cannot pull remote images itself, so local container storage must be mounted; documented ISO examples run Podman with `--privileged`, an unconfined SELinux label, and host/container storage and output bind mounts | A Tekton implementation would require explicit privileged SCC/service account decisions, registry credentials, local image-storage handling, output storage, and secret management before it can be supported |
| OpenShift Pipelines privilege model | Red Hat OpenShift Pipelines documents the default `pipeline` service account and `pipelines-scc`, allows default and maximum SCC configuration through `TektonConfig`, and describes using a custom service account/SCC for privileged tasks | A managed bootc Pipeline would mutate or depend on cluster security policy; this plan cannot add it without an explicit privileged-runtime approval and validation model |
| License and redistribution | RHEL bootc base images and derived containers are subject to the RHEL EULA and must not be publicly redistributed | Any future external registry or example workflow must keep private registry and entitlement boundaries explicit |

## Runtime Model Comparison

| Runtime model | Fit for current workflows | Decision |
| --- | --- | --- |
| Retained Image Builder VM with `composer-cli` | Matches existing RHEL 8 rpm-ostree blueprint, compose, SSH, ISO, OSTree, and publication behavior | Keep as default |
| Privileged `bootc-image-builder` Tekton task | Potentially viable for a future bootc disk/ISO artifact, but requires privileged SCC, local container storage, registry authentication, and a separate bootc source-image workflow | Do not add in this slice |
| External CI or build host | Plausible for bootc artifacts without mutating cluster SCC policy, but still needs private registry, entitlement, output publication, and RHEL target decisions | Candidate future slice |
| Prebuilt bootc image consumed by this repo | Useful for publication-only experiments, but does not replace current blueprint compose, kickstart, ISO, and OSTree publish workflows | Candidate future slice after target choice |
| Hybrid RHEL 8/9 VM plus RHEL 10 bootc | Architecturally plausible because the product support boundary is version-specific | Defer until this fork chooses an explicit RHEL target/version policy |

## Implemented Boundary

No chart, Pipeline, or Ansible runtime behavior changed in this slice.

That is intentional: the inventory did not prove a no-VM replacement for every enabled workflow, and adding a
privileged `bootc-image-builder` task would introduce a new cluster security-policy dependency before the target RHEL
version and runtime model are settled. Existing Plan 0004 `publicationEndpoints` values remain the boundary for
current publication behavior, and no new behavior hard-codes Quay, Nexus, or HTTPD assumptions.

Future implementation should start with one of these explicit choices:

- Current RHEL 8-oriented continuity, or an explicit RHEL 9 Image Builder path: keep the VM and only improve
  lifecycle/validation around the retained compose runtime.
- RHEL 10 image mode: add a separate bootc source-image workflow and make rpm-ostree/composer paths unsupported for
  that target.
- Experimental bootc: add a disabled-by-default workflow only after deciding whether builds run in a privileged
  OpenShift Pipeline or on an external build host.

## Risks

- RHEL 8/9 rpm-ostree workflows and RHEL 10 image-mode workflows may not be interchangeable.
- `bootc-image-builder` may require privileged execution, root access, subscription material, or host bind mounts that
  do not fit the current OpenShift Pipeline security model.
- Replacing the VM could accidentally remove current ISO, kickstart, OSTree publication, or registry push behavior.
- A partial no-VM implementation could create two competing artifact models without clear version or workflow
  boundaries.
- Current docs and examples still reference older RHEL for Edge behavior; updating them broadly may exceed this slice.

## Open Questions

- Which RHEL major version should this fork optimize for first after preserving the current RHEL 8-oriented workflow?
- If bootc is pursued, should the desired runtime be a privileged OpenShift Pipeline, an external CI/build host, or a
  hybrid model?
- Which artifact should be the first explicit bootc candidate: source OCI image, ISO, raw/qcow2 disk, or
  publication-only workflow?
- Are privileged build containers acceptable in the target cluster for `bootc-image-builder`?
- Should future no-VM support become a workflow mode, a component runtime mode, or a separate chart?
