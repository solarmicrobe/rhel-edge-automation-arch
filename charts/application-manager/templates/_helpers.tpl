{{- define "application-manager.validatePlan0007" -}}
{{- $deploymentMode := dig "mode" "managed-rfe-argocd" (default dict .Values.deployment) -}}
{{- $gitops := dig "gitops" dict (default dict .Values.components) -}}
{{- $mode := get $gitops "mode" -}}
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
{{- if and (not $repoChart) (has $path (list "charts/application-manager" "charts/bootstrap" "charts/argocd" "charts/argocd-integration" "charts/odf" "charts/cnv" "charts/image-builder-vm" "charts/rfe-pipelines")) -}}
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
