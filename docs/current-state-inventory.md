# Current State Inventory

This inventory records the current `custom` branch implementation before the modernization work begins. It separates observed behavior from modernization implications so later changes can be scoped deliberately.

## Source Baseline

- Governing direction: [ADR 0001](adr/0001-modern-rfe-architecture.md).
- Current deployment entry point: [README.md](../README.md) and [setup/init.sh](../setup/init.sh).
- Primary values example: [examples/values/deployment/application-manager.yaml](../examples/values/deployment/application-manager.yaml).
- Chart root: [charts/](../charts).
- Workflow automation root: [ansible/](../ansible) and [charts/rfe-pipelines/](../charts/rfe-pipelines).

Existing custom changes and previous local workarounds are treated as evidence, not design authority.

## Observed Topology

The current repo has three overlapping layers:

1. Bootstrap and control-plane setup.
2. App-of-apps rendering through ArgoCD.
3. RFE artifact workflows and supporting services.

Those layers are currently coupled through the example values file. The default path assumes a reference cluster where this repo can create namespaces, install operators, install an ArgoCD instance, grant broad access, deploy supporting services, and run RFE workflows.

## Deployment Entry Points

| Area | Current behavior | Modernization concern |
| --- | --- | --- |
| `setup/init.sh` | Creates initial namespaces, installs the OpenShift GitOps operator, waits for the ArgoCD CRD, then installs this repo's `argocd` chart. | ArgoCD installation is not separate from ArgoCD application targeting. BYO cluster ArgoCD and BYO RFE ArgoCD need first-class paths. |
| `charts/bootstrap` | Depends on `namespaces` and `application-manager`; also renders raw resources and AppProjects. | Bootstrap mixes secrets, namespace creation, AppProject management, and application rendering. |
| `examples/values/deployment/application-manager.yaml` | Describes a nested app-of-apps tree for cluster configuration and RFE applications. | The values file encodes reference-cluster assumptions instead of explicit deployment modes and component lifecycle choices. |

## ArgoCD and AppProject

| Area | Current behavior | Modernization concern |
| --- | --- | --- |
| `charts/argocd` | Renders an `ArgoCD` custom resource with OpenShift OAuth, custom health checks, ignore differences, and resource exclusions. | The chart is an install concern, but the rest of the repo also assumes where Applications should be created. These should be separate concerns. |
| `charts/argocd/templates/clusterrolebinding.yaml` | Binds ArgoCD application-controller, applicationset-controller, and server service accounts to `cluster-admin`. | This is incompatible with the modern default. Standalone RFE ArgoCD should use explicit, narrow access grants. |
| `charts/bootstrap/templates/appproject.yaml` | Creates AppProjects with wildcard source repos, wildcard destinations, and wildcard cluster resource whitelist. | AppProject creation belongs in a control-plane integration layer. The modern default should be restrictive and capability-driven. |
| `charts/application-manager/templates/application.yaml` | Renders ArgoCD `Application` resources into a configurable namespace and destination namespace. | This is the right place to target an abstract ArgoCD instance, but the values API currently uses `common.namespace`, `common.destinationNamespace`, and per-chart overrides rather than a clear `argocd.target` model. |

## Application Manager

| Area | Current behavior | Modernization concern |
| --- | --- | --- |
| Application generation | `application-manager` loops over `.Values.charts` and skips a chart only when `disabled` is true. | `disabled` is too coarse for BYO. Components need `managed`, `byo`, and `disabled` lifecycle modes. |
| Source selection | Repo URL and target revision are chosen from per-chart values, common values, or `global.git`. | This can support the modern model, but the API should make repo/ref ownership explicit. |
| Destination selection | Destination namespace is selected from per-chart, common, or release namespace values. | Destination namespace is not the same as ArgoCD control-plane namespace. The values model should make that distinction obvious. |
| Validation | No central validation was observed for component lifecycle, BYO connection details, or workflow dependencies. | Invalid combinations should fail at Helm render time with clear messages. |

## Component Inventory

