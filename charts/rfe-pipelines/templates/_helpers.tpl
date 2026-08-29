{{/*
Builds the Image Builder repository payload expected by existing Ansible roles.
*/}}
{{- define "rfePipelines.rhsmRepositories" -}}
{{- dict "repositories" (.Values.rhelTarget.imageBuilder.repositories | default list) | toPrettyJson -}}
{{- end -}}
