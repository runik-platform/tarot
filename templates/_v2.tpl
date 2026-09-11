{{/*Runik Platform
Copyright (C) 2023 namenmalkv@gmail.com
SPDX-License-Identifier: AGPL-3.0-only

Tarot v2 composes book/chapter defaults with the spell-owned invocation.  The
helpers in this file intentionally own all workflow semantics; librarian only
delivers the three existing values contexts.
*/}}

{{/* Resolve Tarot-owned configuration with book < chapter < spell precedence. */}}
{{- define "tarot.v2.effectiveConfig" -}}
{{- $root := . -}}
{{- $effective := deepCopy (default dict $root.Values.tarotDefaults) -}}
{{- with $root.Values.spellbook.tarot -}}
  {{- $_ := mergeOverwrite $effective (deepCopy .) -}}
{{- end -}}
{{- with $root.Values.chapter.tarot -}}
  {{- $_ := mergeOverwrite $effective (deepCopy .) -}}
{{- end -}}
{{- with $root.Values.tarot -}}
  {{- $_ := mergeOverwrite $effective (deepCopy .) -}}
{{- end -}}

{{/* Cards are scoped to Tarot and may carry either a native executable
     definition or a reference to an Argo template. */}}
{{- $cards := dict -}}
{{- if and $root.Values.spellbook $root.Values.spellbook.tarot $root.Values.spellbook.tarot.cards -}}
  {{- $_ := mergeOverwrite $cards (deepCopy $root.Values.spellbook.tarot.cards) -}}
{{- end -}}
{{- if and $root.Values.chapter $root.Values.chapter.tarot $root.Values.chapter.tarot.cards -}}
  {{- $_ := mergeOverwrite $cards (deepCopy $root.Values.chapter.tarot.cards) -}}
{{- end -}}
{{- if and $root.Values.tarot $root.Values.tarot.cards -}}
  {{- $_ := mergeOverwrite $cards (deepCopy $root.Values.tarot.cards) -}}
{{- end -}}
{{- $_ := set $effective "cards" $cards -}}
{{- $effective | toJson -}}
{{- end -}}

{{/* A value may describe names as a string list or as a keyed contract map. */}}
{{- define "tarot.v2.contractNames" -}}
{{- $definition := . | default (list) -}}
{{- $names := list -}}
{{- if kindIs "map" $definition -}}
  {{- range $name, $_ := $definition -}}
    {{- $names = append $names $name -}}
  {{- end -}}
{{- else if kindIs "slice" $definition -}}
  {{- range $definition -}}
    {{- if kindIs "string" . -}}
      {{- $names = append $names . -}}
    {{- else if and (kindIs "map" .) (hasKey . "name") -}}
      {{- $names = append $names .name -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $names | toJson -}}
{{- end -}}

{{- define "tarot.v2.cardContract" -}}
{{- $card := . -}}
{{- $contract := dict -}}
{{- if $card.contract -}}
  {{- $contract = deepCopy $card.contract -}}
{{- else -}}
  {{- $contract = dict "inputs" (default dict $card.inputs) "outputs" (default dict $card.outputs) -}}
{{- end -}}
{{- if not $contract.inputs -}}{{- $_ := set $contract "inputs" dict -}}{{- end -}}
{{- if not $contract.outputs -}}{{- $_ := set $contract "outputs" dict -}}{{- end -}}
{{- $contract | toJson -}}
{{- end -}}

{{/* A tarot-reading lexicon entry is itself the resource reference. */}}
{{- define "tarot.v2.readingCoordinates" -}}
{{- $reading := . -}}
{{- if not $reading.name -}}
  {{- fail "tarot-reading requires name (normally injected from its lexicon key)" -}}
{{- end -}}
{{- if $reading.reference -}}
  {{- fail (printf "tarot-reading '%s' uses removed nested reference; publish scope, namespace and template directly on the lexicon entry" $reading.name) -}}
{{- end -}}
{{- $scope := default "namespace" $reading.scope -}}
{{- if not (has $scope (list "namespace" "cluster")) -}}
  {{- fail (printf "tarot-reading '%s' has unsupported scope '%s'; use namespace or cluster" $reading.name $scope) -}}
{{- end -}}
{{- $namespace := "" -}}
{{- if eq $scope "namespace" -}}
  {{- $namespace = default $reading.name $reading.namespace -}}
{{- end -}}
{{- dict
      "name" $reading.name
      "scope" $scope
      "namespace" $namespace
      "template" (default "main" $reading.template)
    | toJson -}}
{{- end -}}

{{/* Locate publications that refer to the WorkflowTemplate rendered here.
     Librarian only injects the consolidated lexicon; Tarot owns this check. */}}
{{- define "tarot.v2.selfPublications" -}}
{{- $root := . -}}
{{- $resourceName := include "common.name" $root -}}
{{- $publications := list -}}
{{- range $key, $definition := (default dict $root.Values.lexicon) -}}
  {{- if and (kindIs "map" $definition) (eq (default "" $definition.type) "tarot-reading") -}}
    {{- $publication := deepCopy $definition -}}
    {{- if not $publication.name }}{{- $_ := set $publication "name" $key -}}{{- end -}}
    {{- if eq $publication.name $resourceName -}}
      {{- $publications = append $publications $publication -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $publications | toJson -}}
{{- end -}}

