# Plan 0006: RHEL Target and Runtime Boundary

## Status

Implemented on the `custom` branch.

## Goal

Make the repository's RHEL target version and artifact runtime assumptions explicit so current RHEL 8-oriented
Image Builder behavior is preserved intentionally, RHEL 9 Image Builder continuity can be expressed, and any future
RHEL 10 image-mode or bootc workflow is rejected until it has its own supported implementation boundary.

This slice follows Plan 0005's `retain-vm` disposition. It should not add a bootc runtime. It should add only the
values, validation, examples, and documentation needed to prevent silent mixing of rpm-ostree/Image Builder workflows
with image-mode/bootc assumptions.

## Governing Context

- [ADR 0001: Modern RFE Architecture Direction](../adr/0001-modern-rfe-architecture.md)
- [Current State Inventory](../current-state-inventory.md)
- [Plan 0001: ArgoCD Targeting, AppProject, and Access Separation](0001-argocd-targeting-appproject-access.md)
- [Plan 0002: Image Builder VM DataSource Modernization](0002-image-builder-datasource-modernization.md)
- [Plan 0003: BuildConfig Inventory and Retirement](0003-buildconfig-inventory-retirement.md)
- [Plan 0004: Artifact Publication Endpoint Modernization](0004-artifact-publication-endpoint-modernization.md)
- [Plan 0005: No-VM Artifact Workflow Evaluation](0005-no-vm-artifact-workflow-evaluation.md)

## Accepted Decisions

- The Image Builder VM remains the supported default artifact runtime.
- Current workflow behavior is RHEL 8-oriented and rpm-ostree/Image Builder based.
- RHEL 9 Image Builder continuity is a supported direction to model, but the repository must not claim a RHEL 9 default
  until rendered values, refs, repositories, and examples are updated deliberately.
- RHEL 10 image mode and bootc are future paths, not default behavior.
- The current `composer-cli`, `osbuild-composer`, SSH, OSTree publication, kickstart, and autoboot ISO workflows must
  not be silently translated to bootc.
- The modern Image Builder VM root disk remains OpenShift Virtualization `DataSource` backed.
- The PVC/Nexus base-image staging path remains legacy/reference behavior and must not return to the modern path.
- Plan 0004 `publicationEndpoints` values remain the current publication boundary.
- No cluster-mutating CRC, OpenShift, or virtualization commands may run without explicit approval.

## Scope

### 1. Inventory Current Target-Version Assumptions

Trace all values, templates, Ansible roles, docs, and examples that encode a RHEL target version or rpm-ostree ref.

Known assumptions to inventory:

- `rhel8`, `rhel8.5`, and `pc-q35-rhel8.4.0` in the Image Builder VM chart.
- RHEL 8 RHSM repositories in `charts/rfe-pipelines` defaults and Image Builder configuration.
- `rhel/8/x86_64/edge` OSTree refs in ISO and publication roles.
- `rhel-edge-container`, `rhel-edge-installer`, and `rhel-edge-commit` compose image types.
- RHEL 8 HTTPD BuildConfig base images and repository enablement.
- docs and walkthroughs that describe Image Builder 8.x behavior as the general path.
- examples that users are likely to copy for current workflow runs.

For each assumption, record whether it is:

- runtime-critical and must remain tied to the current default;
- safe to parameterize in this slice;
- documentation-only and should be clarified;
- legacy/reference behavior;
- deferred because changing it would alter artifact behavior.

### 2. Define The Values Boundary

Add a narrow values API only where it prevents ambiguous runtime behavior.

Candidate model:

```yaml
rhelTarget:
  major: 8
  architecture: x86_64
  imageBuilder:
    enabled: true
    ostreeRef: rhel/8/x86_64/edge
    repositories:
      - rhel-8-for-x86_64-baseos-rpms
      - rhel-8-for-x86_64-appstream-rpms
  imageMode:
    enabled: false
```

The final shape should match existing chart style and avoid broad lifecycle modeling. It may be chart-local if a global
value would create premature cross-chart coupling.

### 3. Add Render-Time Validation

