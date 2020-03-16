{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "datacloud.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "datacloud.fullname" -}}
	{{- if .Values.fullnameOverride -}}
		{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
	{{- else -}}
		{{- $name := default .Chart.Name .Values.nameOverride -}}
		{{- if (contains $name .Release.Name) -}}
			{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
		{{- else -}}
			{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
		{{- end -}}
	{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "datacloud.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Return the proper image name
*/}}
{{- define "image" -}}
{{- $repositoryName := .Values.image.repository -}}
{{- $tag := .Values.image.tag | toString -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .Values.global }}
    {{- if and .Values.global.repository .Values.global.tag (eq $repositoryName "turbonomic") (eq $tag "latest") }}
        {{- printf "%s/%s:%s" .Values.global.repository .Chart.Name .Values.global.tag -}}
    {{- else -}}
        {{- printf "%s/%s:%s" $repositoryName .Chart.Name $tag -}}
    {{- end -}}
{{- else -}}
    {{- printf "%s/%s:%s" $repositoryName .Chart.Name $tag -}}
{{- end -}}
{{- end -}}

{{/*
Return the pullPolicy
*/}}
{{- define "pullPolicy" -}}
{{- $pullPolicy := .Values.image.pullPolicy -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .Values.global }}
    {{- if and .Values.global.pullPolicy (eq $pullPolicy "IfNotPresent") }}
        {{- printf "%s" .Values.global.pullPolicy -}}
    {{- else -}}
        {{- printf "%s" $pullPolicy -}}
    {{- end -}}
{{- else -}}
    {{- printf "%s" $pullPolicy -}}
{{- end -}}
{{- end -}}
