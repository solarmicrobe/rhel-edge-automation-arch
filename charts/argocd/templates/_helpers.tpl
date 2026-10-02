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
{{- $gitopsMode := include "argocd.gitopsMode" . -}}
{{- $expectedMode := ternary "byo" "managed" (has $deploymentMode (list "byo-cluster-argocd" "byo-rfe-argocd")) -}}
{{- if and (ne $gitopsMode "disabled") (ne $gitopsMode $expectedMode) -}}
{{- fail "components.gitops.mode must agree with deployment.mode" -}}
{{- end -}}
{{- if eq $gitopsMode "byo" -}}
{{- range $field := list "namespace" "project" "server" -}}
{{- if not (dig "gitops" "connection" $field "" (default dict $.Values.components)) -}}
{{- fail (printf "components.gitops.connection.%s is required for BYO GitOps" $field) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $permissionsMode := include "argocd.permissionsMode" . -}}
{{- if not (has $permissionsMode (list "auto" "managed" "external")) -}}
{{- fail "permissions.mode must be one of: auto, managed, external" -}}
{{- end -}}
{{- end -}}

{{- define "argocd.gitopsMode" -}}
{{- $deploymentMode := include "argocd.deploymentMode" . -}}
{{- dig "gitops" "mode" (ternary "byo" "managed" (has $deploymentMode (list "byo-cluster-argocd" "byo-rfe-argocd"))) (default dict .Values.components) -}}
{{- end -}}

{{- define "argocd.renderControlPlane" -}}
{{- if eq (include "argocd.gitopsMode" .) "managed" -}}true{{- else -}}false{{- end -}}
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
{{- if and (eq (include "argocd.gitopsMode" .) "managed") .Values.argocd.clusterAdmin.create (eq $deploymentMode "reference-full-stack") (ne $permissionsMode "external") -}}true{{- else -}}false{{- end -}}
{{- end -}}
