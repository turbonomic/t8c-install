{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "xl.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "xl.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "xl.chart" -}}
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

{{/*
  Set the XL component JVM environment params, based on any custom settings from the custom resource file.
  * If .Values.debug or .Values.global.debug are set, then JAVA_DEBUG="true" will be set in the env vars.
  (the java component will interpret this as a signal that the debugging runtime options should be added
  to the command line)
  * .Values.javaDebugOptions or .Values.global.javaDebugOptions will be passed as JAVA_DEBUG_OPTS
  * .Values.javaMaxRAMPercentage or .Values.global.javaMaxRAMPercentage will be passed as JAVA_MAX_RAM_PCT
  * .Values.javaComponentOptions will be passed as JAVA_COMPONENT_OPTS
  * .Values.javaEnvironmentOptions will be passed as JAVA_ENV_OPTS
  * .Values.javaOptions will be passed as JAVA_OPTS. This will completely override the default set of JVM
  runtime options.
*/}}
{{- define "java.setJVMEnvironmentOptions" }}
    {{- if or .Values.global.debug .Values.debug }}
        - name: JAVA_DEBUG
          value: "true"
    {{- end }}
    {{- if or .Values.global.javaDebugOptions .Values.javaDebugOptions }}
        - name: JAVA_DEBUG_OPTS
          value: {{ coalesce .Values.javaDebugOptions .Values.global.javaDebugOptions "" }}
    {{- end }}
    {{- if or .Values.global.javaMaxRAMPercentage .Values.javaMaxRAMPercentage }}
        - name: JAVA_MAX_RAM_PCT
          value: {{ coalesce .Values.javaMaxRAMPercentage .Values.global.javaMaxRAMPercentage "" | quote }}
    {{- end }}
    {{- if .Values.javaComponentOptions }}
        - name: JAVA_COMPONENT_OPTS
          value: {{ .Values.javaComponentOptions }}
    {{- end }}
    {{- if .Values.global.javaEnvironmentOptions }}
        - name: JAVA_ENV_OPTS
          value: {{ .Values.global.javaEnvironmentOptions }}
    {{- end }}
    {{- if or .Values.global.javaBaseOptions .Values.javaBaseOptions }}
        - name: JAVA_BASE_OPTS
          value: {{ coalesce .Values.javaBaseOptions .Values.global.javaBaseOptions "" }}
    {{- end }}
    {{- if .Values.javaOptions }}
        - name: JAVA_OPTS
          value: {{ .Values.javaOptions }}
    {{- end }}
{{- end }}

{{ define "common.getReadinessThresholds" }}
initialDelaySeconds: {{ coalesce .Values.readinessInitialDelaySecs .Values.global.readinessInitialDelaySecs 20 }}
periodSeconds: {{ coalesce .Values.readinessPeriodSecs .Values.global.readinessPeriodSecs 15 }}
timeoutSeconds: {{ coalesce .Values.readinessTimeoutSecs .Values.global.readinessTimeoutSecs 10 }}
successThreshold: {{ coalesce .Values.readinessSuccessThreshold .Values.global.readinessSuccessThreshold 1 }}
failureThreshold: {{ coalesce .Values.readinessFailureThreshold .Values.global.readinessFailureThreshold 5 }}
{{ end }}

{{ define "common.getLivenessThresholds" }}
initialDelaySeconds: {{ coalesce .Values.livenessInitialDelaySecs .Values.global.livenessInitialDelaySecs 20 }}
periodSeconds: {{ coalesce .Values.livenessPeriodSecs .Values.global.livenessPeriodSecs 60 }}
timeoutSeconds: {{ coalesce .Values.livenessTimeoutSecs .Values.global.livenessTimeoutSecs 10 }}
successThreshold: {{ coalesce .Values.livenessSuccessThreshold .Values.global.livenessSuccessThreshold 1 }}
failureThreshold: {{ coalesce .Values.livenessFailureThreshold .Values.global.livenessFailureThreshold 60 }}
{{ end }}
