# Plan 0004: Artifact Publication Endpoint Modernization

## Status

Implemented on the `custom` branch.

## Goal

Refactor artifact publication around explicit endpoint contracts so workflows can consume configured registry,
repository storage, and HTTP serving targets instead of assuming repo-managed Quay, Nexus, and HTTPD resources.

This slice starts with inventory and disposition. It should make bounded implementation changes only where endpoint
assumptions are understood and a current workflow can be preserved.

## Governing Context

- [ADR 0001: Modern RFE Architecture Direction](../adr/0001-modern-rfe-architecture.md)
- [Current State Inventory](../current-state-inventory.md)
- [Plan 0001: ArgoCD Targeting, AppProject, and Access Separation](0001-argocd-targeting-appproject-access.md)
- [Plan 0002: Image Builder VM DataSource Modernization](0002-image-builder-datasource-modernization.md)
- [Plan 0003: BuildConfig Inventory and Retirement](0003-buildconfig-inventory-retirement.md)

## Accepted Decisions

- The Image Builder VM remains the RHEL for Edge compose runtime for now.
- The modern Image Builder VM root disk is DataSource-backed and must not regain a Nexus/PVC base-image staging
  prerequisite.
- Plan 0003 preserved default BuildConfig rendering for compatibility while externalizing `ansible-rfe-runner` image
  consumers and allowing HTTPD to use an externally supplied image.
- Artifact publication endpoint modernization is in scope for this plan.
- Nexus is optional produced-artifact storage, not a boot prerequisite for the modern base-image path.
- HTTPD currently remains part of existing publish and serve flows. `oci-publish-content` runs `ostree` operations
  through the chart-managed HTTPD pod, so an external HTTP URL alone may not replace the current service.
- Quay is a registry target, but repo-managed Quay setup should be separated from registry endpoint consumption.
- Do not migrate surviving BuildConfigs to Tekton in this slice.
- Do not implement the full `components.*.mode` lifecycle model unless a narrow endpoint mode is required to express
  one local boundary.
- Do not introduce bootc, image-mode, Buildah-only, or no-VM runtime replacement in this slice.

## Scope

### 1. Inventory Publication Endpoints and Consumers

Trace all chart, Tekton, and Ansible references to publication endpoints before changing behavior.

Known endpoint families:

- Registry and Quay:
  - `quay-rfe-setup`
  - `publisher`
  - `rfe-oci-quay-repository`
  - `rfe-oci-push-image`
  - `quay_image_path`
  - `quay_image_tag`
  - Quay route, repository, credential, and setup-job values
- Repository storage and Nexus:
  - `nexus-rfe-credentials`
  - `nexus-upload`
  - `upload-kickstart`
  - `oci-build-auto-iso`
  - `iso-generator`
  - `artifact-repository-storage-url`
  - Nexus route, upload path, and credential values
- HTTP serving and content publication:
  - `charts/httpd`
  - `openshift-httpd-pod-imi`
  - `content-download-upload`
  - `oci-publish-content`
  - `oci-stage-content`
  - `serving-storage-url`
  - `content-path`
  - HTTPD route, pod, PVC, and OSTree web-root assumptions
- Adjacent storage or content systems:
  - Pulp
  - ODF or object storage
  - Image stage and content stage resources

For each endpoint, record:

- producing chart or workflow;
- consuming chart, Tekton task, playbook, or role;
- required secret material;
- required route, service, pod, PVC, or API object;
- whether the consumer needs a URL, credentials, a pod execution target, persistent writable storage, or a managed
  application;
- whether the current endpoint can be externalized safely in this slice.

### 2. Define Endpoint Contracts

Introduce explicit value contracts only after the inventory identifies the consumer requirements.

Candidate endpoint contracts:

- `registry`: image registry host, namespace or organization, repository, image tag, push credentials, and pull
  credentials.
- `artifactRepository`: produced-artifact upload endpoint, path conventions, and credentials.
- `httpServing`: serving base URL, content path, and whether the implementation needs a chart-managed pod with writable
  storage and `ostree` tooling.

Prefer values that map to current workflows without broad renaming. Add render-time validation when a user chooses an
external endpoint mode that requires missing values.

### 3. Separate Managed Setup From Endpoint Consumption

Separate consumers from setup charts where the current workflow allows it.

Expected dispositions:

- `managed-reference`: keep the repo-managed service as the default or reference implementation.
- `externalize`: allow consumers to use a configured external endpoint without rendering or depending on the
  repo-managed setup path.
- `retain-reference`: keep current behavior because the workflow needs a pod, route, PVC, or tool-bearing service that
  is not replaced yet.
- `defer-redesign`: document the coupling and leave implementation to a later slice.
- `migrate-later`: keep current behavior until a planned workflow replacement exists.