{{/* For a published reading the lexicon contract is the public source of
     truth. Unpublished/local readings continue to declare reading.inputs. */}}
{{- define "tarot.v2.applyPublicationContract" -}}
{{- $root := index . 0 -}}
{{- $reading := deepCopy (index . 1) -}}
{{- $publications := include "tarot.v2.selfPublications" $root | fromJsonArray -}}
{{- if gt (len $publications) 1 -}}
  {{- fail (printf "Tarot WorkflowTemplate '%s' has multiple tarot-reading publications" (include "common.name" $root)) -}}
{{- end -}}
{{- if eq (len $publications) 1 -}}
  {{- $publication := index $publications 0 -}}
  {{- $coordinates := include "tarot.v2.readingCoordinates" $publication | fromJson -}}
  {{- if ne $coordinates.scope "namespace" -}}
    {{- fail (printf "tarot-reading '%s' publishes scope '%s', but composed readings render a namespaced WorkflowTemplate" $publication.name $coordinates.scope) -}}
  {{- end -}}
  {{- if ne $coordinates.namespace $root.Release.Namespace -}}
    {{- fail (printf "tarot-reading '%s' publishes namespace '%s', but Tarot renders it in '%s'" $publication.name $coordinates.namespace $root.Release.Namespace) -}}
  {{- end -}}
  {{- if ne $coordinates.template "main" -}}
    {{- fail (printf "tarot-reading '%s' publishes template '%s', but Tarot reading entrypoint is 'main'" $publication.name $coordinates.template) -}}
  {{- end -}}
  {{- if $reading.inputs -}}
    {{- fail (printf "Published tarot-reading '%s' must declare its inputs only in appendix.lexicon.contract" $publication.name) -}}
  {{- end -}}
  {{- $contractInputs := default dict (dig "contract" "inputs" dict $publication) -}}
  {{- if not (kindIs "map" $contractInputs) -}}
    {{- fail (printf "tarot-reading '%s' contract.inputs must be a map" $publication.name) -}}
  {{- end -}}
  {{- $_ := set $reading "inputs" (deepCopy $contractInputs) -}}
  {{- $_ := set $reading "_published" true -}}
{{- end -}}
{{- $reading | toJson -}}
{{- end -}}

{{/* Compose extensions into a copied reading and rewire only their boundaries. */}}
{{- define "tarot.v2.composeReading" -}}
{{- $effective := . -}}
{{- if and $effective.extend (not (kindIs "map" $effective.extend)) -}}
  {{- fail "tarot.extend must be a map keyed by extension point" -}}
{{- end -}}
{{- if and $effective.reading $effective.reading.selector $effective.extend -}}
  {{- fail "tarot.extend cannot be combined with a selected reading" -}}
{{- end -}}
{{- if and $effective.reading $effective.reading.selector $effective.reading.cards -}}
  {{- fail "tarot.reading must define either selector or cards, not both" -}}
{{- end -}}
{{- $reading := dict -}}
{{- if and $effective.reading (not $effective.reading.selector) -}}
  {{- $reading = deepCopy $effective.reading -}}
{{- else if $effective.defaultReading -}}
  {{- $reading = deepCopy $effective.defaultReading -}}
{{- else -}}
  {{- fail "Tarot v2 requires tarot.reading or an effective tarot.defaultReading" -}}
{{- end -}}
{{- if not $reading.cards -}}
  {{- fail "The effective Tarot reading must define at least one card" -}}
{{- end -}}
{{- if not (kindIs "map" $reading.cards) -}}
  {{- fail "The effective Tarot reading cards must be a map" -}}
{{- end -}}
{{- $readingCards := deepCopy $reading.cards -}}
{{- $points := default dict $reading.extensionPoints -}}

{{- range $pointName, $extension := (default dict $effective.extend) -}}
  {{- if not (hasKey $points $pointName) -}}
    {{- fail (printf "Tarot extension point '%s' does not exist" $pointName) -}}
  {{- end -}}
  {{- if not (kindIs "map" $extension) -}}
    {{- fail (printf "Tarot extension point '%s' must be a map" $pointName) -}}
  {{- end -}}
  {{- if not $extension.cards -}}
    {{- fail (printf "Tarot extension point '%s' must contain cards" $pointName) -}}
  {{- end -}}
  {{- if not (kindIs "map" $extension.cards) -}}
    {{- fail (printf "Tarot extension point '%s' cards must be a map" $pointName) -}}
  {{- end -}}
  {{- $point := index $points $pointName -}}
  {{- $extensionNames := keys $extension.cards | sortAlpha -}}
  {{- range $cardName := $extensionNames -}}
    {{- if hasKey $readingCards $cardName -}}
      {{- fail (printf "Tarot extension '%s' cannot overwrite card '%s'" $pointName $cardName) -}}
    {{- end -}}
  {{- end -}}

  {{/* Roots have no dependency on another job in this extension. */}}
  {{- $roots := list -}}
  {{- $dependedOn := dict -}}
  {{- range $cardName := $extensionNames -}}
    {{- $card := deepCopy (index $extension.cards $cardName) -}}
    {{- $hasInternalDependency := false -}}
    {{- range (default list $card.depends) -}}
      {{- if has . $extensionNames -}}
        {{- $hasInternalDependency = true -}}
        {{- $_ := set $dependedOn . true -}}
      {{- end -}}
    {{- end -}}
    {{- if not $hasInternalDependency -}}
      {{- $roots = append $roots $cardName -}}
    {{- end -}}
    {{- $_ := set $readingCards $cardName $card -}}
  {{- end -}}

  {{- $terminals := list -}}
  {{- range $cardName := $extensionNames -}}
    {{- if not (hasKey $dependedOn $cardName) -}}
      {{- $terminals = append $terminals $cardName -}}
    {{- end -}}
  {{- end -}}

  {{- range $cardName := $roots -}}
    {{- $card := index $readingCards $cardName -}}
    {{- $dependencies := deepCopy (default list $card.depends) -}}
    {{- range (default list $point.after) -}}
      {{- if not (has . $dependencies) -}}
        {{- $dependencies = append $dependencies . -}}
      {{- end -}}
    {{- end -}}
    {{- $_ := set $card "depends" $dependencies -}}
  {{- end -}}

  {{- range $beforeName := (default list $point.before) -}}
    {{- if not (hasKey $readingCards $beforeName) -}}
      {{- fail (printf "Tarot extension point '%s' references unknown before card '%s'" $pointName $beforeName) -}}
    {{- end -}}
    {{- $beforeCard := index $readingCards $beforeName -}}
    {{- $dependencies := list -}}
    {{- range (default list $beforeCard.depends) -}}
      {{- if not (has . (default list $point.after)) -}}
        {{- $dependencies = append $dependencies . -}}
      {{- end -}}
    {{- end -}}
    {{- range $terminals -}}
      {{- if not (has . $dependencies) -}}
        {{- $dependencies = append $dependencies . -}}
      {{- end -}}
    {{- end -}}
    {{- $_ := set $beforeCard "depends" $dependencies -}}
  {{- end -}}
{{- end -}}
{{- $_ := set $reading "cards" $readingCards -}}
{{- $reading | toJson -}}
{{- end -}}

