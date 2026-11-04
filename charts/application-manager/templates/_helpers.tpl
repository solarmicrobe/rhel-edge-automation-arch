{{- define "application-manager.validatePlan0007" -}}
{{- $deploymentMode := dig "mode" "managed-rfe-argocd" (default dict .Values.deployment) -}}
{{- $gitops := dig "gitops" dict (default dict .Values.components) -}}
{{- $mode := get $gitops "mode" -}}
{{- range $chartName, $chart := .Values.charts -}}
{{- $ctx := dict "chartName" $chartName "chart" $chart "Values" $.Values -}}
{{- $path := include "application-manager.chartPath" $ctx -}}
{{- $repoChart := include "application-manager.chartRepoPath" $ctx -}}
{{- if and (not $chart.disabled) (not $repoChart) (eq $path "charts/rfe-pipelines") -}}
{{- $effective := mergeOverwrite (deepCopy (default dict $chart.values)) (deepCopy (omit $.Values "charts" "common" "global" "argocd")) -}}
{{- include "application-manager.workflowDependencies" (dict "Values" $effective) -}}
{{- else if and (not $chart.disabled) (not $repoChart) (eq $path "charts/operator")  -}}
{{- $effective := mergeOverwrite (deepCopy (default dict $chart.values)) (deepCopy (omit $.Values "charts" "common" "global" "argocd")) -}}
{{- include "application-manager.operatorValidate" (dict "Values" $effective "operatorName" (dig "operator" "name" "" (default dict $chart.values))) -}}
{{- else if and (not $chart.disabled) (not $repoChart) (eq $path "charts/nexus") -}}
{{- $nexus := mergeOverwrite (deepCopy (dig "components" "nexus" dict (default dict $chart.values))) (deepCopy (dig "nexus" dict (default dict $.Values.components))) -}}
{{- include "application-manager.nexusValidate" (dict "nexus" $nexus "consumer" false) -}}
{{- else if and (not $chart.disabled) (not $repoChart) (eq $path "charts/quay") -}}
{{- $registry := mergeOverwrite (deepCopy (dig "components" "registry" dict (default dict $chart.values))) (deepCopy (dig "registry" dict (default dict $.Values.components))) -}}
{{- include "application-manager.registryValidate" (dict "registry" $registry "consumer" false) -}}
{{- else if and (not $chart.disabled) (not $repoChart) (eq $path "charts/httpd") -}}
{{- $httpd := mergeOverwrite (deepCopy (dig "components" "httpd" dict (default dict $chart.values))) (deepCopy (dig "httpd" dict (default dict $.Values.components))) -}}
{{- include "application-manager.httpdValidate" (dict "httpd" $httpd "consumer" false) -}}
{{- end -}}
{{- end -}}
{{- $byo := has $deploymentMode (list "byo-cluster-argocd" "byo-rfe-argocd") -}}
{{- if and $mode (ne $mode "disabled") (ne $mode (ternary "byo" "managed" $byo)) -}}
{{- fail "components.gitops.mode must agree with deployment.mode" -}}
{{- end -}}
{{- if and (eq $mode "disabled") .Values.charts -}}
{{- fail "components.gitops.mode=disabled cannot target workload Applications" -}}
{{- end -}}
{{- if and $byo (ne $mode "disabled") -}}
{{- range $field := list "namespace" "project" "server" -}}
{{- if not (or (dig "connection" $field "" $gitops) (get $.Values.argocd.target $field)) -}}
{{- fail (printf "components.gitops.connection.%s or argocd.target.%s is required for BYO GitOps" $field $field) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the ArgoCD control-plane namespace for Application metadata.
*/}}
{{- define "application-manager.argocdNamespace" -}}
{{- if .chart.namespace }}
{{- printf "%s" .chart.namespace }}
{{- else if (dig "gitops" "connection" "namespace" "" (default dict .Values.components)) }}
{{- dig "gitops" "connection" "namespace" "" (default dict .Values.components) }}
{{- else if .Values.argocd.target.namespace }}
{{- printf "%s" .Values.argocd.target.namespace }}
{{- else if .Values.common.namespace }}
{{- printf "%s" .Values.common.namespace }}
{{- else }}
{{- printf "%s" .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Return the ArgoCD project for Application specs.
*/}}
{{- define "application-manager.argocdProject" -}}
{{- if .chart.project }}
{{- printf "%s" .chart.project }}
{{- else if (dig "gitops" "connection" "project" "" (default dict .Values.components)) }}
{{- dig "gitops" "connection" "project" "" (default dict .Values.components) }}
{{- else if .Values.argocd.target.project }}
{{- printf "%s" .Values.argocd.target.project }}
{{- else if .Values.argocd.project }}
{{- printf "%s" .Values.argocd.project }}
{{- else }}
{{- printf "%s" .Values.common.project }}
{{- end }}
{{- end }}

