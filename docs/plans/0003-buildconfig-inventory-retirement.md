# Plan 0003: BuildConfig Inventory and Retirement

## Status

Implemented on the `custom` branch.

## Goal

Inventory every remaining OpenShift `BuildConfig` path, decide whether each path should be retained, retired, supplied
externally, or migrated later, and remove BuildConfig assumptions from the modern path where the evidence supports a
safe bounded change.

This slice begins BuildConfig modernization with workflow inventory and disposition. It must not directly translate
every `BuildConfig` to a Tekton replacement just because a `BuildConfig` exists.

## Governing Context

- [ADR 0001: Modern RFE Architecture Direction](../adr/0001-modern-rfe-architecture.md)
- [Current State Inventory](../current-state-inventory.md)
- [Plan 0001: ArgoCD Targeting, AppProject, and Access Separation](0001-argocd-targeting-appproject-access.md)
- [Plan 0002: Image Builder VM DataSource Modernization](0002-image-builder-datasource-modernization.md)

## Accepted Decisions

- BuildConfig modernization starts with inventory, not automatic Tekton translation.
- The Image Builder VM remains the compose runtime for now.
- The modern Image Builder VM root disk is DataSource-backed and must not regain a Nexus/PVC base-image staging
  prerequisite.
- `ansible-rfe-runner` and HTTPD OSTree image build behavior are the known BuildConfig candidates.
- `ansible-rfe-runner` may become a prebuilt image, an externally supplied image, a Tekton-built image, or a retained
  reference-profile build after inventory.
- HTTPD may become a standard/prebuilt image, remain a managed reference-profile service, become an externally supplied
  serving endpoint, or be deferred to the artifact-publication endpoint slice after inventory.
- Preserve current default BuildConfig rendering for compatibility in this slice.
- Externalize `ansible-rfe-runner` image references in downstream consumers while preserving the current internal
  ImageStreamTag default.
- Allow the chart-managed HTTPD service to use an externally supplied image by setting `buildConfig.enabled=false` and
  `image.repository`.
- Do not redesign artifact publication in this slice.
- Do not introduce bootc/image-mode or no-VM runtime replacement in this slice.
- Do not implement the full `components.*.mode` lifecycle model in this slice.

## Scope

### 1. Inventory BuildConfig Resources

Confirm all rendered and source-defined `BuildConfig` resources.

Known candidates:

- `charts/ansible-rfe-runner/templates/ansible-rfe-runner-buildconfig.yaml`
- `charts/httpd/templates/httpd-ostree-buildconfig.yaml`

For each candidate, record:

- rendered resource name and namespace;
- rendered output `ImageStreamTag`;
- triggering conditions;
- source image and build strategy;
- build-time secrets and entitlement dependencies;
- downstream consumers;
- whether the modern path needs the build, the built image, both, or neither.

### 2. Inventory Downstream Image Consumers

Trace image references that depend on BuildConfig outputs.

Known `ansible-rfe-runner` consumers include:

- Image Builder VM configuration jobs;
- Quay setup job;
- MachineSet job;
- RFE Pipeline tasks;
- legacy redhat-image-downloader job when the explicit legacy PVC path is enabled.

Known HTTPD consumers include:

- HTTPD deployment image trigger;
- staged OSTree content serving;
- kickstart and ISO publication paths;
- Ansible roles that locate or write to the HTTPD pod.

### 3. Decide Disposition Per Build Path

Classify each BuildConfig as one of:

- `retain-reference`: keep only for reference-full-stack or explicit managed-reference behavior;
- `externalize`: replace modern default assumptions with a configured image or endpoint;
- `retire`: remove from modern rendering because no modern workflow needs it;
- `defer-migration`: keep current behavior temporarily and document why migration requires a later slice;
- `migrate-later`: keep current behavior until a planned Tekton or other implementation slice replaces it.

Disposition must be evidence-backed. Do not remove a BuildConfig when consumers still require its output unless the
same change supplies a clear modern replacement.

### 4. Implement Only Safe Bounded Changes

Make implementation changes only where the inventory proves the change is safe within this slice.

Candidate bounded changes:

- add explicit image override values for `ansible-rfe-runner` consumers while preserving current defaults;
- add render-time validation for required external image or serving endpoint values if a modern path is externalized;
- gate a BuildConfig behind a clearly named legacy/reference value when modern renders no longer need it;
- add focused docs/examples that show the modern BuildConfig boundary.

Avoid broad lifecycle modeling, application-manager rewrites, or artifact-publication endpoint redesign.

### 5. Preserve Current Workflow Names and Runtime Model

Keep current workflow names stable unless a disposition explicitly removes a resource from the modern path:

- `BuildConfig/ansible-rfe-runner`
- `ImageStream/ansible-rfe-runner`
- `BuildConfig/httpd-ostree`
- `ImageStream/httpd-ostree`
- `Deployment/httpd`
- existing RFE Pipeline and Task names
- Image Builder VM names retained by Plan 0002

If a modern default stops rendering a BuildConfig, verify that the remaining consumers no longer require the removed
resource.

## Inventory Results

Targeted source search found two source-defined `BuildConfig` templates:

| Build path | Source template | Rendered resource | Rendered output | Trigger | Build source and strategy | Build-time dependencies | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ansible runner image | `charts/ansible-rfe-runner/templates/ansible-rfe-runner-buildconfig.yaml` | `BuildConfig/ansible-rfe-runner` in `rfe` | `ImageStreamTag/ansible-rfe-runner:latest` | `ConfigChange` | inline Dockerfile from `registry.access.redhat.com/ubi8/python-38:latest`, Docker strategy from the same Docker image | no build source secrets; downloads OpenShift client at build time | `retain-reference` plus `externalize` consumers |
| HTTPD OSTree image | `charts/httpd/templates/httpd-ostree-buildconfig.yaml` | `BuildConfig/httpd-ostree` in `rfe` | `ImageStreamTag/httpd-ostree:latest` | `ConfigChange` | inline Dockerfile from `registry.redhat.io/rhel8/httpd-24`, Docker strategy from `ImageStreamTag/httpd:2.4-el8` in `openshift` | build secrets `etc-pki-entitlement`, `rhsm-ca`, and `rhsm-conf`; enables RHEL BaseOS and AppStream repos to install `ostree` | `defer-migration` plus optional `externalize` chart image |

The rendered `ansible-rfe-runner` `BuildConfig` creates a built image used by downstream jobs and Pipeline tasks. The
consumers need an image that contains Ansible, required Python/Kubernetes libraries, `skopeo`, and `oc`; none of the
consumers directly read or mutate the `BuildConfig` object.

Direct `ansible-rfe-runner` image consumers:

- `charts/image-builder-vm/templates/image-builder-vm-ansible-job.yaml`
- `charts/image-builder-vm/templates/redhat-image-downloader-ansible-job.yaml`, only when the explicit legacy PVC path
  is enabled
- `charts/quay/templates/quay-setup-job.yaml`
- `charts/machineset/templates/aws-machineset-ansible-job.yaml`
- `charts/rfe-pipelines/templates/rfe-oci-build-auto-iso-task.yaml`
- `charts/rfe-pipelines/templates/rfe-oci-build-image-task.yaml`
- `charts/rfe-pipelines/templates/rfe-oci-build-installer-image-task.yaml`
- `charts/rfe-pipelines/templates/rfe-oci-publish-content-task.yaml`
- `charts/rfe-pipelines/templates/rfe-oci-push-image-task.yaml`
- `charts/rfe-pipelines/templates/rfe-oci-quay-repository-task.yaml`
- `charts/rfe-pipelines/templates/rfe-oci-stage-image-task.yaml`
- `charts/rfe-pipelines/templates/upload-kickstart-task.yaml`

The rendered HTTPD chart creates `Deployment/httpd`, `Service/httpd`, `Route/httpd`, `PVC/httpd`,
`BuildConfig/httpd-ostree`, and `ImageStream/httpd-ostree`. Default deployment image selection is driven by an
OpenShift ImageStream trigger that points at `httpd-ostree:latest`. The Ansible publication workflows locate
`Deployment/httpd` pods and routes rather than the `BuildConfig` object, but the default chart-managed service still
depends on a runnable HTTPD image and persistent `/var/www/html` storage.

Direct HTTPD serving and publication consumers:

