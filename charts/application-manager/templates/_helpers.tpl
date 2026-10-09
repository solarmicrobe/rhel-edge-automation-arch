{{- define "application-manager.validatePlan0007" -}}
{{- $deploymentMode := dig "mode" "managed-rfe-argocd" (default dict .Values.deployment) -}}
{{- $gitops := dig "gitops" dict (default dict .Values.components) -}}
{{- $mode := get $gitops "mode" -}}
{{- range $chartName, $chart := .Values.charts -}}
{{- $ctx := dict "chartName" $chartName "chart" $chart "Values" $.Values -}}
{{- $path := include "application-manager.chartPath" $ctx -}}
{{- $repoChart := include "application-manager.chartRepoPath" $ctx -}}
{{- if and (not $chart.disabled) (not $repoChart) (has $path (list "charts/nexus" "charts/rfe-pipelines")) -}}
{{- $nexus := mergeOverwrite (deepCopy (dig "components" "nexus" dict (default dict $chart.values))) (deepCopy (dig "nexus" dict (default dict $.Values.components))) -}}
{{- include "application-manager.nexusValidate" (dict "nexus" $nexus "consumer" (eq $path "charts/rfe-pipelines")) -}}
{{- end -}}
{{- if and (not $chart.disabled) (not $repoChart) (has $path (list "charts/quay" "charts/rfe-pipelines")) -}}
{{- $registry := mergeOverwrite (deepCopy (dig "components" "registry" dict (default dict $chart.values))) (deepCopy (dig "registry" dict (default dict $.Values.components))) -}}
{{- include "application-manager.registryValidate" (dict "registry" $registry) -}}
{{- if eq $path "charts/rfe-pipelines" -}}
{{- if eq (get $registry "mode") "disabled" -}}{{- fail "components.registry.mode=disabled cannot support mandatory image publication pipelines" -}}{{- end -}}
{{- $endpoints := mergeOverwrite (deepCopy (dig "publicationEndpoints" dict (default dict $chart.values))) (deepCopy (default dict $.Values.publicationEndpoints)) -}}
{{- $image := dig "registry" "image" dict $endpoints -}}
{{- $push := ne (get $registry "mode") "byo" -}}
{{- if hasKey $image "push" -}}{{- if not (kindIs "bool" (get $image "push")) -}}{{- fail "publicationEndpoints.registry.image.push must be boolean" -}}{{- end -}}{{- $push = get $image "push" -}}{{- end -}}
{{- if not $push -}}{{- fail "publicationEndpoints.registry.image.push=false cannot support mandatory image publication pipelines until a future workflow slice" -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if and (not $chart.disabled) (not $repoChart) (or (eq $path "charts/rfe-pipelines") (and (eq $path "charts/operator") (eq (dig "operator" "name" "" (default dict $chart.values)) "openshift-pipelines-operator-rh"))) -}}
{{- $pipelines := mergeOverwrite (deepCopy (dig "components" "pipelines" dict (default dict $chart.values))) (deepCopy (dig "pipelines" dict (default dict $.Values.components))) -}}
{{- if hasKey $pipelines "mode" -}}
{{- if not (has (get $pipelines "mode") (list "managed" "byo" "disabled")) -}}
{{- fail "components.pipelines.mode must be one of: managed, byo, disabled" -}}
{{- end -}}
{{- end -}}
{{- $connection := default dict (get $pipelines "connection") -}}
{{- if hasKey $connection "namespace" -}}
{{- $namespace := get $connection "namespace" -}}
{{- if not (kindIs "string" $namespace) -}}
{{- fail "components.pipelines.connection.namespace must be a Kubernetes namespace string" -}}
{{- end -}}
{{- if or (gt (len $namespace) 63) (not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" $namespace)) -}}
{{- fail "components.pipelines.connection.namespace must be a nonempty Kubernetes namespace" -}}
{{- end -}}
{{- end -}}
{{- if and (eq (get $pipelines "mode") "byo") (empty (dig "connection" "namespace" "" $pipelines)) -}}
{{- fail "components.pipelines.connection.namespace is required for BYO Pipelines" -}}
{{- end -}}
{{- if and (eq $path "charts/rfe-pipelines") (eq (get $pipelines "mode") "disabled") -}}
{{- fail "components.pipelines.mode=disabled cannot support mandatory pipelines" -}}
{{- end -}}
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
{{- if and (not $repoChart) (has $path (list "charts/quay" "charts/rfe-pipelines")) -}}
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
{{- $pipelinesOperator := and (not $repoChart) (eq $path "charts/operator") (eq (dig "operator" "name" "" $chartValues) "openshift-pipelines-operator-rh") -}}
{{- if $pipelinesOperator -}}
{{- $pipelines := dig "pipelines" dict (default dict $.Values.components) -}}
{{- if $pipelines -}}
{{- $components := default dict (get $chartValues "components") -}}
{{- $_ := set $components "pipelines" (mergeOverwrite (default dict (get $components "pipelines")) (deepCopy $pipelines)) -}}
{{- $_ := set $chartValues "components" $components -}}
{{- end -}}
{{- end -}}
{{- if and (not $repoChart) (has $path (list "charts/application-manager" "charts/bootstrap" "charts/argocd" "charts/argocd-integration" "charts/odf" "charts/cnv" "charts/image-builder-vm" "charts/rfe-pipelines" "charts/quay")) -}}
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
{{- $_ := set $chartValues $child $childValues -}}
{{- end -}}
{{- end -}}
{{- tpl (toYaml (merge (default dict $chartValues) (default dict (dict "global" $.Values.global)))) .context -}}
{{- end }}

{{- define "application-manager.registryValidate" -}}
{{- $registry := .registry -}}
{{- if and (hasKey $registry "mode") (not (kindIs "string" (get $registry "mode"))) -}}{{- fail "components.registry.mode must be a lifecycle string" -}}{{- end -}}
{{- if not (has (get $registry "mode" | default "managed") (list "managed" "byo" "disabled")) -}}
{{- fail "components.registry.mode must be one of: managed, byo, disabled" -}}
{{- end -}}
{{- $connection := default dict (get $registry "connection") -}}
{{- if hasKey $connection "imagePath" -}}
{{- if not (kindIs "string" (get $connection "imagePath")) -}}{{- fail "components.registry.connection.imagePath must be a registry repository path" -}}{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9][A-Za-z0-9.:-]*/[A-Za-z0-9_./-]+$" (get $connection "imagePath")) -}}{{- fail "components.registry.connection.imagePath must be a registry repository path" -}}{{- end -}}
{{- end -}}
{{- if hasKey $connection "publisherSecretName" -}}
{{- $secret := get $connection "publisherSecretName" -}}
{{- if not (kindIs "string" $secret) -}}{{- fail "components.registry.connection.publisherSecretName must be a Kubernetes DNS name" -}}{{- end -}}
{{- if or (gt (len $secret) 253) (not (regexMatch "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$" $secret)) -}}{{- fail "components.registry.connection.publisherSecretName must be a Kubernetes DNS name" -}}{{- end -}}
{{- end -}}
{{- if eq (get $registry "mode") "byo" -}}
{{- range $field := list "imagePath" "publisherSecretName" -}}
{{- if empty (dig "connection" $field "" $registry) -}}
{{- fail (printf "components.registry.connection.%s is required for BYO registry" $field) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- define "application-manager.nexusValidate" -}}
{{- $nexus := .nexus -}}
{{- $mode := get $nexus "mode" | default "managed" -}}
{{- if not (has $mode (list "managed" "byo" "disabled")) -}}{{- fail "components.nexus.mode must be one of: managed, byo, disabled" -}}{{- end -}}
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
{{- $artifacts := default dict (get $nexus "artifacts") -}}
{{- if and (hasKey $artifacts "upload") (not (kindIs "bool" (get $artifacts "upload"))) -}}{{- fail "components.nexus.artifacts.upload must be boolean" -}}{{- end -}}
{{- if and .consumer (eq $mode "byo") -}}
{{- range $field := list "credentialsSecretName" "credentialsSecretNamespace" "serviceName" "servicePort" "httpScheme" "routeName" "routeNamespace" "kickstartRepository" "autoIsoRepository" -}}
{{- if empty (get $connection $field) -}}{{- fail (printf "components.nexus.connection.%s is required for BYO Nexus consumers" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