{{/*
Return the ArgoCD destination server for Application specs.
*/}}
{{- define "application-manager.argocdServer" -}}
{{- if .chart.server }}
{{- printf "%s" .chart.server }}
{{- else if (dig "gitops" "connection" "server" "" (default dict .Values.components)) }}
{{- dig "gitops" "connection" "server" "" (default dict .Values.components) }}
{{- else if .Values.argocd.target.server }}
{{- printf "%s" .Values.argocd.target.server }}
{{- else if .Values.argocd.server }}
{{- printf "%s" .Values.argocd.server }}
{{- else }}
{{- printf "%s" .Values.common.server }}
{{- end }}
{{- end }}

{{/*
Determines the location of the Helm chart path
*/}}
{{- define "application-manager.chartPath" -}}
{{- if .chart.path }}
{{- printf "%s" .chart.path }}
{{- else if .Values.common.chartPath }}
{{- printf "%s" .Values.common.chartPath }}
{{- else }}
{{- printf "%s/%s" "charts" (default .chartName .chart.name) }}
{{- end }}
{{- end }}

{{/*
Determines the location of the Helm chart repository path
*/}}
{{- define "application-manager.chartRepoPath" -}}
{{- if .chart.chart }}
{{- printf "%s" .chart.chart }}
{{- else if .Values.common.chart }}
{{- printf "%s" .Values.common.chart }}
{{- else }}
{{- print "" }}
{{- end }}
{{- end }}

{{/*
Determines the location of the Helm chart path
*/}}
{{- define "application-manager.destinationNamespace" -}}
{{- if .chart.destinationNamespace }}
{{- printf "%s" .chart.destinationNamespace }}
{{- else if .Values.common.destinationNamespace }}
{{- printf "%s" .Values.common.destinationNamespace }}
{{- else }}
{{- printf "%s" .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Return Git Repository URL
*/}}
{{- define "application-manager.gitURL" -}}
{{- if .Values.global -}}
    {{- if .Values.global.git -}}
        {{- if .Values.global.git.url -}}
            {{- .Values.global.git.url -}}
        {{- else -}}
            {{- .chart.repoURL | default $.Values.common.repoURL -}}
        {{- end -}}
    {{- else -}}
        {{- .chart.repoURL | default $.Values.common.repoURL -}}
    {{- end -}}
{{- else -}}
    {{- .chart.repoURL | default $.Values.common.repoURL -}}
{{- end -}}
{{- end }}

{{/*
Return Git Repository Reference
*/}}
{{- define "application-manager.gitRef" -}}
{{- if .Values.global -}}
    {{- if .Values.global.git -}}
        {{- if .Values.global.git.ref -}}
            {{- .Values.global.git.ref -}}
        {{- else -}}
            {{- .chart.targetRevision | default $.Values.common.targetRevision -}}
        {{- end -}}
    {{- else -}}
        {{- .chart.targetRevision | default $.Values.common.targetRevision -}}
    {{- end -}}
{{- else -}}
    {{- .chart.targetRevision | default $.Values.common.targetRevision -}}
{{- end -}}
{{- end }}

