{{- define "argo-cd.selectorLabels" -}}
{{- if .name -}}
app.kubernetes.io/name: {{ include "argo-cd.name" .context }}-{{ .name }}
{{- end -}}
{{- $legacySelectorNames := list "application-controller" "applicationset-controller" "notifications-controller" "repo-server" "server" -}}
{{- if not (has .name $legacySelectorNames) }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}
{{- if .component }}
app.kubernetes.io/component: {{ .component }}
{{- end }}
{{- end }}