- `ansible/playbooks/oci-publish-content.yaml` uses `openshift-httpd-pod-imi` to target the chart-managed HTTPD pod.
- `ansible/playbooks/oci-build-auto-iso.yaml` uses `openshift-httpd-pod-imi` to copy generated ISOs into the HTTPD pod.
- `ansible/playbooks/iso-generator.yaml` uses `openshift-httpd-pod-imi` for the legacy ISO copy path.
- `ansible/playbooks/upload-kickstart.yaml` uploads templated kickstarts through the `content-download-upload` role,
  which can copy artifacts into the chart-managed HTTPD pod.
- `ansible/roles/oci-publish-content/tasks/main.yaml` initializes and mirrors OSTree content into the chart-managed
  HTTPD web root and reads `Route/httpd`.
- `ansible/roles/oci-build-auto-iso/tasks/main.yaml` uploads the generated ISO to Nexus and pulls it into the
  chart-managed HTTPD pod, then reads `Route/httpd`.
- `ansible/roles/content-download-upload/tasks/upload-rfe-artifact.yaml` copies or unarchives artifacts into the HTTPD
  pod and emits the serving URL.
- `ansible/roles/oci-stage-content/tasks/main.yaml` dynamically creates per-image ImageStreams, deployments, services,
  and routes for staged content; that path is separate from `BuildConfig/httpd-ostree` but still uses OpenShift image
  triggers.

The HTTPD BuildConfig secrets are produced by `ansible/playbooks/configure-image-builder.yaml`, which harvests RHSM
configuration, entitlement material, and CA files from the configured Image Builder VM before creating
`etc-pki-entitlement`, `rhsm-ca`, and `rhsm-conf` in `rfe`.

## Implemented Boundaries

This slice does not remove default BuildConfig rendering. The inventory showed that consumers still require the built
runner image and the chart-managed HTTPD service still has publication consumers. Removing either BuildConfig by default
would require a broader replacement model than Plan 0003 allows.

Implemented bounded changes:

- `image-builder-vm` now uses `ansibleRunner.image` and `ansibleRunner.imagePullPolicy` for both the normal VM
  configuration job and the explicit legacy downloader job.
- `rfe-pipelines` now uses `ansibleRunner.image` for every Tekton task that runs Ansible.
- `quay` now uses `setupJob.ansibleRunnerImage` and `setupJob.ansibleRunnerImagePullPolicy`.
- `machineset` now uses `ansibleJob.image` and `ansibleJob.imagePullPolicy`.
- `httpd` now supports `buildConfig.enabled=false` with `image.repository` to render the chart-managed HTTPD service
  without `BuildConfig/httpd-ostree`, `ImageStream/httpd-ostree`, or the deployment ImageStream trigger.
- `httpd` fails Helm rendering when `buildConfig.enabled=false` is set without `image.repository`.
- `examples/values/buildconfig-external-images.yaml` records the external-image values boundary.

## Non-Goals

- Do not migrate all BuildConfigs to Tekton by default.
- Do not replace the Image Builder VM with Buildah, bootc, `bootc-image-builder`, or another no-VM workflow.
- Do not redesign artifact publication endpoints.
- Do not implement the full component lifecycle model.
- Do not change ArgoCD targeting, AppProject, or access-grant behavior except where a render check exposes a direct
  BuildConfig dependency.
- Do not remove Nexus, Quay, HTTPD, Pulp, or ODF broadly.
- Do not commit generated `temp/` manifests or secret material.

## Proposed Work Breakdown

### Component A: BuildConfig Inventory

Files likely inspected:

- `charts/ansible-rfe-runner/**`
- `charts/httpd/**`
- `charts/rfe-pipelines/**`
- `charts/image-builder-vm/**`
- `charts/quay/**`
- `charts/machineset/**`
- focused Ansible playbooks and roles that consume `ansible-rfe-runner` or HTTPD

Acceptance:

- every source-defined BuildConfig is listed;
- every rendered BuildConfig name and output image is recorded;
- direct downstream consumers are identified;
- the inventory distinguishes needing a build from needing a resulting image or endpoint.

### Component B: Ansible Runner Disposition

Files likely affected after inventory:

- `charts/ansible-rfe-runner/values.yaml`
- `charts/ansible-rfe-runner/templates/**`
- charts that reference `image-registry.openshift-image-registry.svc:5000/rfe/ansible-rfe-runner:latest`
- focused docs/examples

Acceptance:

- the plan states whether `ansible-rfe-runner` is retained, externalized, retired, deferred, or migrated later;
- modern Image Builder VM and RFE Pipeline renders do not gain hidden BuildConfig prerequisites;
- any new image override values are consistently consumed by affected templates;
- retained defaults preserve current behavior unless the disposition explicitly changes it.

### Component C: HTTPD Build Disposition

Files likely affected after inventory:

- `charts/httpd/values.yaml`
- `charts/httpd/templates/**`
- Ansible roles that locate HTTPD or publish content to it
- focused docs/examples

Acceptance:

- the plan states whether HTTPD's custom OSTree image build is retained, externalized, retired, deferred, or migrated
  later;
- the modern path does not require an entitlement-backed HTTPD BuildConfig unless the inventory proves it is still
  necessary;
- HTTPD service, route, PVC, and publication behavior are not redesigned in this slice unless directly required by the
  chosen disposition.

### Component D: Docs and Examples

Files likely affected:

- `docs/current-state-inventory.md`
- `docs/plans/0003-buildconfig-inventory-retirement.md`
- focused examples under `examples/values/**`

Acceptance:

- docs record the BuildConfig inventory and disposition decisions;
- docs preserve the no-VM and artifact-publication non-goals;
- examples do not imply modern users must run obsolete or unneeded BuildConfigs.

### Component E: Verification

Primary verification is Helm rendering plus targeted source searches.

Acceptance:

- default render behavior for affected charts is known and intentionally preserved or intentionally changed;
- removed or gated modern BuildConfig paths are absent from rendered output;
- retained legacy/reference BuildConfig paths render only under explicit values if gated;
- RFE Pipeline and Image Builder VM names remain stable unless intentionally changed;
- `git diff --check` passes.

## Verification Strategy

Start with inventory renders:

```shell
helm template ansible-rfe-runner charts/ansible-rfe-runner --namespace rfe
helm template httpd charts/httpd --namespace rfe
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
```

Use targeted searches:

```shell
rg -n "kind: BuildConfig|ansible-rfe-runner:latest|httpd-ostree|image.openshift.io/triggers|openshift-httpd-pod-imi" charts ansible docs examples
```

If implementation changes add validation or gated modes, add negative Helm checks for invalid or missing required
values.

Finish with:

```shell
git diff --check
```

Local CRC/OpenShift integration is useful but additive. Before cluster tests, check `crc status`. Do not run
`crc setup`, `crc start`, or preset changes without explicit user approval.

## Risks

- `ansible-rfe-runner` is used widely by jobs and Pipeline tasks. Removing its BuildConfig without an image replacement
  would break current workflows.
- HTTPD is both a chart-managed service and an artifact-publication target. Removing its build may require a serving
  endpoint model that belongs to the later artifact-publication slice.
- The HTTPD BuildConfig currently uses entitlement/RHSM build secrets. Retaining it in modern defaults may conflict
  with BYO-first goals, but removing it prematurely may break reference workflows.
- Some OpenShift ImageStream usage may be runtime workflow behavior rather than build behavior. Do not collapse those
  concerns without evidence.
- Gating charts through ad hoc flags can conflict with the planned full component lifecycle model if the slice grows too
  broad.

## Resolved Decisions

- `ansible-rfe-runner` is externalized first at the consumer-image boundary. The producer BuildConfig remains available
  for reference/bootstrap behavior until a pinned prebuilt image, Tekton producer, or component lifecycle profile
  replaces it.
- HTTPD's custom OSTree-capable image build remains the default because `oci-publish-content` currently runs `ostree`
  inside the shared HTTPD pod. The chart can use an externally supplied image when `buildConfig.enabled=false`.
- Default renders continue to create both BuildConfigs in this slice. The external-image example proves the new
  boundary without changing default reference behavior.
- Each consumer chart owns validation only for values it can prove locally. This slice adds HTTPD validation because
  disabling that chart's BuildConfig without an image would render an unusable Deployment. Runner image validation is
  deferred until the component lifecycle model defines whether consumers require a local producer or a supplied image.
