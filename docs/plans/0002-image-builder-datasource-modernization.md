# Plan 0002: Image Builder VM DataSource Modernization

## Status

Implemented on the `custom` branch.

## Goal

Make the modern Image Builder VM path explicitly OpenShift Virtualization `DataSource` backed, and stop treating the
legacy PVC/Nexus base-image staging path as a first-class modern option.

The Image Builder VM remains the RHEL for Edge compose runtime for this slice. This plan does not replace the VM with
Buildah, bootc, `bootc-image-builder`, or another no-VM workflow.

## Governing Context

- [ADR 0001: Modern RFE Architecture Direction](../adr/0001-modern-rfe-architecture.md)
- [Current State Inventory](../current-state-inventory.md)
- [Plan 0001: ArgoCD Targeting, AppProject, and Access Separation](0001-argocd-targeting-appproject-access.md)

## Accepted Decisions

- Keep the Image Builder VM as the compose runtime for now.
- The modern Image Builder VM root disk should come from an OpenShift Virtualization `DataSource`.
- Nexus may still be used for produced artifacts, but it should not be required to boot the Image Builder VM.
- The PVC/Nexus base-image staging path is legacy/reference behavior, not the modern default.
- Retain the legacy PVC/Nexus boot path behind `imageBuilderVM.dataVolumeSource: pvc` plus
  `imageBuilderVM.legacyPvcSource.enabled: true`.
- Keep `imageBuilderVM.dataVolumeSource` as the source mode for this compatibility slice.
- Keep the modern example focused on the Image Builder VM chart values.
- Do not redesign artifact publication in this slice.
- Do not migrate BuildConfigs in this slice.
- Do not implement the full `components.*.mode` lifecycle model in this slice.

## Scope

### 1. Define DataSource Values

Add explicit values for the Image Builder VM source `DataSource`.

Proposed shape:

```yaml
imageBuilderVM:
  dataSource:
    name: rhel8
    namespace: openshift-virtualization-os-images
```

The first implementation should keep compatibility with the current default rendered output:

- `DataSource` name: `rhel8`
- `DataSource` namespace: `openshift-virtualization-os-images`
- VM/service/job names remain stable unless a required validation change proves otherwise.

### 2. Validate Modern Source Configuration

Add Helm render-time validation for Image Builder VM source selection.

Validation should fail clearly when:

- `imageBuilderVM.dataVolumeSource` is not a supported value;
- the modern `datasource` path is enabled without a `dataSource.name`;
- the modern `datasource` path is enabled without a `dataSource.namespace`;
- `imageBuilderVM.replicas` is invalid.

The existing replica validation should be corrected if needed so the message and predicate agree.

### 3. Gate Legacy PVC/Nexus Boot Path

Keep the old PVC/Nexus boot path only behind an explicit legacy flag, or remove it if compatibility impact is small.

If retained, it must be visibly legacy in values and validation. It must not render in modern examples or defaults.

The legacy path includes:

- the `DataVolume` HTTP source that pulls from `http://nexus:8081/repository/rfe-rhel-media/...`;
- `redhat-image-downloader-ansible-job`;
- the `ansible/playbooks/redhat-image-downloader.yaml` base-image upload workflow;
- any values that imply Nexus is needed for VM boot.

### 4. Keep VM Runtime Behavior Stable

Preserve the current VM compose-runtime behavior:

- `VirtualMachine/image-builder-000` and additional indexed VM names;
- `Service/image-builder-000` and additional indexed services;
- `Job/image-builder-vm-ansible-job`;
- RHSM and SSH secret usage for configuring the VM;
- `osbuild-composer` / `composer-cli` based workflows.

Do not change Quay, Nexus, HTTPD, Pulp, Pipelines, or Ansible artifact-publication behavior except where directly
required to remove modern VM boot coupling to Nexus.

### 5. Examples and Documentation

Add or update focused example values showing the modern DataSource-backed VM path.

Document:

- expected default DataSource values;
- how to override the DataSource name and namespace;
- that PVC/Nexus base-image staging is legacy/reference behavior;
- that cluster integration tests should use CRC `openshift` only with explicit approval before host-mutating commands.

## Non-Goals

- Do not replace the Image Builder VM with a containerized compose runtime.
- Do not introduce bootc/image-mode artifact workflows.
- Do not migrate `BuildConfig` resources to Pipelines.
- Do not refactor artifact publication endpoints.
- Do not implement the full component lifecycle model.
- Do not remove Nexus as an artifact repository for produced artifacts.
- Do not change ArgoCD targeting, AppProject, or access-grant behavior from Plan 0001 unless a render check exposes a
  direct dependency.
- Do not commit generated `temp/` manifests or secret material.

## Proposed Work Breakdown

### Component A: Values and Validation

Files likely affected:

- `charts/image-builder-vm/values.yaml`
- `charts/image-builder-vm/templates/_helpers.tpl`
- `charts/image-builder-vm/templates/_validation.tpl`