Do not remove Quay, Nexus, or HTTPD resources by default unless the same change supplies a verified replacement for
every active consumer.

### 4. Implement Bounded Workflow Changes

Make only changes supported by the endpoint inventory and dispositions.

Candidate bounded changes:

- add explicit values for registry, repository storage, or HTTP serving endpoints;
- pass endpoint values into Tekton tasks or Ansible extra vars where consumers currently infer chart-managed routes;
- gate setup jobs separately from endpoint consumption where the workflow already supports external services;
- add Helm validation for unsupported external modes;
- update examples showing managed-reference and external endpoint configurations;
- document deferred endpoint couplings when implementation is not yet safe.

Avoid large Ansible role rewrites, application-manager redesign, or unrelated lifecycle modeling.

### 5. Preserve Runtime Compatibility

Keep existing workflow names and default behavior stable unless the endpoint disposition explicitly changes them:

- Quay setup and push tasks
- Nexus credentials and upload tasks
- HTTPD deployment, route, PVC, and content publication tasks
- RFE Pipeline and Task names
- Image Builder VM names retained by Plan 0002
- BuildConfig compatibility boundaries from Plan 0003

## Non-Goals

- Do not replace the Image Builder VM with bootc, image-mode, Buildah-only, or another no-VM workflow.
- Do not migrate BuildConfigs to Tekton.
- Do not implement a broad `components.*.mode` lifecycle model.
- Do not remove Quay, Nexus, HTTPD, Pulp, or ODF broadly.
- Do not redesign MachineSet, ArgoCD targeting, AppProject, or access-grant behavior except for direct endpoint
  dependencies discovered during this slice.
- Do not commit generated `temp/` manifests or secret material.
- Do not run CRC setup, CRC start, or cluster-mutating commands without explicit approval.

## Proposed Work Breakdown

### Component A: Endpoint Inventory

Files likely inspected:

- `charts/rfe-pipelines/**`
- `charts/httpd/**`
- `charts/quay/**`
- `charts/nexus/**`
- `ansible/playbooks/**`
- `ansible/roles/**`
- `docs/**`
- `examples/values/**`

Acceptance:

- registry, repository storage, and HTTP serving consumers are listed;
- route, service, pod, PVC, URL, credential, and result-file dependencies are recorded;
- each endpoint family has an evidence-backed disposition.

### Component B: Registry and Quay Boundary

Files likely changed if implementation is supported:

- `charts/rfe-pipelines/templates/*quay*`
- `charts/rfe-pipelines/templates/*push*`
- `charts/quay/**`
- focused Ansible role or playbook files that consume Quay endpoint values
- `docs/**`
- `examples/values/**`

Acceptance:

- consumers can distinguish a managed Quay setup path from a configured registry endpoint where supported;
- existing default Quay behavior still renders unless intentionally gated;
- push and repository tasks receive the same or more explicit registry data than before.

### Component C: Repository Storage and Nexus Boundary

Files likely changed if implementation is supported:

- `charts/rfe-pipelines/templates/*nexus*`
- `charts/rfe-pipelines/templates/upload-kickstart-task.yaml`
- `charts/nexus/**`
- focused Ansible role or playbook files that upload artifacts
- `docs/**`
- `examples/values/**`

Acceptance:

- Nexus is not reintroduced as a base-image prerequisite for the modern Image Builder VM path;
- produced-artifact upload consumers either accept explicit repository endpoint values or are documented as retained
  managed-reference flows;
- credential requirements are recorded without committing secret material.

### Component D: HTTP Serving and OSTree Publication Boundary

Files likely changed if implementation is supported:

- `charts/httpd/**`
- `charts/rfe-pipelines/templates/*publish*`
- `charts/rfe-pipelines/templates/*stage*`
- `ansible/roles/oci-publish-content/**`
- `ansible/roles/content-download-upload/**`
- focused ISO and kickstart upload roles
- `docs/**`
- `examples/values/**`

Acceptance:

- HTTP serving consumers are separated by need: URL-only, writable storage, route lookup, or pod execution target;
- `oci-publish-content` OSTree coupling is preserved or explicitly deferred;
- externally supplied HTTPD image support from Plan 0003 remains valid.

### Component E: Documentation and Verification

Files likely changed:

- `docs/current-state-inventory.md`
- `docs/plans/0004-artifact-publication-endpoint-modernization.md`
- `examples/values/**`

Acceptance:

- endpoint dispositions are recorded in the plan or current-state inventory;
- examples show the supported endpoint modes;
- verification commands and any deferred risks are recorded in the final implementation response.

## Verification Strategy

Use Helm rendering as the primary verification path.

Recommended checks:

