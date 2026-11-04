{{- define "rfePipelines.workflow" -}}
{{- $workflows := dict -}}
{{- if hasKey .Values "workflows" -}}
{{- if not (kindIs "map" .Values.workflows) -}}{{- fail "workflows must be an object" -}}{{- end -}}
{{- $workflows = .Values.workflows -}}
{{- end -}}
{{- $settings := dig .name dict $workflows -}}
{{- if not (kindIs "map" $settings) -}}{{- fail (printf "workflows.%s must be an object" .name) -}}{{- end -}}
{{- if and (hasKey $settings "enabled") (not (kindIs "bool" (get $settings "enabled"))) -}}{{- fail (printf "workflows.%s.enabled must be boolean" .name) -}}{{- end -}}
{{- if hasKey $settings "enabled" -}}{{ get $settings "enabled" }}{{- else -}}true{{- end -}}
{{- end -}}
{{- define "rfePipelines.anyWorkflow" -}}
{{- $active := false -}}
{{- range $name := list "composeImage" "stageImage" "publishOstree" "publishIso" "serveKickstarts" -}}
{{- if eq (include "rfePipelines.workflow" (dict "Values" $.Values "name" $name)) "true" -}}{{- $active = true -}}{{- end -}}
{{- end -}}
{{- $active -}}
{{- end -}}
{{/*
Builds the Image Builder repository payload expected by existing Ansible roles.
*/}}
{{- define "rfePipelines.rhsmRepositories" -}}
{{- dict "repositories" (.Values.rhelTarget.imageBuilder.repositories | default list) | toPrettyJson -}}
{{- end -}}

{{- define "rfe-pipelines.registryValidate" -}}
{{- $registry := .registry -}}
{{- if and (hasKey $registry "mode") (not (kindIs "string" (get $registry "mode"))) -}}{{- fail "components.registry.mode must be a lifecycle string" -}}{{- end -}}
{{- if not (has (dig "mode" "managed" $registry) (list "managed" "byo" "disabled")) -}}
{{- fail "components.registry.mode must be one of: managed, byo, disabled" -}}
{{- end -}}
{{- if and (hasKey $registry "connection") (not (kindIs "map" (get $registry "connection"))) -}}{{- fail "components.registry.connection must be an object" -}}{{- end -}}
{{- $connection := default dict (get $registry "connection") -}}
{{- if hasKey $connection "imagePath" -}}
{{- if not (kindIs "string" (get $connection "imagePath")) -}}{{- fail "components.registry.connection.imagePath must be a registry repository path" -}}{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9][A-Za-z0-9.:-]*/[A-Za-z0-9_./-]+$" (get $connection "imagePath")) -}}{{- fail "components.registry.connection.imagePath must be a registry repository path" -}}{{- end -}}
{{- end -}}
{{- range $field := list "publisherSecretName" "pullSecretName" -}}
{{- if hasKey $connection $field -}}
{{- $secret := get $connection $field -}}
{{- if not (kindIs "string" $secret) -}}{{- fail (printf "components.registry.connection.%s must be a Kubernetes DNS name" $field) -}}{{- end -}}
{{- if or (gt (len $secret) 253) (not (regexMatch "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$" $secret)) -}}{{- fail (printf "components.registry.connection.%s must be a Kubernetes DNS name" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if and .consumer (eq (get $registry "mode") "byo") -}}
{{- range $field := list "imagePath" "publisherSecretName" -}}
{{- if empty (dig "connection" $field "" $registry) -}}
{{- fail (printf "components.registry.connection.%s is required for BYO registry" $field) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- define "rfePipelines.registryMode" -}}
{{- if eq .Values.components.registry.mode "byo" -}}external{{- else -}}{{ .Values.publicationEndpoints.registry.mode }}{{- end -}}
{{- end -}}
{{- define "rfePipelines.registryImagePath" -}}
{{- if eq .Values.components.registry.mode "byo" -}}{{ .Values.components.registry.connection.imagePath }}{{- else -}}{{ .Values.publicationEndpoints.registry.imagePath }}{{- end -}}
{{- end -}}
{{- define "rfePipelines.registryPublisherSecret" -}}
{{- if eq .Values.components.registry.mode "byo" -}}{{ .Values.components.registry.connection.publisherSecretName }}{{- else -}}{{ .Values.publicationEndpoints.registry.publisherSecretName }}{{- end -}}
{{- end -}}
{{- define "rfePipelines.nexusValidate" -}}
{{- $nexus := .nexus -}}
{{- $mode := dig "mode" "managed" $nexus -}}
{{- if not (has $mode (list "managed" "byo" "disabled")) -}}{{- fail "components.nexus.mode must be one of: managed, byo, disabled" -}}{{- end -}}
{{- if and (hasKey $nexus "connection") (not (kindIs "map" (get $nexus "connection"))) -}}{{- fail "components.nexus.connection must be an object" -}}{{- end -}}
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
{{- if and (hasKey $nexus "artifacts") (not (kindIs "map" $nexus.artifacts)) -}}{{- fail "components.nexus.artifacts must be an object" -}}{{- end -}}
{{- $artifacts := default dict (get $nexus "artifacts") -}}
{{- if and (hasKey $artifacts "upload") (not (kindIs "bool" (get $artifacts "upload"))) -}}{{- fail "components.nexus.artifacts.upload must be boolean" -}}{{- end -}}
{{- if and .consumer (eq $mode "byo") -}}
{{- $required := list "credentialsSecretName" "credentialsSecretNamespace" "serviceName" "servicePort" "httpScheme" -}}
{{- if .kickstart -}}{{- $required = concat $required (list "routeName" "routeNamespace" "kickstartRepository") -}}{{- end -}}
{{- if .iso -}}{{- $required = append $required "autoIsoRepository" -}}{{- end -}}
{{- range $field := $required -}}
{{- if empty (get $connection $field) -}}{{- fail (printf "components.nexus.connection.%s is required for BYO Nexus consumers" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "rfePipelines.nexusUpload" -}}
{{- $component := .Values.components.nexus -}}
{{- $upload := eq $component.mode "managed" -}}
{{- if hasKey (default dict $component.artifacts) "upload" -}}{{- $upload = $component.artifacts.upload -}}{{- end -}}
{{- and $upload (ne $component.mode "disabled") (or (eq $component.mode "byo") (ne .Values.publicationEndpoints.artifactRepository.mode "disabled")) -}}
{{- end -}}