{{/* Fail on a dependency cycle. The current recursion path is sufficient. */}}
{{- define "tarot.v2.validateAcyclicFrom" -}}
{{- $cards := index . 0 -}}
{{- $cardName := index . 1 -}}
{{- $path := index . 2 -}}
{{- if has $cardName $path -}}
  {{- fail (printf "Tarot reading contains a dependency cycle: %s -> %s" (join " -> " $path) $cardName) -}}
{{- end -}}
{{- $nextPath := append $path $cardName -}}
{{- $card := index $cards $cardName -}}
{{- range (default list $card.depends) -}}
  {{- include "tarot.v2.validateAcyclicFrom" (list $cards . $nextPath) -}}
{{- end -}}
{{- end -}}

{{- define "tarot.v2.cardForJob" -}}
{{- $effective := index . 0 -}}
{{- $jobName := index . 1 -}}
{{- $job := index . 2 -}}
{{- if $job.uses -}}
  {{- if not (hasKey $effective.cards $job.uses) -}}
    {{- fail (printf "Tarot reading card '%s' uses unknown card '%s'" $jobName $job.uses) -}}
  {{- end -}}
  {{- $card := deepCopy (index $effective.cards $job.uses) -}}
  {{- $overrides := omit (deepCopy $job) "uses" "depends" "with" "artifacts" "when" "hooks" "continueOn" -}}
  {{- $_ := mergeOverwrite $card $overrides -}}
  {{- $card | toJson -}}
{{- else -}}
  {{- $job | toJson -}}
{{- end -}}
{{- end -}}

{{- define "tarot.v2.validate" -}}
{{- $effective := index . 0 -}}
{{- $reading := index . 1 -}}
{{- $jobs := $reading.cards -}}
{{- range $reservedName := list "runik-tarot-on-exit" "runik-tarot-on-exit-card" -}}
  {{- if hasKey $jobs $reservedName -}}
    {{- fail (printf "Tarot reading card name '%s' is reserved for lifecycle handling" $reservedName) -}}
  {{- end -}}
{{- end -}}
{{- if and $effective.with (not (kindIs "map" $effective.with)) -}}
  {{- fail "tarot.with must be a map" -}}
{{- end -}}
{{- $executionMode := default "dag" $effective.executionMode -}}
{{- if not (has $executionMode (list "dag" "containerSet")) -}}
  {{- fail (printf "Tarot v2 executionMode '%s' is not supported; use dag or containerSet" $executionMode) -}}
{{- end -}}
{{- $workflowInputDefinitions := dict -}}
{{- if $reading.inputs -}}
  {{- $workflowInputDefinitions = default dict $reading.inputs.parameters -}}
{{- end -}}
{{- $workflowInputs := include "tarot.v2.contractNames" $workflowInputDefinitions | fromJsonArray -}}

{{- range $name, $definition := $workflowInputDefinitions -}}
  {{- if and (kindIs "map" $definition) $definition.required (not $reading._published) (not $definition.runtime) (not (hasKey (default dict $effective.with) $name)) (not (hasKey $definition "default")) (not (hasKey $definition "value")) -}}
    {{- fail (printf "Required Tarot reading input '%s' was not provided in tarot.with" $name) -}}
  {{- end -}}
{{- end -}}
{{- range $name, $_ := (default dict $effective.with) -}}
  {{- if not (has $name $workflowInputs) -}}
    {{- fail (printf "tarot.with provides unknown reading input '%s'" $name) -}}
  {{- end -}}
{{- end -}}

