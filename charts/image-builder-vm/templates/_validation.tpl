{{- define "imageBuilderVM.validate" -}}
{{- $vm := .Values.imageBuilderVM -}}
{{- $sourceMode := $vm.dataVolumeSource | default "datasource" -}}
{{- $dataSource := $vm.dataSource | default dict -}}
{{- $legacyPvcSource := $vm.legacyPvcSource | default dict -}}
{{- $legacyPvcEnabled := $legacyPvcSource.enabled | default false -}}
{{- $target := .Values.rhelTarget | default dict -}}
{{- $targetMajor := toString ($target.major | default "8") -}}
{{- $architecture := $target.architecture | default "" -}}
{{- $imageBuilder := $target.imageBuilder | default dict -}}
{{- $imageMode := $target.imageMode | default dict -}}
{{- if eq $targetMajor "10" -}}
{{- fail "rhelTarget.major=10 is not supported by the current Image Builder VM runtime; RHEL 10 requires a future image-mode/bootc implementation" -}}
{{- end -}}
{{- if not (has $targetMajor (list "8" "9")) -}}
{{- fail "rhelTarget.major must be one of: 8, 9" -}}
{{- end -}}
{{- if empty $architecture -}}
{{- fail "rhelTarget.architecture is required" -}}
{{- end -}}
{{- if $imageMode.enabled -}}
{{- fail "rhelTarget.imageMode.enabled=true is unsupported until a future bootc/image-mode workflow is implemented" -}}
{{- end -}}
{{- if and (hasKey $imageBuilder "enabled") (not $imageBuilder.enabled) -}}
{{- fail "rhelTarget.imageBuilder.enabled=false is unsupported while the Image Builder VM remains the artifact runtime" -}}
{{- end -}}
{{- if empty .Values.rhel.version -}}
{{- fail "rhel.version is required for Image Builder VM KubeVirt metadata" -}}
{{- end -}}
{{- if not (hasPrefix $targetMajor (toString .Values.rhel.version)) -}}
{{- fail (printf "rhel.version must match rhelTarget.major=%s" $targetMajor) -}}
{{- end -}}
{{- if eq (len ($imageBuilder.repositories | default list)) 0 -}}
{{- fail "rhelTarget.imageBuilder.repositories must include at least one RHSM repository for Image Builder VM configuration" -}}
{{- end -}}
{{- range $repo := ($imageBuilder.repositories | default list) -}}
{{- if and (ne $targetMajor "8") (contains "rhel-8-" $repo) -}}
{{- fail (printf "rhelTarget.imageBuilder.repositories contains RHEL 8 repository %q but rhelTarget.major=%s" $repo $targetMajor) -}}
{{- end -}}
{{- if and (ne $targetMajor "9") (contains "rhel-9-" $repo) -}}
{{- fail (printf "rhelTarget.imageBuilder.repositories contains RHEL 9 repository %q but rhelTarget.major=%s" $repo $targetMajor) -}}
{{- end -}}
{{- end -}}
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
{{- if and (ne $targetMajor "8") (eq $dataSource.name "rhel8") -}}
{{- fail "imageBuilderVM.dataSource.name=rhel8 does not match rhelTarget.major; set an explicit DataSource for the selected RHEL target" -}}
{{- end -}}
{{- if and (ne $targetMajor "9") (eq $dataSource.name "rhel9") -}}
{{- fail "imageBuilderVM.dataSource.name=rhel9 does not match rhelTarget.major; set an explicit DataSource for the selected RHEL target" -}}
{{- end -}}
{{- if and (ne $targetMajor "8") (contains "rhel8" $vm.machine.type) -}}
{{- fail "imageBuilderVM.machine.type contains rhel8 and does not match rhelTarget.major; set explicit VM machine metadata for the selected RHEL target" -}}
{{- end -}}
{{- if and (ne $targetMajor "9") (contains "rhel9" $vm.machine.type) -}}
{{- fail "imageBuilderVM.machine.type contains rhel9 and does not match rhelTarget.major; set explicit VM machine metadata for the selected RHEL target" -}}
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
