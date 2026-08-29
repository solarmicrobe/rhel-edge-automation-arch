{{- define "httpd.validate" -}}
{{- if and (not .Values.buildConfig.enabled) (not .Values.image.repository) -}}
{{- fail "httpd.image.repository is required when buildConfig.enabled=false" -}}
{{- end -}}
{{- end -}}
