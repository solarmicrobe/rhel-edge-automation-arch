
{{- define "quay.registryValidate" -}}
{{- $registry := .registry -}}
{{- if and (hasKey $registry "mode") (not (kindIs "string" (get $registry "mode"))) -}}{{- fail "components.registry.mode must be a lifecycle string" -}}{{- end -}}
{{- if not (has (dig "mode" "managed" $registry) (list "managed" "byo" "disabled")) -}}
{{- fail "components.registry.mode must be one of: managed, byo, disabled" -}}
{{- end -}}
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