{{- range $jobName, $job := $jobs -}}
  {{- if not (kindIs "map" $job) -}}
    {{- fail (printf "Tarot reading card '%s' must be a map" $jobName) -}}
  {{- end -}}
  {{- if and $job.depends (not (kindIs "slice" $job.depends)) -}}
    {{- fail (printf "Tarot reading card '%s' depends must be a list" $jobName) -}}
  {{- end -}}
  {{- range $field := list "secrets" "configMaps" "volumes" "envs" -}}
    {{- if hasKey $job $field -}}
      {{- fail (printf "Tarot reading card '%s' cannot declare %s; use tarot.%s and native container references" $jobName $field $field) -}}
    {{- end -}}
  {{- end -}}
  {{- $hasImplementation := or $job.container $job.script $job.resource $job.suspend -}}
  {{- if and $job.uses $hasImplementation -}}
    {{- fail (printf "Tarot reading card '%s' must use either a reusable card or an inline implementation, not both" $jobName) -}}
  {{- end -}}
  {{- if and (not $job.uses) (not $hasImplementation) -}}
    {{- fail (printf "Tarot reading card '%s' requires 'uses' or an inline implementation" $jobName) -}}
  {{- end -}}
  {{- $card := include "tarot.v2.cardForJob" (list $effective $jobName $job) | fromJson -}}
  {{- $implementationCount := 0 -}}
  {{- range $field := list "ref" "container" "script" "resource" "suspend" -}}
    {{- if hasKey $card $field -}}{{- $implementationCount = add1 $implementationCount -}}{{- end -}}
  {{- end -}}
  {{- if ne $implementationCount 1 -}}
    {{- fail (printf "Tarot reading card '%s' must resolve to exactly one implementation" $jobName) -}}
  {{- end -}}
  {{- range $field := list "secrets" "configMaps" "volumes" "envs" -}}
    {{- if hasKey $card $field -}}
      {{- fail (printf "Tarot card '%s' cannot declare %s; use tarot.%s and native container references" (default $jobName $job.uses) $field $field) -}}
    {{- end -}}
  {{- end -}}
  {{- if and $card.ref (or $card.retryStrategy $card.timeout $card.activeDeadlineSeconds $card.metadata) -}}
    {{- fail (printf "Tarot card '%s' references an external template; retry, timeout and metadata must be defined by that template" (default $jobName $job.uses)) -}}
  {{- end -}}
  {{- if eq $executionMode "containerSet" -}}
    {{- if $card.ref -}}
      {{- fail (printf "Tarot containerSet card '%s' resolves to a template reference; use a card with a native container" $jobName) -}}
    {{- end -}}
    {{- if not $card.container -}}
      {{- fail (printf "Tarot containerSet card '%s' requires a native container" $jobName) -}}
    {{- end -}}
    {{- if $job.when -}}
      {{- fail (printf "Tarot containerSet card '%s' cannot use when" $jobName) -}}
    {{- end -}}
    {{- if or $job.with $job.artifacts -}}
      {{- fail (printf "Tarot containerSet card '%s' cannot use template arguments" $jobName) -}}
    {{- end -}}
    {{- if or $card.retryStrategy $card.timeout $card.activeDeadlineSeconds -}}
      {{- fail (printf "Tarot containerSet card '%s' cannot use per-card retry or timeout; those policies belong to the reading because all cards share one pod" $jobName) -}}
    {{- end -}}
  {{- end -}}
  {{- range (default list $job.depends) -}}
    {{- if not (hasKey $jobs .) -}}
      {{- fail (printf "Tarot reading card '%s' depends on unknown card '%s'" $jobName .) -}}
    {{- end -}}
  {{- end -}}

  {{- if $job.uses -}}
    {{- if and $card.ref (or (not $card.ref.kind) (not $card.ref.name) (not $card.ref.template)) -}}
      {{- fail (printf "Tarot card '%s' ref requires kind, name and template" $job.uses) -}}
    {{- end -}}
    {{- if and $card.ref (not (has $card.ref.kind (list "WorkflowTemplate" "ClusterWorkflowTemplate"))) -}}
      {{- fail (printf "Tarot card '%s' has unsupported ref.kind '%s'" $job.uses $card.ref.kind) -}}
    {{- end -}}
  {{- end -}}
  {{- $contract := include "tarot.v2.cardContract" $card | fromJson -}}
  {{- if and (eq $executionMode "containerSet") (or $contract.inputs.parameters $contract.inputs.artifacts $contract.outputs.parameters $contract.outputs.artifacts) -}}
    {{- fail (printf "Tarot containerSet card '%s' contracts may declare secrets only; containers exchange data through shared volumes" $jobName) -}}
  {{- end -}}
  {{- $acceptedParameters := include "tarot.v2.contractNames" (default list $contract.inputs.parameters) | fromJsonArray -}}
  {{- range $parameterName, $_ := (default dict $job.with) -}}
    {{- if not (has $parameterName $acceptedParameters) -}}
      {{- fail (printf "Tarot reading card '%s' provides parameter '%s' not accepted by card '%s'" $jobName $parameterName (default "inline" $job.uses)) -}}
    {{- end -}}
  {{- end -}}
  {{- if kindIs "map" $contract.inputs.parameters -}}
    {{- range $parameterName, $parameter := $contract.inputs.parameters -}}
      {{- if and (kindIs "map" $parameter) $parameter.required (not (hasKey (default dict $job.with) $parameterName)) (not (hasKey $parameter "default")) (not (hasKey $parameter "value")) -}}
        {{- fail (printf "Tarot reading card '%s' is missing required parameter '%s'" $jobName $parameterName) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- $acceptedArtifacts := include "tarot.v2.contractNames" (default list $contract.inputs.artifacts) | fromJsonArray -}}
  {{- range $artifactName, $_ := (default dict $job.artifacts) -}}
    {{- if not (has $artifactName $acceptedArtifacts) -}}
      {{- fail (printf "Tarot reading card '%s' provides artifact '%s' not accepted by card '%s'" $jobName $artifactName (default "inline" $job.uses)) -}}
    {{- end -}}
  {{- end -}}
  {{- $requiredSecrets := include "tarot.v2.contractNames" (default list $contract.inputs.secrets) | fromJsonArray -}}
  {{- range $secretName := $requiredSecrets -}}
    {{- if not (hasKey (default dict $effective.secrets) $secretName) -}}
      {{- fail (printf "Tarot reading card '%s' requires unbound secret '%s'" $jobName $secretName) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- range $jobName, $_ := $jobs -}}
  {{- include "tarot.v2.validateAcyclicFrom" (list $jobs $jobName (list)) -}}
{{- end -}}
{{- with $reading.onExit -}}
  {{- if not (kindIs "map" .) -}}
    {{- fail "tarot.reading.onExit must be a card execution" -}}
  {{- end -}}
  {{- $exitJob := . -}}
  {{- range $field := list "depends" "when" "hooks" "continueOn" "artifacts" -}}
    {{- if hasKey $exitJob $field -}}
      {{- fail (printf "tarot.reading.onExit cannot declare %s" $field) -}}
    {{- end -}}
  {{- end -}}
  {{- $hasImplementation := or $exitJob.container $exitJob.script $exitJob.resource $exitJob.suspend -}}
  {{- if and $exitJob.uses $hasImplementation -}}
    {{- fail "tarot.reading.onExit must use either a reusable card or an inline implementation, not both" -}}
  {{- end -}}
  {{- if and (not $exitJob.uses) (not $hasImplementation) -}}
    {{- fail "tarot.reading.onExit requires 'uses' or an inline implementation" -}}
  {{- end -}}
  {{- $exitCard := include "tarot.v2.cardForJob" (list $effective "onExit" $exitJob) | fromJson -}}
  {{- $implementationCount := 0 -}}
  {{- range $field := list "ref" "container" "script" "resource" "suspend" -}}
    {{- if hasKey $exitCard $field -}}{{- $implementationCount = add1 $implementationCount -}}{{- end -}}
  {{- end -}}
  {{- if ne $implementationCount 1 -}}
    {{- fail "tarot.reading.onExit must resolve to exactly one implementation" -}}
  {{- end -}}
  {{- if and $exitCard.ref (or (not $exitCard.ref.kind) (not $exitCard.ref.name) (not $exitCard.ref.template)) -}}
    {{- fail "tarot.reading.onExit ref requires kind, name and template" -}}
  {{- end -}}
  {{- if and $exitCard.ref (not (has $exitCard.ref.kind (list "WorkflowTemplate" "ClusterWorkflowTemplate"))) -}}
    {{- fail (printf "tarot.reading.onExit has unsupported ref.kind '%s'" $exitCard.ref.kind) -}}
  {{- end -}}
  {{- if and $exitCard.ref (or $exitCard.retryStrategy $exitCard.timeout $exitCard.activeDeadlineSeconds $exitCard.metadata) -}}
    {{- fail "tarot.reading.onExit references an external template; retry, timeout and metadata must be defined by that template" -}}
  {{- end -}}
  {{- $exitContract := include "tarot.v2.cardContract" $exitCard | fromJson -}}
  {{- if $exitContract.inputs.artifacts -}}
    {{- fail "tarot.reading.onExit does not accept input artifacts" -}}
  {{- end -}}
  {{- $acceptedParameters := include "tarot.v2.contractNames" (default list $exitContract.inputs.parameters) | fromJsonArray -}}
  {{- range $parameterName, $_ := (default dict $exitJob.with) -}}
    {{- if not (has $parameterName $acceptedParameters) -}}
      {{- fail (printf "tarot.reading.onExit provides parameter '%s' not accepted by its card" $parameterName) -}}
    {{- end -}}
  {{- end -}}
  {{- if kindIs "map" $exitContract.inputs.parameters -}}
    {{- range $parameterName, $parameter := $exitContract.inputs.parameters -}}
      {{- if and (kindIs "map" $parameter) $parameter.required (not (hasKey (default dict $exitJob.with) $parameterName)) (not (hasKey $parameter "default")) (not (hasKey $parameter "value")) -}}
        {{- fail (printf "tarot.reading.onExit is missing required parameter '%s'" $parameterName) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- $requiredSecrets := include "tarot.v2.contractNames" (default list $exitContract.inputs.secrets) | fromJsonArray -}}
  {{- range $secretName := $requiredSecrets -}}
    {{- if not (hasKey (default dict $effective.secrets) $secretName) -}}
      {{- fail (printf "tarot.reading.onExit requires unbound secret '%s'" $secretName) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/* Render shorthand or native Argo input/output declarations. */}}
{{- define "tarot.v2.renderNamedDefinitions" -}}
{{- $definitions := . -}}
{{- if kindIs "map" $definitions -}}
  {{- range $name, $definition := $definitions }}