```sh
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
helm template httpd charts/httpd --namespace rfe
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template quay charts/quay --namespace rfe
helm template nexus charts/nexus --namespace rfe
rg -n "quay-rfe-setup|publisher|nexus-rfe-credentials|nexus-upload|openshift-httpd-pod-imi|artifact-repository-storage-url|serving-storage-url|content-path|quay_image_path|quay_image_tag|httpd_route|nexus_route" charts ansible docs examples
git diff --check
```

If a chart has missing dependencies, run the relevant `helm dependency build` command before rendering and record it in
the final response.

If implementation adds validation, add at least one negative render check that proves missing required endpoint values
fail with a clear message.

Cluster validation is optional for this planning slice and additive for implementation. Do not run host-mutating CRC
commands without approval.

## Risks and Constraints

- Publication behavior is tightly coupled to Tekton params, Ansible variables, route lookups, and result files.
- `oci-publish-content` does more than serve files; it initializes and mirrors OSTree content through a chart-managed
  HTTPD pod.
- Nexus upload workflows may combine repository storage, credential creation, and HTTP serving assumptions.
- Quay setup currently creates or prepares registry state and credentials; endpoint consumption must not silently depend
  on the setup job when an external registry is configured.
- Pulp and ODF may be adjacent to artifact publication but should not be pulled into scope unless a direct consumer
  dependency is found.

## Resolved Decisions

- `publicationEndpoints` is the narrow local endpoint value boundary for this slice.
- Registry consumption supports `managed-reference` and `external`; external mode requires a pre-created image path and
  keeps push authentication explicit through `publisherSecretName`.
- Artifact repository storage supports `managed-reference` and `disabled`; full external repository storage is deferred
  because the current upload roles still combine internal service upload, route lookup, and credential discovery.
- HTTP serving remains `managed-reference`; full external HTTP serving is deferred because the current workflows need a
  writable pod, PVC-backed web root, route lookup, and `ostree` tooling.
- Pulp and ODF remain adjacent `migrate-later` systems for this slice.

## Inventory Results

### Registry and Quay

The managed Quay surface consists of `QuayRegistry/quay`, `Job/quay-setup-ansible-job`, `Secret/quay-rfe-setup`, and
`Secret/publisher`. The setup job runs `ansible/playbooks/quay-setup.yaml`, discovers
`QuayRegistry/quay.status.registryEndpoint`, creates the RFE organization/repositories/robot account, and writes the
publisher docker config secret.

Direct consumers:

- `rfe-oci-quay-repository` mounts `publisher` and `quay-rfe-setup`, runs
  `ansible/playbooks/oci-create-repository.yaml`, calls the Quay API, and writes the `image-path` Tekton result.
- `rfe-oci-push-image` needs only a concrete image path plus `/var/secrets/publisher/.dockerconfigjson` for `skopeo`.
- `rfe-oci-stage-image` needs an image path and tag. Its generated stage Deployment pulls through the
  `oci-rfe-httpd` service account and the existing `publisher` image pull secret.
- `rfe-oci-publish-content` treats the image path and tag as identifiers for staged service names and output paths.
- `rfe-oci-build-image` did not use the registry secrets it mounted.

Disposition: keep Quay as `managed-reference`; externalize registry consumption where a repository already exists by
allowing `rfe-oci-quay-repository` to bypass Quay API setup and emit a configured image path. Do not generalize Quay
repository creation into a generic registry provisioning task in this slice.

### Repository Storage and Nexus

The managed Nexus surface consists of `Nexus/nexus`, `Job/nexus-setup`, `Secret/nexus-rfe-credentials`, raw
repositories `rfe-kickstarts`, `rfe-tarballs`, `rfe-rhel-media`, and `rfe-auto-iso`, plus the `Service/nexus:8081` and
`Route/nexus` lookup used to produce public result URLs.

Direct consumers:

- `upload-kickstart` reads `Secret/nexus-rfe-credentials`, uploads the rendered kickstart through
  `content-download-upload`, and emits `artifact-repository-storage-url`.
- `content-download-upload` PUTs to `http://nexus:8081/repository/<repo>/...`, then reads `Route/nexus` to write the
  artifact repository result file.
- `oci-build-auto-iso` includes `nexus-upload` with repository `rfe-auto-iso`; this is produced-artifact storage only
  and its Nexus URL is not currently surfaced as a Tekton result.
- `download-upload-rfe-artifact` and the legacy `redhat-image-downloader` use the same Nexus credential pattern, but
  the downloader remains tied to the explicit legacy PVC boot path.

Disposition: keep Nexus as `managed-reference` for produced-artifact storage. Add explicit endpoint values for the
Nexus credential secret, internal service URL parts, public route lookup, and repository names. Allow pipeline-driven
produced-artifact storage to be disabled when HTTPD serving remains active. Do not reconnect Nexus to the modern Image
Builder VM DataSource boot path.

