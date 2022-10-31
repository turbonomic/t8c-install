{{/* vim: set filetype=mustache: */}}
{{/*
Selector labels
*/}}
{{- define "clientNetwork.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Common labels
*/}}
{{- define "clientNetwork.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