Invalid combinations should fail clearly at Helm render time before a user creates incompatible workflows.

Validation should reject at least:

- unsupported `rhelTarget.major` values;
- `rhelTarget.major=10` with the current Image Builder rpm-ostree workflows enabled;
- `rhelTarget.imageMode.enabled=true` without a future bootc/image-mode implementation;
- missing OSTree ref or RHSM repository values when Image Builder workflows need them;
- mismatched RHEL major and default OSTree ref where the chart can prove the mismatch locally.

Do not add validation that depends on live cluster state.

### 4. Parameterize Only Safe Defaults

Make bounded implementation changes after inventory proves the value can be parameterized without changing behavior.

Candidate changes:

- feed chart defaults for RHSM repositories from a single local value tree in `charts/rfe-pipelines`;
- feed `rhel/8/x86_64/edge` from a value into installer and publication tasks;
- expose Image Builder VM DataSource name, OS labels, and machine metadata as target-aware values only if current
  rendered defaults remain stable;
- document HTTPD BuildConfig RHEL 8 coupling rather than changing its build image if changing it would alter runtime
  behavior.

### 5. Examples and Documentation

Add examples that make the supported boundary obvious:

- current RHEL 8 Image Builder continuity example;
- optional RHEL 9 Image Builder planning example only if the rendered values are complete enough to be honest;
- explicit unsupported RHEL 10/image-mode example only as a negative validation case, not as a runnable workflow.

Update focused docs to say:

- current defaults are RHEL 8-oriented implementation facts;
- RHEL 9 Image Builder is the nearest Image Builder continuity target;
- RHEL 10 requires a separate image-mode/bootc workflow and must not use the current composer paths.

## Non-Goals

- Do not add a bootc, image-mode, or `bootc-image-builder` Pipeline.
- Do not make RHEL 10 a supported runtime for current rpm-ostree/Image Builder workflows.
- Do not remove the Image Builder VM.
- Do not migrate BuildConfigs to Tekton.
- Do not redesign artifact publication endpoints.
- Do not implement the full `components.*.mode` lifecycle model.
- Do not reintroduce Nexus/PVC base-image staging into the modern Image Builder VM boot path.
- Do not update broad walkthroughs unless a focused correction is required to prevent a wrong target/runtime claim.
- Do not run cluster-mutating validation without explicit approval.
- Do not commit generated `temp/` manifests or secret material.

## Proposed Work Breakdown

### Component A: Target Assumption Inventory

Files likely inspected:

- `charts/image-builder-vm/**`
- `charts/rfe-pipelines/**`
- `charts/httpd/**`
- `ansible/roles/image-builder/**`
- `ansible/roles/oci-build-image/**`
- `ansible/roles/oci-build-installer-image/**`
- `ansible/roles/oci-publish-content/**`
- `ansible/roles/build-rpm-ostree/**`
- `docs/**`
- `examples/values/**`

Acceptance:

- every RHEL major, RHSM repo, architecture, OSTree ref, Image Builder image type, and boot media assumption in the
  active workflow surface is listed;
- each assumption has a disposition: preserve, parameterize, document, legacy, or defer.

### Component B: Values and Validation

Files likely changed:

- `charts/rfe-pipelines/values.yaml`
- `charts/rfe-pipelines/templates/_validation.tpl`
- focused `charts/rfe-pipelines/templates/*` files that pass RHEL target values into task extra vars
- `charts/image-builder-vm/values.yaml`
- `charts/image-builder-vm/templates/_validation.tpl`

Acceptance:

- current default renders remain behaviorally stable;
- invalid RHEL target/runtime combinations fail at Helm render time;
- `imageMode.enabled=true` fails clearly until a later plan implements a real bootc path;
- supported values do not imply RHEL 10 composer support.

### Component C: Ansible Runtime Inputs

Files likely changed only after chart values exist:

- `ansible/roles/oci-build-installer-image/tasks/main.yaml`
- `ansible/roles/oci-publish-content/tasks/main.yaml`
- `ansible/roles/image-builder/tasks/main.yaml`
- `ansible/roles/build-rpm-ostree/tasks/main.yaml`