### HTTP Serving and OSTree Publication

The managed HTTPD surface consists of `Deployment/httpd`, `Service/httpd`, `Route/httpd`, `PVC/httpd`, and by default
the Plan 0003-retained `BuildConfig/httpd-ostree` and `ImageStream/httpd-ostree`. The HTTPD pod is not only a serving
URL; it is a writable execution target for publication workflows.

Direct consumers:

- `content-download-upload` locates a pod by `deployment=httpd`, copies or unarchives artifacts into
  `/var/www/html`, reads `Route/httpd`, and writes `serving-storage-url`.
- `oci-build-auto-iso` copies the generated ISO into the HTTPD pod and writes `iso-url` from `Route/httpd`.
- `oci-publish-content` runs inside the chart-managed HTTPD pod, initializes an OSTree repository under
  `/var/www/html/<image>/<tag>`, mirrors content from the stage service, updates the summary, and writes `content-path`
  from `Route/httpd`.
- `oci-stage-content` creates per-image `ImageStream`, `Deployment`, `Service`, and `Route` resources for staged
  content. It depends on the stage namespace and the `oci-rfe-httpd` service account.

Disposition: retain HTTPD as the managed reference for this slice. Plan 0003 external HTTPD image support remains
valid, but an external HTTP URL alone is not a replacement for the current writable pod, PVC, route lookup, and
`ostree` tooling assumptions.

Pulp and ODF were inspected only as adjacent content/storage systems. No direct Plan 0004 publication consumer required
pulling either into this slice, so their disposition remains `migrate-later`.

## Implemented Endpoint Contract

`charts/rfe-pipelines` now exposes a local endpoint contract under `publicationEndpoints`:

```yaml
publicationEndpoints:
  registry:
    mode: managed-reference # managed-reference | external
    imagePath: ""
    publisherSecretName: publisher
    setupSecretName: quay-rfe-setup
  artifactRepository:
    mode: managed-reference # managed-reference | disabled
    disabledResultValue: ""
    nexus:
      credentialsSecretName: nexus-rfe-credentials
      credentialsSecretNamespace: rfe
      serviceName: nexus
      servicePort: 8081
      httpScheme: http
      routeName: nexus
      routeNamespace: rfe
      kickstartRepository: rfe-kickstarts
      autoIsoRepository: rfe-auto-iso
  httpServing:
    mode: managed-reference
    routeName: httpd
    routeNamespace: rfe
    podNamespace: rfe
    podLabelSelector: deployment=httpd
    webRoot: /var/www/html
    stageServiceAccountName: oci-rfe-httpd
```

Implemented behavior:

- default rendering preserves existing Pipeline, Task, Quay, Nexus, HTTPD, and Image Builder VM resource names;
- `publicationEndpoints.registry.mode=external` requires `publicationEndpoints.registry.imagePath`, bypasses Quay
  repository creation, and emits that image path as the existing `image-path` result;
- `publicationEndpoints.registry.publisherSecretName` controls the docker config secret consumed by image push;
- `rfe-oci-build-image` no longer mounts unused `publisher` or `quay-rfe-setup` secrets;
- pipeline-driven Nexus upload consumers receive explicit secret, service, route, and repository values;
- `publicationEndpoints.artifactRepository.mode=disabled` skips Nexus upload while preserving HTTPD serving results;
- HTTPD route, pod namespace, pod selector, web root, stage namespace, and stage service account values are explicit;
- render-time validation rejects unsupported endpoint modes and missing required values.

Focused examples:

- `examples/values/artifact-publication-external-registry.yaml`
- `examples/values/artifact-publication-no-nexus.yaml`

## Verification Results

The implementation was verified primarily with Helm rendering:

```sh
helm dependency build charts/nexus
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe -f examples/values/artifact-publication-external-registry.yaml
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe -f examples/values/artifact-publication-no-nexus.yaml
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe --set publicationEndpoints.registry.mode=external --set publicationEndpoints.registry.imagePath=
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe --set publicationEndpoints.registry.publisherSecretName=
helm template rfe-pipelines charts/rfe-pipelines --namespace rfe --set publicationEndpoints.artifactRepository.mode=external
helm template httpd charts/httpd --namespace rfe
helm template image-builder-vm charts/image-builder-vm --namespace rfe
helm template quay charts/quay --namespace rfe
helm template nexus charts/nexus --namespace rfe
rg -n "quay-rfe-setup|publisher|nexus-rfe-credentials|nexus-upload|openshift-httpd-pod-imi|artifact-repository-storage-url|serving-storage-url|content-path|quay_image_path|quay_image_tag|httpd_route|nexus_route" charts ansible docs examples
git diff --check
```

Negative render checks confirmed clear failures for missing external registry image path, missing registry publisher
secret, and unsupported artifact repository external mode.
