{{/*Runik Platform
Copyright (C) 2023 namenmalkv@gmail.com
SPDX-License-Identifier: AGPL-3.0-only

Tarot Trinket Helper Templates
Dynamic workflow composition using mystical card-based architecture
*/}}

{{/*
Common labels with runik-specific additions
*/}}
{{- define "tarot.labels" -}}
{{ include "common.labels" . }}
runik.ing/component: tarot
runik.ing/type: trinket
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "tarot.serviceAccountName" -}}
{{- if .Values.tarot.serviceAccount.name }}
{{- .Values.tarot.serviceAccount.name }}
{{- else if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "common.name" . }}
{{- end }}
{{- end }}
