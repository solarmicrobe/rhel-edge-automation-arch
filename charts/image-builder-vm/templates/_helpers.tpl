{{/*
Generates the RHEL labels and annotations that depend on the used RHEL version
*/}}
{{- define "kubevirtRHELLabel" -}}
{{- printf "os.template.kubevirt.io/rhel%s: 'true'" .Values.rhel.version }}
{{- end }}

{{- define "kubevirtRHELAnnotation" -}}
{{- printf "name.os.template.kubevirt.io/rhel%s: Red Hat Enterprise Linux %s.0 or higher" .Values.rhel.version (.Values.rhelTarget.major | toString) }}
{{- end }}
