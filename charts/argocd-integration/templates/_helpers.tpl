{{/*
Expand the name of the chart.
*/}}
{{- define "argocd-integration.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "argocd-integration.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "argocd-integration.labels" -}}
{{ include "common.labels.labels" . }}
{{- end }}

{{/*
Target ArgoCD namespace.
*/}}
{{- define "argocd-integration.targetNamespace" -}}
{{- .Values.argocd.target.namespace | default .Release.Namespace -}}
{{- end }}

{{/*
AppProject name.
*/}}
{{- define "argocd-integration.appProjectName" -}}
{{- .Values.argocd.appProject.name | default .Values.argocd.target.project -}}
{{- end }}

{{/*
Namespace grant resource base name.
*/}}
{{- define "argocd-integration.namespaceGrantName" -}}
{{- .Values.argocd.access.namespaceGrants.name | default (printf "%s-namespace-access" (include "argocd-integration.appProjectName" .)) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Cluster capability grant resource base name.
*/}}
{{- define "argocd-integration.clusterCapabilityName" -}}
{{- .Values.argocd.access.clusterCapabilities.name | default (printf "%s-cluster-capabilities" (include "argocd-integration.appProjectName" .)) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Controller namespace used by access bindings.
*/}}
{{- define "argocd-integration.namespaceGrantControllerNamespace" -}}
{{- .Values.argocd.access.namespaceGrants.controllerNamespace | default .Values.argocd.target.namespace -}}
{{- end }}

{{/*
Controller namespace used by cluster capability bindings.
*/}}
{{- define "argocd-integration.clusterCapabilityControllerNamespace" -}}
{{- .Values.argocd.access.clusterCapabilities.controllerNamespace | default .Values.argocd.target.namespace -}}
{{- end }}
