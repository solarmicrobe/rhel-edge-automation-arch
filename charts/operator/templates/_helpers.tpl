{{- define "operator.pipelinesValidate" -}}
{{- if eq .Values.operator.name "openshift-pipelines-operator-rh" -}}
{{- if and (eq .Values.components.pipelines.mode "byo") (empty .Values.components.pipelines.connection.namespace) -}}
{{- fail "components.pipelines.connection.namespace is required for BYO Pipelines" -}}
{{- end -}}
{{- end -}}
{{- end -}}
