{{- define "nexus.nexusValidate" -}}
{{- $nexus := .nexus -}}
{{- $mode := dig "mode" "managed" $nexus -}}
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