| Component | Current managed resources | Current coupling | Modernization concern |
| --- | --- | --- | --- |
| Namespaces | `Namespace` resources from `charts/namespaces`. | Example values create platform/component namespaces such as `quay`, `openshift-pipelines`, `openshift-user-workload-monitoring`, and `pulp`. | Namespace creation should follow component lifecycle and ownership, not a single reference install assumption. |
| CatalogSources | `CatalogSource` through `charts/catalogsources`. | Included in the operators app group. | Should be a managed reference-profile component or explicit cluster capability. |
| Operators | Generic `OperatorGroup` and `Subscription` through `charts/operator`. | Used for OpenShift Virtualization, ODF, Nexus, Patch Operator, Pipelines, Pulp, and Quay in the reference values. | BYO components should not install operators. Managed operator installation should be explicit per component. |
| OpenShift Virtualization | `HyperConverged` through `charts/cnv`; operator install is represented separately in the app tree. | Image Builder depends on KubeVirt/CDI resources and, in the modern path, common DataSources. | BYO virtualization should configure DataSource details rather than installing or mutating virtualization. |
| Image Builder VM | `VirtualMachine`, `DataVolume`, service, and Ansible configuration jobs. | VM uses secrets, service account, RHSM credentials, and `ansible-rfe-runner`. | The chart still contains both PVC and DataSource branches. Modern path should be DataSource-only. |
| Nexus | `Nexus` custom resource, setup job, service account, role, role binding, and repository setup values. | Used for artifact repositories and historically for base RHEL media storage. | Nexus should be optional output storage, not required for image-builder VM boot. BYO Nexus needs connection values. |
| Quay | `QuayRegistry`, setup job, role, and role binding. | Pipelines assume a `quay-rfe-setup` secret and Quay repository creation task. | Quay should be a registry target with managed/BYO lifecycle. Pipeline tasks should not assume repo-managed Quay. |
| ODF/NooBaa | `NooBaa`, `BackingStore`, patch resources, and cluster-scoped patch roles. | Pulp uses object bucket and NooBaa patching. | Storage should be managed only in reference mode or configured as BYO connection details. |
| Pulp | `Pulp`, `ObjectBucketClaim`, S3 secret, and patch operator resources. | Depends on ODF/NooBaa behavior and patch operator support. | Needs a clear decision on whether Pulp is core, managed reference infrastructure, or optional artifact integration. |
| HTTPD | Deployment, service, route, PVC, ImageStream, and BuildConfig. | Used to serve staged OSTree content, kickstarts, and ISOs. | The BuildConfig and service ownership should be evaluated against the modern artifact publication model. |
| User management | Groups, bindings, OAuth merge secret/configmap/job, cluster role, and cluster role binding. | Example values create `rfe-admins`, grant `cluster-admin`, and configure HTPasswd identity provider. | This is reference-cluster behavior and should not be part of the modern default. |
| RBAC | Service accounts, namespace roles, role bindings, and cross-namespace roles for ingress and openshift-config access. | Grants pipeline and automation access to RFE resources and selected platform namespaces. | Access grants should move into an explicit access layer with named capabilities. |
| MachineSet | Service account, jobs, roles, role bindings, and cluster roles for infrastructure data. | Appears tied to AWS MachineSet automation. | Likely reference or optional infrastructure automation, not core RFE artifact production. |
| User workload monitoring | ConfigMaps for cluster and user workload monitoring. | Deployed from the cluster-config app group. | Reference/profile concern unless explicitly required by RFE workflows. |

## Workflow Inventory

| Workflow | Current implementation | Produced or consumed artifact | Modernization concern |
| --- | --- | --- | --- |
| Build ansible runner image | `charts/ansible-rfe-runner` renders a `BuildConfig` and `ImageStream`. | Internal `ansible-rfe-runner:latest` image consumed by jobs and pipeline tasks. | This is a remaining build path. It should be inventoried before replacement; it may become a prebuilt image, a Pipeline build, or an external dependency. |
| Build HTTPD OSTree image | `charts/httpd` renders a `BuildConfig`, `ImageStream`, Deployment, PVC, Service, and Route. | HTTPD image with OSTree support for serving content. | This may be obsolete, replaceable by a standard image, or still needed for content serving. Do not translate directly to Pipeline until the need is confirmed. |
| Configure image-builder VM | `charts/image-builder-vm/templates/image-builder-vm-ansible-job.yaml` runs Ansible against VM instances. | Configured Image Builder VM capable of composing artifacts. | Still likely core, but dependencies and credentials need mode-aware validation. |
| Download base RHEL image | `charts/image-builder-vm/templates/redhat-image-downloader-ansible-job.yaml` runs `ansible/playbooks/redhat-image-downloader.yaml`. | Base qcow2 uploaded to Nexus repository `rfe-rhel-media`. | Conflicts with the DataSource-only target. Current custom branch defaults to `datasource`, but this job renders when `dataVolumeSource` is not `pvc`; that should be corrected or removed. |
| Compose RFE OCI image | `rfe-oci-image-pipeline` clones tooling and blueprints, creates a Quay repository, builds via Image Builder, and pushes the result. | OCI image path, tags, Image Builder commit ID. | Core workflow, but assumes Quay setup secret, internal runner image, cluster `git-clone` ClusterTask, and SSH access to the VM. |
| Stage OSTree content | `rfe-oci-stage-pipeline` and Ansible roles create/import ImageStreams and serve staged content over HTTPD. | HTTP URL for staged OSTree content. | Tightly coupled to internal HTTPD and OpenShift ImageStream behavior. Needs review against artifact publication targets. |
| Publish OSTree content | `rfe-oci-publish-content-pipeline` and Ansible roles publish content from a Quay image tag. | Published OSTree repository URL. | Needs BYO registry and serving target support. |
| Build installer image or ISO | `rfe-oci-iso-pipeline`, installer-image tasks, and ISO generator roles. | Installer image build IDs and ISO output URL. | Likely core, but publication should be endpoint-driven rather than HTTPD/Nexus-assumed. |
| Render and upload kickstarts | `rfe-kickstart-pipeline` and `upload-kickstart` task call `ansible/playbooks/upload-kickstart.yaml`. | Nexus artifact URL and serving URL. | Currently requires Nexus credentials and HTTPD upload. BYO artifact targets need explicit connection values. |

