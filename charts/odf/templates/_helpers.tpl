{{- define "odf.lifecycleMode" -}}
{{- $components := default dict .Values.components -}}
{{- $odf := default dict (get $components "odf") -}}
{{- default "managed" (get $odf "mode") -}}
{{- end -}}

{{- define "odf.byoCreateObjects" -}}
{{- $components := default dict .Values.components -}}
{{- $odf := default dict (get $components "odf") -}}
{{- $byo := default dict (get $odf "byo") -}}
{{- if (get $byo "createObjects") -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "odf.validateLifecycle" -}}
{{- $mode := include "odf.lifecycleMode" . -}}
{{- if not (has $mode (list "managed" "byo" "disabled")) -}}
{{- fail "components.odf.mode must be one of: managed, byo, disabled" -}}
{{- end -}}
{{- end -}}

{{- define "odf.renderManagedResources" -}}
{{- $mode := include "odf.lifecycleMode" . -}}
{{- if or (eq $mode "managed") (and (eq $mode "byo") (eq (include "odf.byoCreateObjects" .) "true")) -}}true{{- else -}}false{{- end -}}
{{- end -}}