Acceptance:

- hard-coded RHEL 8 refs or repositories are parameterized only when the calling chart or playbook supplies an explicit
  value;
- default behavior remains equivalent for RHEL 8;
- missing required inputs fail clearly in Ansible or Helm before producing misleading artifacts.

### Component D: Examples and Docs

Files likely changed:

- `examples/values/rhel-target-image-builder-rhel8.yaml`
- `examples/values/rhel-target-image-mode-unsupported.yaml`
- `docs/current-state-inventory.md`
- `docs/plans/0006-rhel-target-runtime-boundary.md`

Acceptance:

- examples show the supported current target boundary and at least one unsupported negative case;
- docs record that RHEL 8 defaults are implementation facts, not fresh product support claims;
- docs identify RHEL 9 Image Builder and RHEL 10 image mode as separate future decisions.

### Component E: Verification

Minimum verification:

```sh
rg -n "rhel8|rhel8.5|rhel-8|rhel/8/x86_64/edge|rhel-edge-container|rhel-edge-installer|rhel-edge-commit|rhelTarget|imageMode|bootc" charts ansible docs examples
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template httpd charts/httpd --namespace rfe
git diff --check
```

If validation is added, include negative render checks for unsupported `rhelTarget.major=10`,
`imageMode.enabled=true`, and missing required Image Builder target values.

If any parameterization changes rendered manifests, compare default render output before and after for the affected
fields and record why the change is intentional.

## Verification Strategy

Use Helm rendering as the primary verification path. Local CRC/OpenShift validation is additive and must not run
without explicit approval when it mutates host or cluster state.

Recommended checks:

```sh
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template httpd charts/httpd --namespace rfe
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe --set rhelTarget.major=10
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe --set rhelTarget.imageMode.enabled=true
git diff --check
```

## Risks

- A global-looking target value can imply broader cross-chart support than this slice actually implements.
- RHEL 8 and RHEL 9 Image Builder behavior may be similar enough to invite unsafe generalization, but values still need
  explicit refs, repositories, DataSources, and examples.
- RHEL 10 image mode has overlapping artifact names but a different source/runtime model.
- Parameterizing docs without parameterizing templates can make examples lie; parameterize only where verification
  proves the rendered behavior.
- Broad README/walkthrough rewrites can exceed the slice and obscure the runtime boundary.

## Open Questions

- Should target-version validation move into a shared helper once a broader component lifecycle model exists?

## Resolved Decisions

- `rhelTarget` is chart-local to `charts/rfe-pipelines` and `charts/image-builder-vm` in this slice. A shared global
  value would imply cross-chart lifecycle support that this plan does not implement.
- RHEL 8 remains the default target for current rendered workflows. The defaults are implementation facts, not a fresh
  product support claim.
- RHEL 9 Image Builder continuity is modelable only when callers supply explicit RHEL 9 values. This slice does not add
  a runnable RHEL 9 example because the VM DataSource, VM metadata, repository list, OSTree ref, and operational test
  boundary need to be chosen deliberately together.
- RHEL 10 image-mode and bootc remain unsupported for the current composer workflows. `rhelTarget.major=10` and
  `rhelTarget.imageMode.enabled=true` fail Helm rendering.
- HTTPD's RHEL 8 BuildConfig base image and RHEL 8 repository enablement remain documented reference coupling until a
  later artifact-publication or serving-runtime slice changes that behavior.

## Target Assumption Inventory

