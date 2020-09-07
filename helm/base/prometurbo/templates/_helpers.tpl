{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "prometurbo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "prometurbo.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "prometurbo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Return the proper image name
*/}}
{{- define "prometurbo_image" -}}
{{- $repositoryName := .Values.image.repository -}}
{{- $tag := .Values.image.prometurboTag | toString -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .Values.global }}
    {{- if and .Values.global.repository .Values.global.tag (eq $repositoryName "turbonomic") (contains "SNAPSHOT" .Values.global.tag ) }}
        {{- printf "%s/prometurbo:%s" .Values.global.repository $tag -}}
    {{- else if and .Values.global.repository .Values.global.tag (eq $repositoryName "turbonomic") -}}
        {{- printf "%s/prometurbo:%s" .Values.global.repository .Values.global.tag -}}
     {{- else -}}
        {{- printf "%s/prometurbo:%s" $repositoryName $tag -}}
   {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the proper image name
*/}}
{{- define "turbodif_image" -}}
{{- $repositoryName := .Values.image.repository -}}
{{- $tag := .Values.image.turbodifTag | toString -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .Values.global }}
    {{- if and .Values.global.repository .Values.global.tag (eq $repositoryName "turbonomic") (contains "SNAPSHOT" .Values.global.tag ) }}
        {{- printf "%s/turbodif:%s" .Values.global.repository $tag -}}
    {{- else if and .Values.global.repository .Values.global.tag (eq $repositoryName "turbonomic") -}}
        {{- printf "%s/turbodif:%s" .Values.global.repository .Values.global.tag -}}
    {{- else -}}
        {{- printf "%s/turbodif:%s" $repositoryName $tag -}}
    {{- end -}}
{{- end -}}
{{- end -}}
