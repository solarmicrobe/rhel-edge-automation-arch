{{/*
Builds the Image Builder repository payload expected by existing Ansible roles.
*/}}
{{- define "rfePipelines.rhsmRepositories" -}}
{{- dict "repositories" (.Values.rhelTarget.imageBuilder.repositories | default list) | toPrettyJson -}}
{{- end -}}

{{- define "rfe-pipelines.registryValidate" -}}
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
{{- define "rfePipelines.registryMode" -}}
{{- if eq .Values.components.registry.mode "byo" -}}external{{- else -}}{{ .Values.publicationEndpoints.registry.mode }}{{- end -}}
{{- end -}}
{{- define "rfePipelines.registryImagePath" -}}
{{- if eq .Values.components.registry.mode "byo" -}}{{ .Values.components.registry.connection.imagePath }}{{- else -}}{{ .Values.publicationEndpoints.registry.imagePath }}{{- end -}}
{{- end -}}
{{- define "rfePipelines.registryPublisherSecret" -}}
{{- if eq .Values.components.registry.mode "byo" -}}{{ .Values.components.registry.connection.publisherSecretName }}{{- else -}}{{ .Values.publicationEndpoints.registry.publisherSecretName }}{{- end -}}
{{- end -}}
