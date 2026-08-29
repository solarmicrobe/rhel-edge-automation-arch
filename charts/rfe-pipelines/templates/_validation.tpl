{{- define "rfePipelines.validate" -}}
{{- $endpoints := .Values.publicationEndpoints | default dict -}}
{{- $registry := $endpoints.registry | default dict -}}
{{- $artifactRepository := $endpoints.artifactRepository | default dict -}}
{{- $httpServing := $endpoints.httpServing | default dict -}}
{{- $nexus := $artifactRepository.nexus | default dict -}}
{{- $registryMode := $registry.mode | default "managed-reference" -}}
{{- $artifactRepositoryMode := $artifactRepository.mode | default "managed-reference" -}}
{{- $httpServingMode := $httpServing.mode | default "managed-reference" -}}
{{- $target := .Values.rhelTarget | default dict -}}
{{- $targetMajor := toString ($target.major | default "8") -}}
{{- $architecture := $target.architecture | default "" -}}
{{- $imageBuilder := $target.imageBuilder | default dict -}}
{{- $composeTypes := $imageBuilder.composeTypes | default dict -}}
{{- $imageMode := $target.imageMode | default dict -}}
{{- if eq $targetMajor "10" -}}
{{- fail "rhelTarget.major=10 is not supported by the current Image Builder rpm-ostree workflows; RHEL 10 requires a future image-mode/bootc implementation" -}}
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
{{- fail "rhelTarget.imageBuilder.enabled=false is unsupported while the current pipelines use Image Builder rpm-ostree workflows" -}}
{{- end -}}
{{- if empty $imageBuilder.ostreeRef -}}
{{- fail "rhelTarget.imageBuilder.ostreeRef is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if not (contains (printf "rhel/%s/%s/" $targetMajor $architecture) $imageBuilder.ostreeRef) -}}
{{- fail (printf "rhelTarget.imageBuilder.ostreeRef must match rhelTarget.major=%s and rhelTarget.architecture=%s" $targetMajor $architecture) -}}
{{- end -}}
{{- if empty $composeTypes.container -}}
{{- fail "rhelTarget.imageBuilder.composeTypes.container is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if empty $composeTypes.installer -}}
{{- fail "rhelTarget.imageBuilder.composeTypes.installer is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if eq (len ($imageBuilder.repositories | default list)) 0 -}}
{{- fail "rhelTarget.imageBuilder.repositories must include at least one RHSM repository when Image Builder workflows are enabled" -}}
{{- end -}}
{{- range $repo := ($imageBuilder.repositories | default list) -}}
{{- if and (ne $targetMajor "8") (contains "rhel-8-" $repo) -}}
{{- fail (printf "rhelTarget.imageBuilder.repositories contains RHEL 8 repository %q but rhelTarget.major=%s" $repo $targetMajor) -}}
{{- end -}}
{{- if and (ne $targetMajor "9") (contains "rhel-9-" $repo) -}}
{{- fail (printf "rhelTarget.imageBuilder.repositories contains RHEL 9 repository %q but rhelTarget.major=%s" $repo $targetMajor) -}}
{{- end -}}
{{- end -}}
{{- if not (has $registryMode (list "managed-reference" "external")) -}}
{{- fail "publicationEndpoints.registry.mode must be one of: managed-reference, external" -}}
{{- end -}}
{{- if and (eq $registryMode "external") (empty $registry.imagePath) -}}
{{- fail "publicationEndpoints.registry.imagePath is required when publicationEndpoints.registry.mode=external" -}}
{{- end -}}
{{- if empty $registry.publisherSecretName -}}
{{- fail "publicationEndpoints.registry.publisherSecretName is required" -}}
{{- end -}}
{{- if and (eq $registryMode "managed-reference") (empty $registry.setupSecretName) -}}
{{- fail "publicationEndpoints.registry.setupSecretName is required when publicationEndpoints.registry.mode=managed-reference" -}}
{{- end -}}
{{- if not (has $artifactRepositoryMode (list "managed-reference" "disabled")) -}}
{{- fail "publicationEndpoints.artifactRepository.mode must be one of: managed-reference, disabled" -}}
{{- end -}}
{{- if and (eq $artifactRepositoryMode "managed-reference") (empty $nexus.credentialsSecretName) -}}
{{- fail "publicationEndpoints.artifactRepository.nexus.credentialsSecretName is required when publicationEndpoints.artifactRepository.mode=managed-reference" -}}
{{- end -}}
{{- if and (eq $artifactRepositoryMode "managed-reference") (empty $nexus.credentialsSecretNamespace) -}}
{{- fail "publicationEndpoints.artifactRepository.nexus.credentialsSecretNamespace is required when publicationEndpoints.artifactRepository.mode=managed-reference" -}}
{{- end -}}
{{- if and (eq $artifactRepositoryMode "managed-reference") (empty $nexus.serviceName) -}}
{{- fail "publicationEndpoints.artifactRepository.nexus.serviceName is required when publicationEndpoints.artifactRepository.mode=managed-reference" -}}
{{- end -}}
{{- if not (has $httpServingMode (list "managed-reference")) -}}
{{- fail "publicationEndpoints.httpServing.mode must be one of: managed-reference" -}}
{{- end -}}
{{- if empty $httpServing.routeName -}}
{{- fail "publicationEndpoints.httpServing.routeName is required" -}}
{{- end -}}
{{- if empty $httpServing.podNamespace -}}
{{- fail "publicationEndpoints.httpServing.podNamespace is required" -}}
{{- end -}}
{{- end -}}
