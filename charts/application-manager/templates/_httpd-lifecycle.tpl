{{- define "application-manager.httpdValidate" -}}
{{- $httpd := .httpd -}}
{{- $mode := dig "mode" "managed" $httpd -}}
{{- if not (has $mode (list "managed" "byo" "disabled")) -}}{{- fail "components.httpd.mode must be one of: managed, byo, disabled" -}}{{- end -}}
{{- $connection := dig "connection" dict $httpd -}}
{{- if not (kindIs "map" $connection) -}}{{- fail "components.httpd.connection must be an object" -}}{{- end -}}
{{- range $field := list "routeName" "routeNamespace" "podNamespace" "podLabelSelector" "webRoot" "stageServiceAccountName" -}}
{{- if and (eq $mode "byo") (empty (get $connection $field)) -}}{{- fail (printf "components.httpd.connection.%s is required for BYO HTTPD" $field) -}}{{- end -}}
{{- if hasKey $connection $field -}}
{{- $value := get $connection $field -}}
{{- if not (kindIs "string" $value) -}}{{- fail (printf "components.httpd.connection.%s must be a string" $field) -}}{{- end -}}
{{- $pattern := "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" -}}
{{- $limit := 63 -}}
{{- if has $field (list "routeName" "stageServiceAccountName") -}}{{- $pattern = "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$" -}}{{- $limit = 253 -}}{{- end -}}
{{- if eq $field "podLabelSelector" -}}{{- $pattern = "^[A-Za-z0-9][A-Za-z0-9_.:/-]*=[A-Za-z0-9][A-Za-z0-9_.-]*$" -}}{{- $limit = 253 -}}{{- end -}}
{{- if eq $field "webRoot" -}}{{- $pattern = "^(/[A-Za-z0-9_-]+)+$" -}}{{- $limit = 4096 -}}{{- end -}}
{{- if or (gt (len $value) $limit) (not (regexMatch $pattern $value)) -}}{{- fail (printf "components.httpd.connection.%s must be a safe nonempty endpoint value" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- $consumer := .consumer -}}
{{- $endpoint := default dict .endpoint -}}
{{- range $flag := list "content" "staging" -}}
{{- $settings := dig $flag dict $endpoint -}}
{{- if not (kindIs "map" $settings) -}}{{- fail (printf "publicationEndpoints.httpServing.%s must be an object" $flag) -}}{{- end -}}
{{- $key := ternary "write" "create" (eq $flag "content") -}}
{{- if and (hasKey $settings $key) (not (kindIs "bool" (get $settings $key))) -}}{{- fail (printf "publicationEndpoints.httpServing.%s.%s must be boolean" $flag $key) -}}{{- end -}}
{{- if $consumer -}}
{{- $allowed := eq $mode "managed" -}}
{{- if hasKey $settings $key -}}{{- $allowed = get $settings $key -}}{{- end -}}
{{- if not $allowed -}}{{- fail (printf "publicationEndpoints.httpServing.%s.%s=true is required for mandatory HTTPD workflows" $flag $key) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if and .consumer (eq $mode "disabled") -}}{{- fail "components.httpd.mode=disabled cannot support mandatory HTTPD workflows" -}}{{- end -}}
{{- end -}}