- name: {{ $name }}
    {{- if kindIs "map" $definition }}
      {{- $nativeDefinition := omit $definition "required" "runtime" "default" -}}
      {{- if $nativeDefinition }}
      {{- $nativeDefinition | toYaml | nindent 2 }}
      {{- end }}
      {{- if and (hasKey $definition "default") (not (hasKey $definition "value")) }}
  value: {{ $definition.default | quote }}
      {{- end }}
    {{- end }}
  {{- end -}}
{{- else if kindIs "slice" $definitions -}}
  {{- range $definitions }}
    {{- if kindIs "string" . }}
- name: {{ . }}
    {{- else }}
- {{ . | toYaml | nindent 2 | trim }}
    {{- end }}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "tarot.v2.renderTemplateIO" -}}
{{- $definition := . -}}
{{- if or $definition.parameters $definition.artifacts }}
  {{- if $definition.parameters }}
parameters:
{{ include "tarot.v2.renderNamedDefinitions" $definition.parameters | nindent 2 }}
  {{- end }}
  {{- if $definition.artifacts }}
artifacts:
{{ include "tarot.v2.renderNamedDefinitions" $definition.artifacts | nindent 2 }}
  {{- end }}
{{- end -}}
{{- end -}}

{{/* Locate the unique dependency that produces an artifact required by a job. */}}
{{- define "tarot.v2.artifactProducer" -}}
{{- $effective := index . 0 -}}
{{- $jobs := index . 1 -}}
{{- $jobName := index . 2 -}}
{{- $artifactName := index . 3 -}}
{{- $job := index $jobs $jobName -}}
{{- $producers := list -}}
{{- range $dependencyName := (default list $job.depends) -}}
  {{- $dependency := index $jobs $dependencyName -}}
  {{- $card := include "tarot.v2.cardForJob" (list $effective $dependencyName $dependency) | fromJson -}}
  {{- $contract := include "tarot.v2.cardContract" $card | fromJson -}}
  {{- $outputs := include "tarot.v2.contractNames" (default list $contract.outputs.artifacts) | fromJsonArray -}}
  {{- if has $artifactName $outputs -}}
    {{- $producers = append $producers $dependencyName -}}
  {{- end -}}
{{- end -}}
{{- if eq (len $producers) 0 -}}
  {{- fail (printf "Tarot reading card '%s' requires artifact '%s' but none of its dependencies produces it" $jobName $artifactName) -}}
{{- else if gt (len $producers) 1 -}}
  {{- fail (printf "Tarot reading card '%s' has multiple producers for artifact '%s': %s" $jobName $artifactName (join ", " $producers)) -}}
{{- else -}}
  {{- index $producers 0 -}}
{{- end -}}
{{- end -}}