{{/*
Injects Global Values
*/}}
{{- define "application-manager.chartValues" -}}
{{- $chartValues := deepCopy (default dict .chart.values) -}}
{{- $path := include "application-manager.chartPath" . -}}
{{- $repoChart := include "application-manager.chartRepoPath" . -}}
{{- if and (not $repoChart) (has $path (list "charts/quay" "charts/rfe-pipelines" "charts/rbac" "charts/application-manager" "charts/bootstrap")) -}}
{{- if hasKey $.Values "publicationEndpoints" -}}
{{- $_ := set $chartValues "publicationEndpoints" (mergeOverwrite (default dict (get $chartValues "publicationEndpoints")) (deepCopy $.Values.publicationEndpoints)) -}}
{{- end -}}
{{- end -}}
{{- if and (not $repoChart) (eq $path "charts/nexus") -}}
{{- $nexus := dig "nexus" dict (default dict $.Values.components) -}}
{{- if $nexus -}}
{{- $components := default dict (get $chartValues "components") -}}
{{- $_ := set $components "nexus" (mergeOverwrite (default dict (get $components "nexus")) (deepCopy $nexus)) -}}
{{- $_ := set $chartValues "components" $components -}}
{{- end -}}
{{- end -}}
{{- if and (not $repoChart) (eq $path "charts/httpd") -}}
{{- $httpd := dig "httpd" dict (default dict $.Values.components) -}}
{{- if $httpd -}}
{{- $components := default dict (get $chartValues "components") -}}
{{- $_ := set $components "httpd" (mergeOverwrite (default dict (get $components "httpd")) (deepCopy $httpd)) -}}
{{- $_ := set $chartValues "components" $components -}}
{{- end -}}
{{- end -}}
{{- if and (not $repoChart) (has $path (list "charts/application-manager" "charts/bootstrap" "charts/image-builder-vm" "charts/rfe-pipelines" "charts/rbac")) (hasKey $.Values "workflows") -}}
{{- $_ := set $chartValues "workflows" (mergeOverwrite (default dict (get $chartValues "workflows")) (deepCopy $.Values.workflows)) -}}
{{- end -}}
{{- if and (not $repoChart) (has $path (list "charts/image-builder-vm" "charts/rfe-pipelines" "charts/application-manager" "charts/bootstrap")) (hasKey $.Values "rhelTarget") -}}
{{- $_ := set $chartValues "rhelTarget" (mergeOverwrite (default dict (get $chartValues "rhelTarget")) (deepCopy $.Values.rhelTarget)) -}}
{{- end -}}
{{- $operatorComponent := get (dict "openshift-gitops-operator" "gitops" "kubevirt-hyperconverged" "virtualization" "odf-operator" "odf" "openshift-pipelines-operator-rh" "pipelines" "quay-operator" "registry" "nexus-operator" "nexus") (dig "operator" "name" "" $chartValues) -}}
{{- if and (not $repoChart) (eq $path "charts/operator") $operatorComponent -}}
{{- $component := dig $operatorComponent dict (default dict $.Values.components) -}}
{{- if $component -}}
{{- $components := default dict (get $chartValues "components") -}}
{{- $_ := set $components $operatorComponent (mergeOverwrite (default dict (get $components $operatorComponent)) (deepCopy $component)) -}}
{{- $_ := set $chartValues "components" $components -}}
{{- end -}}
{{- end -}}
{{- if and (not $repoChart) (has $path (list "charts/application-manager" "charts/bootstrap" "charts/argocd" "charts/argocd-integration" "charts/odf" "charts/cnv" "charts/image-builder-vm" "charts/rfe-pipelines" "charts/rbac" "charts/quay")) -}}
{{- range $key := list "deployment" "permissions" "components" -}}
{{- if hasKey $.Values $key -}}
{{- $_ := set $chartValues $key (mergeOverwrite (default dict (get $chartValues $key)) (deepCopy (get $.Values $key))) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and (not $repoChart) (eq $path "charts/bootstrap") -}}
{{- range $child := list "application-manager" "argocdIntegration" -}}
{{- $childValues := default dict (get $chartValues $child) -}}
{{- range $key := list "deployment" "permissions" "components" -}}
{{- if hasKey $.Values $key -}}
{{- $_ := set $childValues $key (mergeOverwrite (default dict (get $childValues $key)) (deepCopy (get $.Values $key))) -}}
{{- end -}}
{{- end -}}
{{- if and (eq $child "application-manager") (hasKey $.Values "workflows") -}}
{{- $_ := set $childValues "workflows" (mergeOverwrite (default dict (get $childValues "workflows")) (deepCopy $.Values.workflows)) -}}
{{- end -}}
{{- $_ := set $chartValues $child $childValues -}}
{{- end -}}
{{- end -}}
{{- tpl (toYaml (merge (default dict $chartValues) (default dict (dict "global" $.Values.global)))) .context -}}
{{- end }}

