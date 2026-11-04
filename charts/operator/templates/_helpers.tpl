{{- define "operator.component" -}}
{{- get (dict "openshift-gitops-operator" "gitops" "kubevirt-hyperconverged" "virtualization" "odf-operator" "odf" "openshift-pipelines-operator-rh" "pipelines" "quay-operator" "registry" "nexus-operator" "nexus") .Values.operator.name -}}
{{- end -}}
{{- define "operator.managed" -}}
{{- $name := include "operator.component" . -}}
{{- $component := dig $name dict (default dict .Values.components) -}}
{{- $mode := dig "mode" "managed" $component -}}
{{- if and $name (not (has $mode (list "managed" "byo" "disabled"))) -}}{{- fail (printf "components.%s.mode must be one of: managed, byo, disabled" $name) -}}{{- end -}}
{{- if eq $name "pipelines" -}}
{{- if and (eq $mode "byo") (empty (dig "connection" "namespace" "" $component)) -}}{{- fail "components.pipelines.connection.namespace is required for BYO Pipelines" -}}{{- end -}}
{{- end -}}
{{- or (not $name) (eq $mode "managed") -}}
{{- end -}}