Acceptance:

- supported source modes are documented in values;
- invalid source mode fails at Helm render time;
- missing DataSource name or namespace fails at Helm render time for the modern path;
- replica validation accurately enforces the accepted lower bound.

### Component B: VM DataVolume Source

Files likely affected:

- `charts/image-builder-vm/templates/image-builder-vm.yaml`

Acceptance:

- the default render uses `sourceRef.kind: DataSource`;
- the default render uses configured `imageBuilderVM.dataSource.name`;
- the default render uses configured `imageBuilderVM.dataSource.namespace`;
- current VM names and service linkage remain stable.

### Component C: Legacy Downloader and PVC Path

Files likely affected:

- `charts/image-builder-vm/templates/redhat-image-downloader-ansible-job.yaml`
- `charts/image-builder-vm/values.yaml`
- focused docs or examples

Acceptance:

- default render does not include `redhat-image-downloader-ansible-job`;
- default render does not include `rfe-rhel-media`;
- default render does not include `http://nexus:8081/repository/rfe-rhel-media`;
- if the legacy path is retained, it renders only when explicitly enabled and clearly named legacy values are set.

### Component D: Examples and Docs

Files likely affected:

- `examples/values/image-builder-vm-datasource.yaml`
- `docs/plans/0002-image-builder-datasource-modernization.md`
- README or focused docs only if needed

Acceptance:

- a focused modern values file renders the DataSource-backed VM path;
- docs record the retained VM runtime boundary and no-VM non-goal;
- docs do not imply Nexus is required for modern VM boot.

### Component E: Verification

Files likely inspected:

- `charts/image-builder-vm/**`
- `charts/rfe-pipelines/**`
- `ansible/playbooks/redhat-image-downloader.yaml`
- focused Nexus files only if the legacy path remains wired

Acceptance:

- VM/service/job rendered names remain stable for the modern path;
- `rfe-pipelines` rendered names remain stable;
- no modern render path adds access or workflow prerequisites for downloader/PVC/Nexus base-image staging;
- Helm failures are clear for invalid source configuration.

## Verification Strategy

Use Helm rendering as the primary verification.

Minimum checks:

```shell
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template image-builder-vm charts/image-builder-vm --namespace rfe -f examples/values/image-builder-vm-datasource.yaml
helm template image-builder-vm charts/image-builder-vm --namespace rfe --set imageBuilderVM.dataSource.name=
helm template image-builder-vm charts/image-builder-vm --namespace rfe --set imageBuilderVM.dataSource.namespace=
helm template image-builder-vm charts/image-builder-vm --namespace rfe --set imageBuilderVM.dataVolumeSource=invalid
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
git diff --check
```

When checking rendered output, confirm:

- default modern output includes `sourceRef.kind: DataSource`;
- default modern output includes `name: rhel8`;
- default modern output includes `namespace: openshift-virtualization-os-images`;
- default modern output does not include `redhat-image-downloader-ansible-job`;
- default modern output does not include `rfe-rhel-media`;
- invalid configurations fail before producing manifests.

Local CRC/OpenShift integration is useful but additive. Before cluster tests, check `crc status`. Do not run
`crc setup`, `crc start`, or preset changes without explicit user approval.

## Risks

- Removing the PVC/Nexus path outright may break old reference deployments that still depend on manually staged qcow2
  media.
- Retaining the PVC/Nexus path under a legacy flag may preserve code that should disappear later, but it reduces
  compatibility risk for this slice.
- DataSource names differ across OpenShift Virtualization versions and imported OS images; values must allow override.
- The chart currently hard-codes the workload namespace as `rfe`; changing that belongs to a later lifecycle/profile
  slice unless required for validation.
- The VM configuration job still depends on the internal `ansible-rfe-runner` image and RHSM/SSH secrets. That is
  retained behavior, not solved here.

## Resolved Decisions

- The PVC/Nexus boot path is retained for reference compatibility only behind
  `imageBuilderVM.dataVolumeSource: pvc` and `imageBuilderVM.legacyPvcSource.enabled: true`.
- The downloader job is tied to the explicit legacy PVC source mode rather than a separate modern workflow flag.
- The existing `imageBuilderVM.dataVolumeSource` field remains the source mode for this slice.
- The modern example is focused on the Image Builder VM chart values.

## Implementation Notes

The modern chart default is `imageBuilderVM.dataVolumeSource: datasource`, backed by configurable
`imageBuilderVM.dataSource.name` and `imageBuilderVM.dataSource.namespace` values. The default values remain `rhel8`
and `openshift-virtualization-os-images`.

The legacy PVC/Nexus branch remains available for reference deployments only when both of these values are set:

```yaml
imageBuilderVM:
  dataVolumeSource: pvc
  legacyPvcSource:
    enabled: true
```

Modern renders continue to create `VirtualMachine/image-builder-000`, `Service/image-builder-000`, and
`Job/image-builder-vm-ansible-job`, but do not create the legacy downloader job.
