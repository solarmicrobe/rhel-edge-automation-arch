{{- define "rfePipelines.validate" -}}
{{- $endpoints := .Values.publicationEndpoints | default dict -}}
{{- $registry := $endpoints.registry | default dict -}}
{{- $artifactRepository := $endpoints.artifactRepository | default dict -}}
{{- $httpServing := $endpoints.httpServing | default dict -}}
{{- $nexus := $artifactRepository.nexus | default dict -}}
{{- $registryMode := $registry.mode | default "managed-reference" -}}
{{- $artifactRepositoryMode := $artifactRepository.mode | default "managed-reference" -}}
{{- $httpServingMode := $httpServing.mode | default "managed-reference" -}}
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