| Assumption | Disposition | Evidence |
| --- | --- | --- |
| RHEL 8 default target | Preserve | `charts/rfe-pipelines/values.yaml`, `charts/image-builder-vm/values.yaml` |
| `x86_64` architecture | Parameterize | `rhelTarget.architecture` in `charts/rfe-pipelines` and `charts/image-builder-vm` |
| RHEL 8 BaseOS/AppStream RHSM repositories | Parameterize | `rhelTarget.imageBuilder.repositories`; Image Builder VM configuration receives `image_builder_rhsm_repositories` |
| `rhel/8/x86_64/edge` OSTree ref | Parameterize | `rhelTarget.imageBuilder.ostreeRef`, `rfe-oci-build-installer-image`, and `rfe-oci-publish-content` |
| `rhel-edge-container` and `rhel-edge-installer` compose types | Parameterize | `rhelTarget.imageBuilder.composeTypes` and corresponding Ansible role defaults |
| `rhel-edge-commit` compose type | Legacy/reference | `ansible/roles/build-rpm-ostree` now has an overrideable default but is not wired into modern pipelines |
| `DataSource/rhel8` in `openshift-virtualization-os-images` | Preserve | `imageBuilderVM.dataSource` remains the modern VM root disk default |
| `pc-q35-rhel8.4.0`, RHEL 8.5 labels, and VM description | Document | VM metadata remains overrideable values; changing defaults would alter current VM behavior |
| Legacy PVC/Nexus qcow2 boot path | Legacy | Still requires `imageBuilderVM.dataVolumeSource=pvc` plus `legacyPvcSource.enabled=true` |
| HTTPD RHEL 8 base image and `httpd:2.4-el8` build input | Document | HTTPD remains managed-reference because current publication needs the writable pod, PVC, route, and `ostree` tooling |
| RHEL 10 image mode and bootc | Defer/reject | Unsupported until a later plan adds a separate bootc/image-mode implementation |

## Implemented Boundary

`charts/rfe-pipelines` now exposes:

```yaml
rhelTarget:
  major: 8
  architecture: x86_64
  imageBuilder:
    enabled: true
    ostreeRef: rhel/8/x86_64/edge
    composeTypes:
      container: rhel-edge-container
      installer: rhel-edge-installer
    repositories:
      - rhel-8-for-x86_64-baseos-rpms
      - rhel-8-for-x86_64-appstream-rpms
  imageMode:
    enabled: false
```

The chart renders those values into the existing pipeline and task names without adding new runtime resources:

- `rfe-oci-image-pipeline` uses the target repository list for the default `rhsm-repositories` parameter and passes the
  configured container compose type to `rfe-oci-build-image`.
- `rfe-oci-iso-pipeline` uses the target repository list and passes the configured OSTree ref and installer compose
  type to `rfe-oci-build-installer-image`.
- `rfe-oci-publish-content-pipeline` passes the configured OSTree ref to `rfe-oci-publish-content`.

`charts/image-builder-vm` now exposes chart-local `rhelTarget` values for Image Builder VM validation and RHSM
repository configuration. The default render still creates `VirtualMachine/image-builder-000`,
`Service/image-builder-000`, and `Job/image-builder-vm-ansible-job`, still uses `DataSource/rhel8` in
`openshift-virtualization-os-images`, and still avoids the legacy downloader/PVC/Nexus base-image path.

Focused examples:

- `examples/values/rhel-target-image-builder-rhel8.yaml`
- `examples/values/rhel-target-image-mode-unsupported.yaml`

## Support Boundary Sources

Primary Red Hat documentation reviewed on 2026-08-29:

- [RHEL 10 migration from rpm-ostree systems to bootc-based systems](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/composing_installing_and_managing_rhel_for_edge_images/migrating-from-rpm-ostree-based-deployed-systems-to-bootc-based-systems)
- [RHEL 10 image mode introduction](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/introducing-image-mode-for-rhel)
- [RHEL 9 Edge considerations and supported image types](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/considerations_in_adopting_rhel_9/assembly_edge_considerations-in-adopting-rhel-9)
- [OpenShift Virtualization VM boot sources](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/virtualization/virtual-machines)
- [RHEL 9 repository IDs](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/upgrading_from_rhel_8_to_rhel_9/appendix_rhel-9-repositories_upgrading-from-rhel-8-to-rhel-9)

These sources support the version boundary used here: RHEL 9 still has an Image Builder RHEL for Edge continuity path,
while RHEL 10 edge image creation requires image mode/bootc and cannot silently reuse this repository's current
`composer-cli` rpm-ostree workflow.