## Cross-Cutting Assumptions

| Assumption | Evidence | Impact |
| --- | --- | --- |
| Reference install can own broad cluster behavior. | `setup/init.sh`, `charts/argocd`, wildcard AppProject, user-mgmt cluster-admin binding. | Must be isolated to `reference-full-stack` or explicit capabilities. |
| BYO means disabling selected apps. | README documents `disabled: true`; application-manager only checks `disabled`. | BYO needs lifecycle and connection semantics. |
| Repo-managed Quay exists. | Pipeline tasks and docs use Quay route and `quay-rfe-setup` secret. | BYO registry support requires a connection contract and task changes. |
| Repo-managed Nexus exists. | Kickstart upload and base-image downloader expect Nexus credentials and repositories. | Nexus should be optional artifact storage, not a base-image prerequisite. |
| Internal HTTPD exists for serving artifacts. | HTTPD chart and Ansible roles produce or discover HTTPD routes. | Serving targets should be modeled as managed or BYO artifact endpoints. |
| Pipelines operator and Tekton ClusterTasks exist. | Pipelines use `git-clone` `ClusterTask`; docs require `tkn`. | BYO Pipelines mode needs prerequisites and validation. Managed mode must install what workflows require. |
| Service account access is local and cross-namespace. | `rbac`, `quay`, `user-mgmt`, `machineset`, `odf`, and `pulp` charts render RoleBindings or ClusterRoleBindings. | Access should be explicit, capability-based, and separate from workload deployment. |

## Initial Modernization Slices

These are proposed slices, not implementation approval.

1. Define values API and validation skeleton.
   - Add explicit deployment mode.
   - Add `argocd.target`, `argocd.install`, `argocd.appProject`.
   - Add component lifecycle and connection shape.
   - Add workflow flags with enabled defaults.

2. Separate ArgoCD install, Application targeting, AppProject, and access grants.
   - Keep Application generation, but retarget it through `argocd.target`.
   - Move AppProject and Kubernetes access grants into explicit control-plane/access layers.
   - Remove default cluster-admin behavior from modern modes.

3. Make Image Builder DataSource-only in the modern path.
   - Remove or disable the PVC/Nexus base-image branch from modern rendering.
   - Remove or correct the downloader job path.
   - Add DataSource connection values and render-time validation.

4. Inventory and retire BuildConfigs before migration.
   - Decide whether `ansible-rfe-runner` should be prebuilt, externally supplied, or built by Tekton.
   - Decide whether the HTTPD OSTree image still needs custom build behavior.
   - Migrate only surviving build needs to Pipelines.

5. Refactor artifact publication around endpoints.
   - Model registry, object storage, HTTP, and repository targets as managed or BYO connections.
   - Update workflows to consume endpoints instead of assuming internal Quay, Nexus, or HTTPD.

## Open Questions

- Is Pulp still in scope for the modern path, or only for reference/full-stack deployments?
- Is MachineSet automation still in scope for this fork?
- Should HTTPD remain the default serving mechanism, or should object storage/registry-first publication replace it?
- Should `ansible-rfe-runner` be produced by this repo, pulled from a maintained image, or built by a Pipeline?
- Which exact OpenShift Virtualization DataSource names and namespaces should be supported by default?
