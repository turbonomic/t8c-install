{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "xl.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "annotations" -}}
  {{- if .Values.global }}
    {{- if or .Values.annotations .Values.global.annotations }}
      {{- with .Values.annotations }}
  {{- toYaml . }}
      {{- end }}
      {{- with .Values.global.annotations }}
  {{- toYaml . }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "labels" -}}
{{- if .Values.global }}
  {{- if or .Values.labels .Values.global.labels }}
    {{- with .Values.labels }}
{{- toYaml . }}
    {{- end }}
    {{- with .Values.global.labels }}
{{- toYaml . }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "serviceAnnotations" -}}
  {{- if .Values.global }}
    {{- if or .Values.serviceAnnotations .Values.global.serviceAnnotations }}
      {{- with .Values.serviceAnnotations }}
  {{- toYaml . }}
      {{- end }}
      {{- with .Values.global.serviceAnnotations }}
  {{- toYaml . }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "serviceLabels" -}}
{{- if .Values.global }}
  {{- if or .Values.serviceLabels .Values.global.serviceLabels }}
    {{- with .Values.serviceLabels }}
{{- toYaml . }}
    {{- end }}
    {{- with .Values.global.serviceLabels }}
{{- toYaml . }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "imagePullSecrets" -}}
{{ if .Values.global -}}
{{- if .Values.global.registry -}}
{{- if .Values.global.imagePullSecret -}}
imagePullSecrets:
- name: {{ .Values.global.imagePullSecret }}
{{- else -}}
{{- if and .Values.global.imageUsername .Values.global.imagePassword -}}
imagePullSecrets:
- name: turbocred
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
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
{{- $scope := dict "repository" .Values.image.repository "tag" .Values.image.tag "component" .Chart.Name "global" .Values.global}}
{{- include "imageString" $scope }}
{{- end -}}

{{/*
Builds the image name string for a Turbonomic image.

Scope should have the following values:
- repository
- tag
- component
- global.repository
- global.tag

The global values will be used if both repository="turbonomic" and tag="latest"
*/}}
{{- define "imageString" -}}
{{- $repositoryName := .repository -}}
{{- $tag := .tag | toString -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .global }}
    {{- if and .global.repository .global.tag (eq $repositoryName "turbonomic") (eq $tag "latest") -}}
        {{- $repositoryName = .global.repository -}}
        {{- $tag = .global.tag -}}
    {{- end -}}
{{- end -}}

{{- printf "%s/%s:%s" $repositoryName .component $tag -}}

{{- end -}}

{{/*
Return the serviceAccountName
*/}}
{{- define "serviceAccountName" -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .Values.global }}
    {{- if .Values.serviceAccountName }}
        {{- printf "%s" .Values.serviceAccountName -}}
    {{- else if or .Values.global.serviceAccountName  -}}
        {{- printf "%s" .Values.global.serviceAccountName -}}
    {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the pullPolicy
*/}}
{{- define "pullPolicy" -}}
{{ $scope := dict "pullPolicy" .Values.image.pullPolicy "global" .Values.global }}
{{- include "pullPolicyString" $scope }}
{{- end -}}

{{/*
Returns the pull policy string.

Scope should have the following values:
- pullPolicy
- global.pullPolicy

The global value will be used if pullPolicy="IfNotPresent"
*/}}
{{- define "pullPolicyString" -}}
{{- $pullPolicy := .pullPolicy -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .global }}
    {{- if and .global.pullPolicy (eq $pullPolicy "IfNotPresent") -}}
        {{- $pullPolicy = .global.pullPolicy -}}
    {{- end -}}
{{- end -}}

{{- $pullPolicy -}}

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

{{/*
Return the db secret name
*/}}
{{- define "dbSecretName" -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .Values.dbSecretName }}
    {{- printf "%s" .Values.dbSecretName -}}
{{- else -}}
    {{- if and .Values.global .Values.global.dbSecretName }}
        {{- printf "%s" .Values.global.dbSecretName -}}
    {{- end -}}
{{- end -}}
{{- end -}}

{{/*

Expose a service with Skupper. Use inside an annotations block
*/}}
{{- define "skupperExpose" -}}
skupper.io/proxy: {{ .proxy }}
{{- if .address }}
skupper.io/address: {{ .address }}
{{- end -}}
{{- end }}

{{/*
Return kube OAuth secrets volume configuration
*/}}
{{ define "kubeAuthSecretsVolume" }}
- name: kube-auth-secrets
  secret:
    secretName: {{ .Chart.Name }}-auth-secrets
    optional: true
{{ end }}

{{/*
Return kube OAuth secret volume mount configuration
*/}}
{{ define "kubeAuthSecretsVolumeMount" }}
- mountPath: /etc/config/kubeAuthSecrets
  name: kube-auth-secrets
  readOnly: true
{{ end }}