{{- define "argocd.deploymentMode" -}}
{{- $deployment := default dict .Values.deployment -}}
{{- default "managed-rfe-argocd" (get $deployment "mode") -}}
{{- end -}}

{{- define "argocd.permissionsMode" -}}
{{- $permissions := default dict .Values.permissions -}}
{{- default "auto" (get $permissions "mode") -}}
{{- end -}}

{{- define "argocd.validatePlan0007" -}}
{{- $deploymentMode := include "argocd.deploymentMode" . -}}
{{- if not (has $deploymentMode (list "managed-rfe-argocd" "byo-cluster-argocd" "byo-rfe-argocd" "reference-full-stack")) -}}
{{- fail "deployment.mode must be one of: managed-rfe-argocd, byo-cluster-argocd, byo-rfe-argocd, reference-full-stack" -}}
{{- end -}}
{{- $permissionsMode := include "argocd.permissionsMode" . -}}
{{- if not (has $permissionsMode (list "auto" "managed" "external")) -}}
{{- fail "permissions.mode must be one of: auto, managed, external" -}}
{{- end -}}
{{- end -}}

{{- define "argocd.renderControlPlane" -}}
{{- $deploymentMode := include "argocd.deploymentMode" . -}}
{{- if has $deploymentMode (list "managed-rfe-argocd" "reference-full-stack") -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "argocd.resolvedPermissionsMode" -}}
{{- $permissionsMode := include "argocd.permissionsMode" . -}}
{{- if ne $permissionsMode "auto" -}}
{{- $permissionsMode -}}
{{- else -}}
{{- $deploymentMode := include "argocd.deploymentMode" . -}}
{{- if has $deploymentMode (list "byo-cluster-argocd" "byo-rfe-argocd") -}}external{{- else -}}managed{{- end -}}
{{- end -}}
{{- end -}}

{{- define "argocd.renderLegacyClusterAdmin" -}}
{{- $deploymentMode := include "argocd.deploymentMode" . -}}
{{- $permissionsMode := include "argocd.resolvedPermissionsMode" . -}}
{{- if and .Values.argocd.clusterAdmin.create (eq $deploymentMode "reference-full-stack") (ne $permissionsMode "external") -}}true{{- else -}}false{{- end -}}
{{- end -}}
