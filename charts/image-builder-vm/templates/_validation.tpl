{{- define "imageBuilderVM.validate" -}}
{{- $vm := .Values.imageBuilderVM -}}
{{- $sourceMode := $vm.dataVolumeSource | default "datasource" -}}
{{- $dataSource := $vm.dataSource | default dict -}}
{{- $legacyPvcSource := $vm.legacyPvcSource | default dict -}}
{{- $legacyPvcEnabled := $legacyPvcSource.enabled | default false -}}
{{- if not (has $sourceMode (list "datasource" "pvc")) -}}
{{- fail "imageBuilderVM.dataVolumeSource must be one of: datasource, pvc" -}}
{{- end -}}
{{- if not (ge ($vm.replicas | int) 1) -}}
{{- fail "imageBuilderVM.replicas must be greater than or equal to 1!" -}}
{{- end -}}
{{- if eq $sourceMode "datasource" -}}
{{- if empty $dataSource.name -}}
{{- fail "imageBuilderVM.dataSource.name is required when imageBuilderVM.dataVolumeSource=datasource" -}}
{{- end -}}
{{- if empty $dataSource.namespace -}}
{{- fail "imageBuilderVM.dataSource.namespace is required when imageBuilderVM.dataVolumeSource=datasource" -}}
{{- end -}}
{{- if $legacyPvcEnabled -}}
{{- fail "imageBuilderVM.legacyPvcSource.enabled=true requires imageBuilderVM.dataVolumeSource=pvc" -}}
{{- end -}}
{{- end -}}
{{- if eq $sourceMode "pvc" -}}
{{- if not $legacyPvcEnabled -}}
{{- fail "imageBuilderVM.dataVolumeSource=pvc is legacy and requires imageBuilderVM.legacyPvcSource.enabled=true" -}}
{{- end -}}
{{- if empty $legacyPvcSource.repositoryUrl -}}
{{- fail "imageBuilderVM.legacyPvcSource.repositoryUrl is required when imageBuilderVM.dataVolumeSource=pvc" -}}
{{- end -}}
{{- end -}}
{{- end -}}
