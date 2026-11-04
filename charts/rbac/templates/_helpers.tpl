{{- define "rbac.workflow" -}}
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
{{- define "rbac.anyWorkflow" -}}
{{- $active := false -}}
{{- range $name := list "composeImage" "stageImage" "publishOstree" "publishIso" "serveKickstarts" -}}
{{- if eq (include "rbac.workflow" (dict "Values" $.Values "name" $name)) "true" -}}{{- $active = true -}}{{- end -}}
{{- end -}}
{{- $active -}}
{{- end -}}
{{- define "rbac.owned" -}}
{{- $deployment := dig "mode" "managed-rfe-argocd" (default dict .Values.deployment) -}}
{{- if not (has $deployment (list "managed-rfe-argocd" "byo-cluster-argocd" "byo-rfe-argocd" "reference-full-stack")) -}}{{- fail "deployment.mode must be a supported deployment mode" -}}{{- end -}}
{{- $mode := dig "mode" "auto" (default dict .Values.permissions) -}}
{{- if not (has $mode (list "auto" "managed" "external")) -}}{{- fail "permissions.mode must be auto, managed or external" -}}{{- end -}}
{{- if eq $mode "auto" -}}{{- $mode = ternary "external" "managed" (has (dig "mode" "managed-rfe-argocd" (default dict .Values.deployment)) (list "byo-cluster-argocd" "byo-rfe-argocd")) -}}{{- end -}}
{{- and (eq $mode "managed") (eq (include "rbac.anyWorkflow" .) "true") -}}
{{- end -}}
{{- define "rbac.stageConnection" -}}
{{- $httpd := dig "httpd" dict (default dict .Values.components) -}}
{{- if eq (get $httpd "mode") "byo" -}}{{- toJson (default dict $httpd.connection) -}}{{- else -}}{{- toJson (dig "httpServing" dict (default dict .Values.publicationEndpoints)) -}}{{- end -}}
{{- end -}}
{{- define "rbac.stageNamespace" -}}
{{- $connection := include "rbac.stageConnection" . | fromJson -}}
{{- if and (get $connection "podNamespace") (or (eq (dig "httpd" "mode" "managed" (default dict .Values.components)) "byo") (ne $connection.podNamespace "rfe")) -}}{{ $connection.podNamespace }}{{- else -}}{{ template "common.names.namespace" . }}{{- end -}}
{{- end -}}
{{- define "rbac.stageName" -}}
{{- $connection := include "rbac.stageConnection" . | fromJson -}}
{{- get $connection "stageServiceAccountName" | default "oci-rfe-httpd" -}}
{{- end -}}
{{- define "rbac.pullSecret" -}}
{{- $registry := dig "registry" dict (default dict .Values.components) -}}
{{- $secret := dig "connection" "pullSecretName" "" $registry -}}
{{- if and (not $secret) (ne (get $registry "mode") "byo") -}}{{- $secret = dig "registry" "publisherSecretName" "publisher" (default dict .Values.publicationEndpoints) -}}{{- end -}}
{{- if and $secret (or (not (kindIs "string" $secret)) (gt (len $secret) 253) (not (regexMatch "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$" $secret))) -}}{{- fail "registry pull secret must be a Kubernetes DNS name" -}}{{- end -}}
{{- $secret -}}
{{- end -}}

{{- define "rbac.reference" -}}
{{- eq (dig "mode" "managed-rfe-argocd" (default dict .Values.deployment)) "reference-full-stack" -}}
{{- end -}}
