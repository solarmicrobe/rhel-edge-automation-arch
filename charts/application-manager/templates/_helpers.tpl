{{/*
Return the ArgoCD control-plane namespace for Application metadata.
*/}}
{{- define "application-manager.argocdNamespace" -}}
{{- if .chart.namespace }}
{{- printf "%s" .chart.namespace }}
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
{{- printf "%s/%s" "charts" .chart.name }}
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
{{- $chartValues := .chart.values -}}
{{- tpl (toYaml (merge (default dict $chartValues) (default dict (dict "global" $.Values.global)))) .context -}}
{{- end }}