{{- define "tarot.v2.renderTaskArguments" -}}
{{- $effective := index . 0 -}}
{{- $reading := index . 1 -}}
{{- $jobName := index . 2 -}}
{{- $job := index $reading.cards $jobName -}}
{{- $card := include "tarot.v2.cardForJob" (list $effective $jobName $job) | fromJson -}}
{{- $contract := include "tarot.v2.cardContract" $card | fromJson -}}
{{- $artifactInputs := include "tarot.v2.contractNames" (default list $contract.inputs.artifacts) | fromJsonArray -}}
{{- if or $job.with (gt (len $artifactInputs) 0) $job.artifacts }}
arguments:
  {{- if $job.with }}
  parameters:
    {{- range $name, $value := $job.with }}
    - name: {{ $name }}
      value: {{ $value | quote }}
    {{- end }}
  {{- end }}
  {{- if or (gt (len $artifactInputs) 0) $job.artifacts }}
  artifacts:
    {{- range $artifactName := $artifactInputs }}
      {{- $explicit := get (default dict $job.artifacts) $artifactName }}
    - name: {{ $artifactName }}
      {{- if $explicit }}
        {{- if kindIs "string" $explicit }}
      from: {{ $explicit | quote }}
        {{- else }}
{{ $explicit | toYaml | nindent 6 }}
        {{- end }}
      {{- else }}
        {{- $producer := include "tarot.v2.artifactProducer" (list $effective $reading.cards $jobName $artifactName) }}
      from: {{ printf "{{tasks.%s.outputs.artifacts.%s}}" $producer $artifactName | quote }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end -}}
{{- end -}}

{{- define "tarot.v2.renderJobTemplate" -}}
{{- $effective := index . 0 -}}
{{- $jobName := index . 1 -}}
{{- $job := index . 2 -}}
{{- $card := include "tarot.v2.cardForJob" (list $effective $jobName $job) | fromJson -}}
{{- if not $card.ref }}
- name: {{ $jobName }}
  {{- $contract := default dict $card.contract }}
  {{- $contractInputs := default dict $contract.inputs }}
  {{- $contractOutputs := default dict $contract.outputs }}
  {{- $inputs := default $contractInputs $card.inputs }}
  {{- $outputs := default $contractOutputs $card.outputs }}
  {{- if or $inputs.parameters $inputs.artifacts }}
  inputs:
{{ include "tarot.v2.renderTemplateIO" $inputs | nindent 4 }}
  {{- end }}
  {{- if or $outputs.parameters $outputs.artifacts }}
  outputs:
{{ include "tarot.v2.renderTemplateIO" $outputs | nindent 4 }}
  {{- end }}
  {{- if $card.container }}
  container:
{{ $card.container | toYaml | nindent 4 }}
  {{- else if $card.script }}
  script:
{{ $card.script | toYaml | nindent 4 }}
  {{- else if $card.resource }}
  resource:
{{ $card.resource | toYaml | nindent 4 }}
  {{- else if $card.suspend }}
  suspend:
{{ $card.suspend | toYaml | nindent 4 }}
  {{- end }}
  {{- with $card.retryStrategy }}
  retryStrategy:
{{ . | toYaml | nindent 4 }}
  {{- end }}
  {{- if or $card.timeout $card.activeDeadlineSeconds }}
  activeDeadlineSeconds: {{ default $card.activeDeadlineSeconds $card.timeout }}
  {{- end }}
  {{- with $card.metadata }}
  metadata:
{{ . | toYaml | nindent 4 }}
  {{- end }}
{{- end -}}
{{- end -}}

{{- define "tarot.v2.resolveReadingReference" -}}
{{- $root := index . 0 -}}
{{- $selector := index . 1 -}}
{{- if not (kindIs "map" $selector) -}}
  {{- fail "tarot.reading.selector must be a map" -}}
{{- end -}}
{{- if eq (len $selector) 0 -}}
  {{- fail "tarot.reading.selector cannot be empty" -}}
{{- end -}}
{{- $chapterName := default "" $root.Values.chapter.name -}}
{{- $readings := get (include "runic-system.runic-indexer" (list $root.Values.lexicon $selector "tarot-reading" $chapterName) | fromJson) "results" -}}
{{- if eq (len $readings) 0 -}}
  {{- fail "tarot.reading.selector matched no tarot-reading" -}}
{{- else if gt (len $readings) 1 -}}
  {{- fail "tarot.reading.selector matched multiple tarot-readings" -}}
{{- end -}}
{{- $reading := index $readings 0 -}}
{{- $labels := default dict $reading.labels -}}
{{- $exactMatch := true -}}
{{- range $key, $value := $selector -}}
  {{- if and (hasKey $labels $key) (eq (index $labels $key) $value) -}}
  {{- else if and (hasKey $reading $key) (eq (toString (index $reading $key)) (toString $value)) -}}
  {{- else -}}
    {{- $exactMatch = false -}}
  {{- end -}}
{{- end -}}
{{- if not $exactMatch -}}
  {{- fail "tarot.reading.selector matched only a lexicon default; named readings require an exact selector match" -}}
{{- end -}}
{{- $coordinates := include "tarot.v2.readingCoordinates" $reading | fromJson -}}
{{- $reading | toJson -}}
{{- end -}}

