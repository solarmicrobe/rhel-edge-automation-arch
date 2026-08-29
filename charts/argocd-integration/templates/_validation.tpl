{{/*
Validate AppProject input when AppProject creation is enabled.
*/}}
{{- define "argocd-integration.validateAppProject" -}}
{{- if .Values.argocd.appProject.create -}}
{{- if not .Values.argocd.target.namespace -}}
{{- fail "argocd.target.namespace is required when argocd.appProject.create=true" -}}
{{- end -}}
{{- if not (include "argocd-integration.appProjectName" .) -}}
{{- fail "argocd.target.project or argocd.appProject.name is required when argocd.appProject.create=true" -}}
{{- end -}}
{{- if not .Values.argocd.appProject.sourceRepos -}}
{{- fail "argocd.appProject.sourceRepos must include at least one repository when argocd.appProject.create=true" -}}
{{- end -}}
{{- range $repo := .Values.argocd.appProject.sourceRepos -}}
{{- if eq $repo "*" -}}
{{- fail "argocd.appProject.sourceRepos must not include wildcard '*'" -}}
{{- end -}}
{{- end -}}
{{- if not .Values.argocd.appProject.destinations -}}
{{- fail "argocd.appProject.destinations must include at least one destination when argocd.appProject.create=true" -}}
{{- end -}}
{{- range $destination := .Values.argocd.appProject.destinations -}}
{{- if or (not $destination.namespace) (not $destination.server) -}}
{{- fail "each argocd.appProject.destinations entry must set namespace and server" -}}
{{- end -}}
{{- if or (eq $destination.namespace "*") (eq $destination.server "*") -}}
{{- fail "argocd.appProject.destinations must not include wildcard namespace or server" -}}
{{- end -}}
{{- end -}}
{{- range $resource := .Values.argocd.appProject.clusterResourceWhitelist -}}
{{- if and (eq ($resource.group | default "") "*") (eq ($resource.kind | default "") "*") -}}
{{- fail "argocd.appProject.clusterResourceWhitelist must not include blanket '*/*' access" -}}
{{- end -}}
{{- end -}}
{{- range $resource := .Values.argocd.appProject.clusterResourceBlacklist -}}
{{- if or (not (hasKey $resource "group")) (not (hasKey $resource "kind")) -}}
{{- fail "each argocd.appProject.clusterResourceBlacklist entry must set group and kind" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Validate namespace-scoped ArgoCD access grants.
*/}}
{{- define "argocd-integration.validateNamespaceGrants" -}}
{{- if .Values.argocd.access.namespaceGrants.create -}}
{{- if not (include "argocd-integration.namespaceGrantControllerNamespace" .) -}}
{{- fail "argocd.access.namespaceGrants.controllerNamespace or argocd.target.namespace is required when namespace grants are enabled" -}}
{{- end -}}
{{- if not .Values.argocd.access.namespaceGrants.controllerServiceAccount -}}
{{- fail "argocd.access.namespaceGrants.controllerServiceAccount is required when namespace grants are enabled" -}}
{{- end -}}
{{- if not .Values.argocd.access.namespaceGrants.namespaces -}}
{{- fail "argocd.access.namespaceGrants.namespaces must include at least one namespace when namespace grants are enabled" -}}
{{- end -}}
{{- range $namespace := .Values.argocd.access.namespaceGrants.namespaces -}}
{{- if or (not $namespace) (eq $namespace "*") -}}
{{- fail "argocd.access.namespaceGrants.namespaces entries must be explicit namespace names, not wildcards" -}}
{{- end -}}
{{- end -}}
{{- if not .Values.argocd.access.namespaceGrants.rules -}}
{{- fail "argocd.access.namespaceGrants.rules must include at least one rule when namespace grants are enabled" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Validate named cluster capability grants.
*/}}
{{- define "argocd-integration.validateClusterCapabilities" -}}
{{- if .Values.argocd.access.clusterCapabilities.create -}}
{{- if not (include "argocd-integration.clusterCapabilityControllerNamespace" .) -}}
{{- fail "argocd.access.clusterCapabilities.controllerNamespace or argocd.target.namespace is required when cluster capabilities are enabled" -}}
{{- end -}}
{{- if not .Values.argocd.access.clusterCapabilities.controllerServiceAccount -}}
{{- fail "argocd.access.clusterCapabilities.controllerServiceAccount is required when cluster capabilities are enabled" -}}
{{- end -}}
{{- if not .Values.argocd.access.clusterCapabilities.capabilities -}}
{{- fail "argocd.access.clusterCapabilities.capabilities must include at least one named capability when cluster capabilities are enabled" -}}
{{- end -}}
{{- range $capability := .Values.argocd.access.clusterCapabilities.capabilities -}}
{{- if ne $capability "namespaces" -}}
{{- fail (printf "unsupported argocd.access.clusterCapabilities capability %q; supported capabilities: namespaces" $capability) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