{{- define "application-manager.registryValidate" -}}
{{- $registry := .registry -}}
{{- if and (hasKey $registry "mode") (not (kindIs "string" (get $registry "mode"))) -}}{{- fail "components.registry.mode must be a lifecycle string" -}}{{- end -}}
{{- if not (has (dig "mode" "managed" $registry) (list "managed" "byo" "disabled")) -}}
{{- fail "components.registry.mode must be one of: managed, byo, disabled" -}}
{{- end -}}
{{- if and (hasKey $registry "connection") (not (kindIs "map" (get $registry "connection"))) -}}{{- fail "components.registry.connection must be an object" -}}{{- end -}}
{{- $connection := default dict (get $registry "connection") -}}
{{- if hasKey $connection "imagePath" -}}
{{- if not (kindIs "string" (get $connection "imagePath")) -}}{{- fail "components.registry.connection.imagePath must be a registry repository path" -}}{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9][A-Za-z0-9.:-]*/[A-Za-z0-9_./-]+$" (get $connection "imagePath")) -}}{{- fail "components.registry.connection.imagePath must be a registry repository path" -}}{{- end -}}
{{- end -}}
{{- range $field := list "publisherSecretName" "pullSecretName" -}}
{{- if hasKey $connection $field -}}
{{- $secret := get $connection $field -}}
{{- if not (kindIs "string" $secret) -}}{{- fail (printf "components.registry.connection.%s must be a Kubernetes DNS name" $field) -}}{{- end -}}
{{- if or (gt (len $secret) 253) (not (regexMatch "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$" $secret)) -}}{{- fail (printf "components.registry.connection.%s must be a Kubernetes DNS name" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if and .consumer (eq (get $registry "mode") "byo") -}}
{{- range $field := list "imagePath" "publisherSecretName" -}}
{{- if empty (dig "connection" $field "" $registry) -}}
{{- fail (printf "components.registry.connection.%s is required for BYO registry" $field) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- define "application-manager.nexusValidate" -}}
{{- $nexus := .nexus -}}
{{- $mode := dig "mode" "managed" $nexus -}}
{{- if not (has $mode (list "managed" "byo" "disabled")) -}}{{- fail "components.nexus.mode must be one of: managed, byo, disabled" -}}{{- end -}}
{{- if and (hasKey $nexus "connection") (not (kindIs "map" (get $nexus "connection"))) -}}{{- fail "components.nexus.connection must be an object" -}}{{- end -}}
{{- $connection := default dict (get $nexus "connection") -}}
{{- range $field, $value := $connection -}}
{{- if eq $field "servicePort" -}}
{{- if or (not (regexMatch "^[0-9]+$" (toString $value))) (lt (int $value) 1) (gt (int $value) 65535) -}}{{- fail "components.nexus.connection.servicePort must be a valid port" -}}{{- end -}}
{{- else if eq $field "httpScheme" -}}
{{- if not (has $value (list "http" "https")) -}}{{- fail "components.nexus.connection.httpScheme must be http or https" -}}{{- end -}}
{{- else -}}
{{- if not (kindIs "string" $value) -}}{{- fail (printf "components.nexus.connection.%s must be a DNS name" $field) -}}{{- end -}}
{{- if or (gt (len $value) 253) (not (regexMatch "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$" $value)) -}}{{- fail (printf "components.nexus.connection.%s must be a DNS name" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if and (hasKey $nexus "artifacts") (not (kindIs "map" $nexus.artifacts)) -}}{{- fail "components.nexus.artifacts must be an object" -}}{{- end -}}
{{- $artifacts := default dict (get $nexus "artifacts") -}}
{{- if and (hasKey $artifacts "upload") (not (kindIs "bool" (get $artifacts "upload"))) -}}{{- fail "components.nexus.artifacts.upload must be boolean" -}}{{- end -}}
{{- if and .consumer (eq $mode "byo") -}}
{{- $required := list "credentialsSecretName" "credentialsSecretNamespace" "serviceName" "servicePort" "httpScheme" -}}
{{- if .kickstart -}}{{- $required = concat $required (list "routeName" "routeNamespace" "kickstartRepository") -}}{{- end -}}
{{- if .iso -}}{{- $required = append $required "autoIsoRepository" -}}{{- end -}}
{{- range $field := $required -}}
{{- if empty (get $connection $field) -}}{{- fail (printf "components.nexus.connection.%s is required for BYO Nexus consumers" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- define "application-manager.workflow" -}}
{{- $workflows := dict -}}
{{- if hasKey .Values "workflows" -}}
{{- if not (kindIs "map" .Values.workflows) -}}{{- fail "workflows must be an object" -}}{{- end -}}
{{- $workflows = .Values.workflows -}}
{{- end -}}
{{- $settings := dig .name dict $workflows -}}
{{- if not (kindIs "map" $settings) -}}{{- fail (printf "workflows.%s must be an object" .name) -}}{{- end -}}
{{- if and (hasKey $settings "enabled") (not (kindIs "bool" (get $settings "enabled"))) -}}{{- fail (printf "workflows.%s.enabled must be boolean" .name) -}}{{- end -}}
{{- if hasKey $settings "enabled" -}}{{ get $settings "enabled" }}{{- else -}}true{{- end -}}
{{- end -}}
{{- define "application-manager.workflowDependencies" -}}
{{- $compose := eq (include "application-manager.workflow" (dict "Values" .Values "name" "composeImage")) "true" -}}
{{- $stage := eq (include "application-manager.workflow" (dict "Values" .Values "name" "stageImage")) "true" -}}
{{- $ostree := eq (include "application-manager.workflow" (dict "Values" .Values "name" "publishOstree")) "true" -}}
{{- $iso := eq (include "application-manager.workflow" (dict "Values" .Values "name" "publishIso")) "true" -}}
{{- $kickstart := eq (include "application-manager.workflow" (dict "Values" .Values "name" "serveKickstarts")) "true" -}}
{{- include "application-manager.pipelinesValidate" (dict "Values" .Values "consumer" (or $compose $stage $ostree $iso $kickstart)) -}}
{{- $target := mergeOverwrite ("{\"major\":8,\"architecture\":\"x86_64\",\"imageBuilder\":{\"enabled\":true,\"ostreeRef\":\"rhel/8/x86_64/edge\",\"composeTypes\":{\"container\":\"rhel-edge-container\",\"installer\":\"rhel-edge-installer\"},\"repositories\":[\"rhel-8-for-x86_64-baseos-rpms\",\"rhel-8-for-x86_64-appstream-rpms\"]},\"imageMode\":{\"enabled\":false}}" | fromJson) (deepCopy (default dict .Values.rhelTarget)) -}}
{{- include "application-manager.rhelValidate" (dict "Values" (dict "rhelTarget" $target) "compose" $compose "iso" $iso "ostree" $ostree) -}}
{{- $components := default dict .Values.components -}}
{{- $endpoints := default dict .Values.publicationEndpoints -}}
{{- $httpd := dig "httpd" dict $components -}}
{{- include "application-manager.httpdValidate" (dict "httpd" $httpd "endpoint" (dig "httpServing" dict $endpoints) "consumer" (or $stage $ostree $iso $kickstart) "stage" $stage "content" (or $ostree $iso $kickstart)) -}}
{{- $registry := dig "registry" dict $components -}}
{{- include "application-manager.registryValidate" (dict "registry" $registry "consumer" $compose) -}}
{{- if and (or $compose $stage) (eq (get $registry "mode") "disabled") -}}{{- fail "enabled image workflows require components.registry" -}}{{- end -}}
{{- $push := ne (get $registry "mode") "byo" -}}
{{- $image := dig "registry" "image" dict $endpoints -}}
{{- if hasKey $image "push" -}}{{- if not (kindIs "bool" $image.push) -}}{{- fail "publicationEndpoints.registry.image.push must be boolean" -}}{{- end -}}{{- $push = $image.push -}}{{- end -}}
{{- if and $compose (not $push) -}}{{- fail "composeImage requires publicationEndpoints.registry.image.push=true" -}}{{- end -}}
{{- if and (or $compose $stage $ostree $iso $kickstart) (eq (dig "pipelines" "mode" "managed" $components) "disabled") -}}{{- fail "enabled workflows require components.pipelines" -}}{{- end -}}
{{- if and (or $compose $iso) (eq (dig "imageBuilderVM" "mode" "managed" $components) "disabled") -}}{{- fail "composeImage and publishIso require components.imageBuilderVM" -}}{{- end -}}
{{- include "application-manager.vmLifecycleValidate" (dict "Values" .Values "consumer" (or $compose $iso)) -}}
{{- $nexus := dig "nexus" dict $components -}}
{{- include "application-manager.nexusValidate" (dict "nexus" $nexus "consumer" false) -}}
{{- $upload := eq (dig "mode" "managed" $nexus) "managed" -}}
{{- if hasKey (default dict $nexus.artifacts) "upload" -}}{{- $upload = $nexus.artifacts.upload -}}{{- end -}}
{{- include "application-manager.nexusValidate" (dict "nexus" $nexus "consumer" (and $upload (or $iso $kickstart)) "iso" $iso "kickstart" $kickstart) -}}
{{- end -}}
{{- define "application-manager.pipelinesValidate" -}}
{{- $component := dig "pipelines" dict (default dict .Values.components) -}}
{{- $mode := dig "mode" "managed" $component -}}
{{- if not (has $mode (list "managed" "byo" "disabled")) -}}{{- fail "components.pipelines.mode must be one of: managed, byo, disabled" -}}{{- end -}}
{{- if and (hasKey $component "connection") (not (kindIs "map" $component.connection)) -}}{{- fail "components.imageBuilderVM.connection must be an object" -}}{{- end -}}
{{- $connection := default dict $component.connection -}}
{{- if hasKey $connection "namespace" -}}
{{- $namespace := $connection.namespace -}}
{{- if not (kindIs "string" $namespace) -}}{{- fail "components.pipelines.connection.namespace must be a Kubernetes namespace string" -}}{{- end -}}
{{- if or (gt (len $namespace) 63) (not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" $namespace)) -}}{{- fail "components.pipelines.connection.namespace must be a nonempty Kubernetes namespace" -}}{{- end -}}
{{- end -}}
{{- if and .consumer (eq $mode "byo") (empty (get $connection "namespace")) -}}{{- fail "components.pipelines.connection.namespace is required for BYO Pipelines" -}}{{- end -}}
{{- end -}}
{{- define "application-manager.vmLifecycleValidate" -}}
{{- $component := dig "imageBuilderVM" dict (default dict .Values.components) -}}
{{- if not (has (dig "mode" "managed" $component) (list "managed" "byo" "disabled")) -}}{{- fail "components.imageBuilderVM.mode must be one of: managed, byo, disabled" -}}{{- end -}}
{{- if and (hasKey $component "connection") (not (kindIs "map" $component.connection)) -}}{{- fail "components.imageBuilderVM.connection must be an object" -}}{{- end -}}
{{- $connection := default dict $component.connection -}}
{{- range $field := list "host" "sshSecretName" -}}
{{- if and $.consumer (eq (get $component "mode") "byo") (empty (get $connection $field)) -}}{{- fail (printf "components.imageBuilderVM.connection.%s is required for BYO Image Builder VM" $field) -}}{{- end -}}
{{- if hasKey $connection $field -}}
{{- $value := get $connection $field -}}
{{- if not (kindIs "string" $value) -}}{{- fail (printf "components.imageBuilderVM.connection.%s must be a DNS name" $field) -}}{{- end -}}
{{- $pattern := "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$" -}}
{{- if eq $field "host" -}}{{- $pattern = "^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$" -}}{{- end -}}
{{- if or (gt (len $value) 253) (not (regexMatch $pattern $value)) -}}{{- fail (printf "components.imageBuilderVM.connection.%s must be a DNS name" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- define "application-manager.rhelValidate" -}}
{{- $compose := .compose -}}{{- $iso := .iso -}}{{- $ostree := .ostree -}}
{{- $target := .Values.rhelTarget | default dict -}}
{{- $targetMajor := toString ($target.major | default "8") -}}
{{- $architecture := $target.architecture | default "" -}}
{{- $imageBuilder := $target.imageBuilder | default dict -}}
{{- $composeTypes := $imageBuilder.composeTypes | default dict -}}
{{- $imageMode := $target.imageMode | default dict -}}
{{- if or $compose $iso -}}
{{- if eq $targetMajor "10" -}}
{{- fail "rhelTarget.major=10 is not supported by the current Image Builder rpm-ostree workflows; RHEL 10 requires a future image-mode/bootc implementation" -}}
{{- end -}}
{{- if not (has $targetMajor (list "8" "9")) -}}
{{- fail "rhelTarget.major must be one of: 8, 9" -}}
{{- end -}}
{{- if empty $architecture -}}
{{- fail "rhelTarget.architecture is required" -}}
{{- end -}}
{{- if $imageMode.enabled -}}
{{- fail "rhelTarget.imageMode.enabled=true is unsupported until a future bootc/image-mode workflow is implemented" -}}
{{- end -}}
{{- if and (hasKey $imageBuilder "enabled") (not $imageBuilder.enabled) -}}
{{- fail "rhelTarget.imageBuilder.enabled=false is unsupported while the current pipelines use Image Builder rpm-ostree workflows" -}}
{{- end -}}
{{- end -}}
{{- if and (or $iso $ostree) (empty $imageBuilder.ostreeRef) -}}
{{- fail "rhelTarget.imageBuilder.ostreeRef is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if and (or $iso $ostree) (not (contains (printf "rhel/%s/%s/" $targetMajor $architecture) $imageBuilder.ostreeRef)) -}}
{{- fail (printf "rhelTarget.imageBuilder.ostreeRef must match rhelTarget.major=%s and rhelTarget.architecture=%s" $targetMajor $architecture) -}}
{{- end -}}
{{- if and $compose (empty $composeTypes.container) -}}
{{- fail "rhelTarget.imageBuilder.composeTypes.container is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if and $iso (empty $composeTypes.installer) -}}
{{- fail "rhelTarget.imageBuilder.composeTypes.installer is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if or $compose $iso -}}
{{- if eq (len ($imageBuilder.repositories | default list)) 0 -}}
{{- fail "rhelTarget.imageBuilder.repositories must include at least one RHSM repository when Image Builder workflows are enabled" -}}
{{- end -}}
{{- range $repo := ($imageBuilder.repositories | default list) -}}
{{- if and (ne $targetMajor "8") (contains "rhel-8-" $repo) -}}
{{- fail (printf "rhelTarget.imageBuilder.repositories contains RHEL 8 repository %q but rhelTarget.major=%s" $repo $targetMajor) -}}
{{- end -}}
{{- if and (ne $targetMajor "9") (contains "rhel-9-" $repo) -}}
{{- fail (printf "rhelTarget.imageBuilder.repositories contains RHEL 9 repository %q but rhelTarget.major=%s" $repo $targetMajor) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "application-manager.operatorValidate" -}}
{{- $name := get (dict "openshift-gitops-operator" "gitops" "kubevirt-hyperconverged" "virtualization" "odf-operator" "odf" "openshift-pipelines-operator-rh" "pipelines" "quay-operator" "registry" "nexus-operator" "nexus") .operatorName -}}
{{- if $name -}}
{{- $component := dig $name dict (default dict .Values.components) -}}
{{- if not (has (dig "mode" "managed" $component) (list "managed" "byo" "disabled")) -}}{{- fail (printf "components.%s.mode must be one of: managed, byo, disabled" $name) -}}{{- end -}}
{{- if eq $name "pipelines" -}}{{- include "application-manager.pipelinesValidate" (dict "Values" .Values "consumer" true) -}}{{- end -}}
{{- end -}}
{{- end -}}