{{- define "tarot.v2.renderSelectedReading" -}}
{{- $root := index . 0 -}}
{{- $effective := index . 1 -}}
{{- $published := include "tarot.v2.resolveReadingReference" (list $root $effective.reading.selector) | fromJson -}}
{{- $reference := include "tarot.v2.readingCoordinates" $published | fromJson -}}
{{- if and (eq $reference.scope "namespace") (ne $reference.namespace $root.Release.Namespace) -}}
  {{- fail (printf "tarot-reading '%s' references namespace '%s'; namespaced readings can only be selected from '%s'" $published.name $reference.namespace $root.Release.Namespace) -}}
{{- end -}}
{{- $parameterDefinitions := default dict (dig "contract" "inputs" "parameters" dict $published) -}}
{{- $parameterNames := include "tarot.v2.contractNames" $parameterDefinitions | fromJsonArray -}}
{{- range $name, $_ := (default dict $effective.with) -}}
  {{- if not (has $name $parameterNames) -}}
    {{- fail (printf "tarot.with provides unknown selected-reading input '%s'" $name) -}}
  {{- end -}}
{{- end -}}
{{- $workflowParameters := list -}}
{{- $taskParameters := list -}}
{{- range $name := $parameterNames -}}
  {{- $workflowParameter := dict "name" $name -}}
  {{- if hasKey (default dict $effective.with) $name -}}
    {{- $_ := set $workflowParameter "value" (index $effective.with $name) -}}
  {{- else if and (kindIs "map" $parameterDefinitions) (hasKey $parameterDefinitions $name) -}}
    {{- $definition := index $parameterDefinitions $name -}}
    {{- if and (kindIs "map" $definition) (hasKey $definition "default") -}}
      {{- $_ := set $workflowParameter "value" $definition.default -}}
    {{- else if and (kindIs "map" $definition) (hasKey $definition "value") -}}
      {{- $_ := set $workflowParameter "value" $definition.value -}}
    {{- end -}}
  {{- end -}}
  {{- $workflowParameters = append $workflowParameters $workflowParameter -}}
  {{- $taskParameters = append $taskParameters (dict "name" $name "value" (printf "{{workflow.parameters.%s}}" $name)) -}}
{{- end -}}
{{- $templateRef := dict "name" $reference.name "template" (default "main" $reference.template) -}}
{{- if eq $reference.scope "cluster" -}}
  {{- $_ := set $templateRef "clusterScope" true -}}
{{- end -}}
{{- $task := dict "name" "selected-reading" "templateRef" $templateRef -}}
{{- if $taskParameters -}}
  {{- $_ := set $task "arguments" (dict "parameters" $taskParameters) -}}
{{- end -}}
{{- $spec := dict
  "entrypoint" "main"
  "templates" (list (dict "name" "main" "dag" (dict "tasks" (list $task))))
-}}
{{- if $workflowParameters -}}
  {{- $_ := set $spec "arguments" (dict "parameters" $workflowParameters) -}}
{{- end -}}
{{- with $effective.synchronization -}}
  {{- $_ := set $spec "synchronization" (deepCopy .) -}}
{{- end -}}
{{- with $effective.ttlStrategy -}}
  {{- $_ := set $spec "ttlStrategy" (deepCopy .) -}}
{{- end -}}
{{- with $effective.podGC -}}
  {{- $_ := set $spec "podGC" (deepCopy .) -}}
{{- end -}}
{{- with $effective.serviceAccount.name -}}
  {{- $_ := set $spec "serviceAccountName" . -}}
{{- end -}}
{{- $labels := mergeOverwrite (dict
  "runik.ing/component" "tarot"
  "runik.ing/type" "trinket"
  "runik.ing/workflow-type" "selected"
  "runik.ing/reading" $published.name
) (deepCopy (default dict $effective.labels)) -}}
{{ include "workflow.template" (list $root (dict
  "name" (include "common.name" $root)
  "namespace" $root.Release.Namespace
  "labels" $labels
  "annotations" (default dict $effective.annotations)
  "spec" $spec
)) }}
{{- end -}}

