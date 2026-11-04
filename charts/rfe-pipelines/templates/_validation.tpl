{{- define "rfePipelines.vmLifecycleValidate" -}}
{{- $component := dig "imageBuilderVM" dict (default dict .Values.components) -}}
{{- if not (has (dig "mode" "managed" $component) (list "managed" "byo" "disabled")) -}}{{- fail "components.imageBuilderVM.mode must be one of: managed, byo, disabled" -}}{{- end -}}
{{- if and (hasKey $component "connection") (not (kindIs "map" $component.connection)) -}}{{- fail "components.imageBuilderVM.connection must be an object" -}}{{- end -}}
{{- $connection := default dict $component.connection -}}
{{- range $field := list "host" "sshSecretName" -}}
{{- if and $.consumer (eq (get $component "mode") "byo") (empty (get $connection $field)) -}}{{- fail (printf "components.imageBuilderVM.connection.%s is required for BYO Image Builder VM" $field) -}}{{- end -}}
{{- if hasKey $connection $field -}}
{{- $value := get $connection $field -}}
{{- if not (kindIs "string" $value) -}}{{- fail (printf "components.imageBuilderVM.connection.%s must be a DNS name" $field) -}}{{- end -}}
{{- $pattern := "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$" -}}
{{- if eq $field "host" -}}{{- $pattern = "^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$" -}}{{- end -}}
{{- if or (gt (len $value) 253) (not (regexMatch $pattern $value)) -}}{{- fail (printf "components.imageBuilderVM.connection.%s must be a DNS name" $field) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- define "rfePipelines.validate" -}}
{{- $compose := eq (include "rfePipelines.workflow" (dict "Values" .Values "name" "composeImage")) "true" -}}
{{- $stage := eq (include "rfePipelines.workflow" (dict "Values" .Values "name" "stageImage")) "true" -}}
{{- $ostree := eq (include "rfePipelines.workflow" (dict "Values" .Values "name" "publishOstree")) "true" -}}
{{- $iso := eq (include "rfePipelines.workflow" (dict "Values" .Values "name" "publishIso")) "true" -}}
{{- $kickstart := eq (include "rfePipelines.workflow" (dict "Values" .Values "name" "serveKickstarts")) "true" -}}
{{- $any := or $compose $stage $ostree $iso $kickstart -}}
{{- include "rfePipelines.httpdValidate" (dict "httpd" .Values.components.httpd "endpoint" .Values.publicationEndpoints.httpServing "consumer" (or $stage $ostree $iso $kickstart) "stage" $stage "content" (or $ostree $iso $kickstart)) -}}
{{- $upload := eq (include "rfePipelines.nexusUpload" .) "true" -}}
{{- include "rfePipelines.nexusValidate" (dict "nexus" .Values.components.nexus "consumer" (and $upload (or $iso $kickstart)) "iso" $iso "kickstart" $kickstart) -}}
{{- include "rfe-pipelines.registryValidate" (dict "registry" .Values.components.registry "consumer" $compose) -}}
{{- if and (or $compose $stage) (eq .Values.components.registry.mode "disabled") -}}{{- fail "enabled image workflows require components.registry" -}}{{- end -}}
{{- $image := default dict .Values.publicationEndpoints.registry.image -}}
{{- $push := ne .Values.components.registry.mode "byo" -}}
{{- if hasKey $image "push" -}}{{- if not (kindIs "bool" $image.push) -}}{{- fail "publicationEndpoints.registry.image.push must be boolean" -}}{{- end -}}{{- $push = $image.push -}}{{- end -}}
{{- if and $compose (not $push) -}}{{- fail "composeImage requires publicationEndpoints.registry.image.push=true" -}}{{- end -}}
{{- if and $any (eq .Values.components.pipelines.mode "disabled") -}}{{- fail "enabled workflows require components.pipelines" -}}{{- end -}}
{{- if and $any (eq .Values.components.pipelines.mode "byo") (empty .Values.components.pipelines.connection.namespace) -}}{{- fail "components.pipelines.connection.namespace is required for BYO Pipelines" -}}{{- end -}}
{{- include "rfePipelines.vmLifecycleValidate" (dict "Values" .Values "consumer" (or $compose $iso)) -}}
{{- if and (or $compose $iso) (eq .Values.components.imageBuilderVM.mode "disabled") -}}{{- fail "composeImage and publishIso require components.imageBuilderVM" -}}{{- end -}}
{{- include "rfePipelines.rhelValidate" (dict "Values" .Values "compose" $compose "iso" $iso "ostree" $ostree) -}}
{{- if $compose -}}
{{- $registryMode := include "rfePipelines.registryMode" . -}}
{{- if not (has $registryMode (list "managed-reference" "external")) -}}{{- fail "publicationEndpoints.registry.mode must be one of: managed-reference, external" -}}{{- end -}}
{{- if and (eq $registryMode "external") (empty (include "rfePipelines.registryImagePath" .)) -}}{{- fail "publicationEndpoints.registry.imagePath is required for external compose publication" -}}{{- end -}}
{{- if empty (include "rfePipelines.registryPublisherSecret" .) -}}{{- fail "publicationEndpoints.registry.publisherSecretName is required" -}}{{- end -}}
{{- if and (eq $registryMode "managed-reference") (empty .Values.publicationEndpoints.registry.setupSecretName) -}}{{- fail "publicationEndpoints.registry.setupSecretName is required" -}}{{- end -}}
{{- end -}}
{{- if and $upload (or $iso $kickstart) (eq .Values.components.nexus.mode "managed") -}}
{{- $fields := list "credentialsSecretName" "credentialsSecretNamespace" "serviceName" "servicePort" "httpScheme" -}}
{{- if $iso -}}{{- $fields = append $fields "autoIsoRepository" -}}{{- end -}}
{{- if $kickstart -}}{{- $fields = concat $fields (list "routeName" "routeNamespace" "kickstartRepository") -}}{{- end -}}
{{- range $field := $fields -}}{{- if empty (get $.Values.publicationEndpoints.artifactRepository.nexus $field) -}}{{- fail (printf "publicationEndpoints.artifactRepository.nexus.%s is required for enabled uploads" $field) -}}{{- end -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- define "rfePipelines.rhelValidate" -}}
{{- $compose := .compose -}}{{- $iso := .iso -}}{{- $ostree := .ostree -}}
{{- $target := .Values.rhelTarget | default dict -}}
{{- $targetMajor := toString ($target.major | default "8") -}}
{{- $architecture := $target.architecture | default "" -}}
{{- $imageBuilder := $target.imageBuilder | default dict -}}
{{- $composeTypes := $imageBuilder.composeTypes | default dict -}}
{{- $imageMode := $target.imageMode | default dict -}}
{{- if or $compose $iso -}}
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
{{- end -}}
{{- if and (or $iso $ostree) (empty $imageBuilder.ostreeRef) -}}
{{- fail "rhelTarget.imageBuilder.ostreeRef is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if and (or $iso $ostree) (not (contains (printf "rhel/%s/%s/" $targetMajor $architecture) $imageBuilder.ostreeRef)) -}}
{{- fail (printf "rhelTarget.imageBuilder.ostreeRef must match rhelTarget.major=%s and rhelTarget.architecture=%s" $targetMajor $architecture) -}}
{{- end -}}
{{- if and $compose (empty $composeTypes.container) -}}
{{- fail "rhelTarget.imageBuilder.composeTypes.container is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if and $iso (empty $composeTypes.installer) -}}
{{- fail "rhelTarget.imageBuilder.composeTypes.installer is required when Image Builder workflows are enabled" -}}
{{- end -}}
{{- if or $compose $iso -}}
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
{{- end -}}
{{- end -}}