{{- define "tarot.v2.renderComposedSpec" -}}
{{- $root := index . 0 -}}
{{- $effective := index . 1 -}}
{{- $reading := index . 2 -}}
{{- $executionMode := default "dag" $effective.executionMode -}}
{{- $workflowInputDefinitions := dict -}}
{{- if $reading.inputs -}}
  {{- $workflowInputDefinitions = default dict $reading.inputs.parameters -}}
{{- end -}}
entrypoint: main
{{- if $reading.onExit }}
onExit: runik-tarot-on-exit
{{- end }}
{{- with $effective.serviceAccount.name }}
serviceAccountName: {{ . | quote }}
{{- end }}
{{- if $workflowInputDefinitions }}
arguments:
  parameters:
  {{- range $name, $definition := $workflowInputDefinitions }}
    - name: {{ $name }}
      {{- if hasKey (default dict $effective.with) $name }}
      value: {{ index $effective.with $name | quote }}
      {{- else if and (kindIs "map" $definition) (hasKey $definition "default") }}
      value: {{ $definition.default | quote }}
      {{- else if and (kindIs "map" $definition) (hasKey $definition "value") }}
      value: {{ $definition.value | quote }}
      {{- end }}
  {{- end }}
{{- end }}
{{- with $effective.synchronization }}
synchronization:
  {{- . | toYaml | nindent 2 }}
{{- end }}
{{- with $effective.ttlStrategy }}
ttlStrategy:
  {{- . | toYaml | nindent 2 }}
{{- end }}
{{- with $effective.podGC }}
podGC:
  {{- . | toYaml | nindent 2 }}
{{- end }}
{{- $renderedVolumes := "" -}}
{{- if $effective.volumes -}}
  {{- $volumeContext := dict "Values" (dict "volumes" $effective.volumes) "Release" $root.Release "Chart" $root.Chart -}}
  {{- $renderedVolumes = include "summon.common.volumes.volumes" $volumeContext -}}
{{- end -}}
{{- if $effective.secrets -}}
  {{- $renderedVolumes = printf "%s\n%s" $renderedVolumes (include "summon.common.volumes.secrets" $effective.secrets) -}}
{{- end -}}
{{- $renderedVolumes = trim $renderedVolumes -}}
{{- if $renderedVolumes }}
volumes:
{{ $renderedVolumes | nindent 2 }}
{{- end }}
{{- with $effective.nodeSelector }}
nodeSelector:
  {{- . | toYaml | nindent 2 }}
{{- end }}
{{- with $effective.tolerations }}
tolerations:
  {{- . | toYaml | nindent 2 }}
{{- end }}
{{- with $effective.affinity }}
affinity:
  {{- . | toYaml | nindent 2 }}
{{- end }}
templates:
{{- if eq $executionMode "containerSet" }}
    - name: main
      {{- with $reading.retryStrategy }}
      retryStrategy:
        {{- . | toYaml | nindent 8 }}
      {{- end }}
      {{- if or $reading.timeout $reading.activeDeadlineSeconds }}
      activeDeadlineSeconds: {{ default $reading.activeDeadlineSeconds $reading.timeout }}
      {{- end }}
      containerSet:
        containers:
        {{- range $jobName, $job := $reading.cards }}
          {{- $card := include "tarot.v2.cardForJob" (list $effective $jobName $job) | fromJson }}
          - name: {{ $jobName }}
{{ omit (deepCopy $card.container) "name" "dependencies" | toYaml | indent 12 }}
            {{- with $job.depends }}
            dependencies:
              {{- . | toYaml | nindent 14 }}
            {{- end }}
        {{- end }}
  {{- else }}
    - name: main
      {{- with $reading.retryStrategy }}
      retryStrategy:
        {{- . | toYaml | nindent 8 }}
      {{- end }}
      {{- if or $reading.timeout $reading.activeDeadlineSeconds }}
      activeDeadlineSeconds: {{ default $reading.activeDeadlineSeconds $reading.timeout }}
      {{- end }}
      dag:
        tasks:
        {{- range $jobName, $job := $reading.cards }}
          - name: {{ $jobName }}
            {{- if $job.uses }}
              {{- $card := include "tarot.v2.cardForJob" (list $effective $jobName $job) | fromJson }}
              {{- if $card.ref }}
            templateRef:
              name: {{ $card.ref.name }}
              template: {{ $card.ref.template }}
                {{- if eq $card.ref.kind "ClusterWorkflowTemplate" }}
              clusterScope: true
                {{- end }}
              {{- else }}
            template: {{ $jobName }}
              {{- end }}
            {{- else }}
            template: {{ $jobName }}
            {{- end }}
            {{- with $job.depends }}
            dependencies:
              {{- . | toYaml | nindent 14 }}
            {{- end }}
            {{- with $job.when }}
            when: {{ . | quote }}
            {{- end }}
            {{- with $job.continueOn }}
            continueOn:
              {{- . | toYaml | nindent 14 }}
            {{- end }}
            {{- with $job.hooks }}
            hooks:
              {{- . | toYaml | nindent 14 }}
            {{- end }}
{{ include "tarot.v2.renderTaskArguments" (list $effective $reading $jobName) | nindent 12 }}
        {{- end }}
    {{- range $jobName, $job := $reading.cards }}
{{ include "tarot.v2.renderJobTemplate" (list $effective $jobName $job) | nindent 4 }}
    {{- end }}
  {{- end }}
{{- with $reading.onExit }}
  {{- $exitJobName := "runik-tarot-on-exit-card" }}
  {{- $exitReading := dict "cards" (dict $exitJobName .) }}
  {{- $exitCard := include "tarot.v2.cardForJob" (list $effective $exitJobName .) | fromJson }}
    - name: runik-tarot-on-exit
      dag:
        tasks:
          - name: finalize
            {{- if $exitCard.ref }}
            templateRef:
              name: {{ $exitCard.ref.name }}
              template: {{ $exitCard.ref.template }}
              {{- if eq $exitCard.ref.kind "ClusterWorkflowTemplate" }}
              clusterScope: true
              {{- end }}
            {{- else }}
            template: {{ $exitJobName }}
            {{- end }}
{{ include "tarot.v2.renderTaskArguments" (list $effective $exitReading $exitJobName) | nindent 12 }}
{{ include "tarot.v2.renderJobTemplate" (list $effective $exitJobName .) | nindent 4 }}
{{- end }}
{{- end -}}

{{- define "tarot.v2.renderWorkflow" -}}
{{- $root := index . 0 -}}
{{- $effective := index . 1 -}}
{{- $reading := include "tarot.v2.composeReading" $effective | fromJson -}}
{{- $reading = include "tarot.v2.applyPublicationContract" (list $root $reading) | fromJson -}}
{{- include "tarot.v2.validate" (list $effective $reading) -}}
{{- range $name, $secret := (default dict $effective.secrets) }}
  {{- if eq (default "kubernetes" $secret.location) "vault" }}
{{ include "vault.secret" (list $root (mergeOverwrite (deepCopy $secret) (dict "name" $name))) }}
  {{- else if $secret.content }}
{{ include "summon.secrets" (list $root (dict "name" $name "definition" $secret)) }}
  {{- end }}
{{ "\n" }}
{{- end }}
{{- range $name, $configMap := (default dict $effective.configMaps) }}
{{ include "summon.configMap" (list $root (dict "name" $name "definition" $configMap)) }}
{{ "\n" }}
{{- end }}
{{- range $name, $volume := (default dict $effective.volumes) }}
  {{- if or (eq (default "emptyDir" $volume.type) "pvc") (eq (default "emptyDir" $volume.type) "persistentVolumeClaim") }}
{{ include "summon.persistentVolumeClaim" (list $root $name $volume) }}
{{ "\n" }}
  {{- end }}
{{- end }}
{{- $spec := include "tarot.v2.renderComposedSpec" (list $root $effective $reading) | fromYaml -}}
{{- if hasKey $spec "Error" -}}
  {{- fail (printf "Tarot generated an invalid WorkflowTemplate spec: %s" $spec.Error) -}}
{{- end -}}
{{- $labels := mergeOverwrite (dict
  "runik.ing/component" "tarot"
  "runik.ing/type" "trinket"
  "runik.ing/workflow-type" "composed"
  "runik.ing/execution-mode" (default "dag" $effective.executionMode)
) (deepCopy (default dict $effective.labels)) -}}
{{ include "workflow.template" (list $root (dict
  "name" (include "common.name" $root)
  "namespace" $root.Release.Namespace
  "labels" $labels
  "annotations" (default dict $effective.annotations)
  "spec" $spec
)) }}
{{- end -}}
