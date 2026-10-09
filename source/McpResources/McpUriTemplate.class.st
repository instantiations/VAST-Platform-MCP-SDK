"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpUriTemplate

`McpUriTemplate` implements RFC 6570 Level 1-4 URI Template expansion, matching,
and variable extraction.

## Responsibilities

- Parse and compile URI templates containing Level 1-3 operators (`+`, `#`, `.`,
  `/`, `;`, `?`, `&`) and Level 4 explode modifiers (`{/var*}`).
- Match concrete URIs against compiled patterns, extracting variables into a keyed
  dictionary.
- Automatically unquote percent-encoded components via `sstUrlDecodePathComponent`.
- Expand templates with variable values according to RFC 6570 rules.
- Identify templated URIs via `isTemplate:`.

## Lifecycle and boundaries

Immutable once instantiated. Owned by an `McpResourceTemplate`.
"
Class {
	#name : 'McpUriTemplate',
	#superclass : 'Object',
	#instVars : [
		'templateString',
		'matcher',
		'variableNames'
	],
	#category : 'McpResources'
}

{ #category : 'Testing' }
McpUriTemplate class >> isTemplate: aString [
	"Answer whether aString contains at least one variable expression {...}.

	 Arguments:
		aString - <String>.
	 Answers:
		<Boolean>."

	| start end |

	(aString isString and: [aString size >= 3]) ifFalse: [^false].
	start := aString indexOf: ${.
	start = 0 ifTrue: [^false].
	end := aString indexOf: $} startingAt: start + 1.
	^end > (start + 1)
]

{ #category : 'Instance Creation' }
McpUriTemplate class >> template: aString [
	"Answer a new compiled URI template.

	 Arguments:
		aString - <String> RFC 6570 template string.
	 Answers:
		<McpUriTemplate>."

	^self new templateString: aString
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpUriTemplate >> compile [
	"Compile the template string into an RxMatcher regex and variable names list.
	 Supports RFC 6570 Level 1-3 operators (+, #, ., /, ;, ?, &) and Level 4 explode (/var*).

	 Answers:
		<McpUriTemplate> the receiver."

	| regexStream varStream specialChars stream char varExpr op varName isExploded hasQueryAfter
	  pattern |

	variableNames := OrderedCollection new.
	regexStream := WriteStream on: String new.
	specialChars := '\^$.[]()*+?{}|:'.
	regexStream nextPut: $^.

	stream := templateString readStream.
	[stream atEnd] whileFalse: [
		char := stream next.
		char = ${
			ifTrue: [
				varStream := WriteStream on: String new.
				[stream atEnd or: [(char := stream next) = $}]] whileFalse: [varStream nextPut: char].
				varExpr := varStream contents.
				varExpr notEmpty
					ifTrue: [
						op := nil.
						('+/#.;?&' includes: varExpr first)
							ifTrue: [
								op := varExpr first.
								varName := varExpr copyFrom: 2 to: varExpr size]
							ifFalse: [varName := varExpr].
						isExploded := varName notEmpty and: [varName last = $*].
						isExploded ifTrue: [varName := varName copyFrom: 1 to: varName size - 1].
						variableNames add: varName.
						hasQueryAfter := (templateString indexOf: $? startingAt: stream position) > 0.
						pattern :=
							self
								regexPatternFor: varName
								operator: op
								exploded: isExploded
								hasQueryAfter: hasQueryAfter.
						regexStream nextPutAll: pattern]]
			ifFalse: [
				(specialChars includes: char) ifTrue: [regexStream nextPut: $\].
				regexStream nextPut: char]].

	regexStream nextPut: $$.
	matcher := RxMatcher forString: regexStream contents.
	^self
]

{ #category : 'Formatting' }
McpUriTemplate >> expand: aDictionary [
	"Expand this template with variable values from aDictionary per RFC 6570.

	 Arguments:
		aDictionary - <KeyedCollection> variable values.
	 Answers:
		<String> expanded URI."

	| stream varStream char varExpr op varName isExploded val valStr tmplStream |

	stream := WriteStream on: String new.
	tmplStream := templateString readStream.
	[tmplStream atEnd] whileFalse: [
		char := tmplStream next.
		char = ${
			ifTrue: [
				varStream := WriteStream on: String new.
				[tmplStream atEnd or: [(char := tmplStream next) = $}]]
					whileFalse: [varStream nextPut: char].
				varExpr := varStream contents.
				varExpr notEmpty
					ifTrue: [
						op := nil.
						('+/#.;?&' includes: varExpr first)
							ifTrue: [
								op := varExpr first.
								varName := varExpr copyFrom: 2 to: varExpr size]
							ifFalse: [varName := varExpr].
						isExploded := varName notEmpty and: [varName last = $*].
						isExploded ifTrue: [varName := varName copyFrom: 1 to: varName size - 1].
						val := aDictionary at: varName ifAbsent: [''].
						valStr := val isString ifTrue: [val] ifFalse: [val printString].
						self expandVariable: varName operator: op value: valStr onto: stream]]
			ifFalse: [stream nextPut: char]].
	^stream contents
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpUriTemplate >> expandVariable: aVarName operator: anOp value: aValue onto: aStream [
	"Write the expanded variable representation onto aStream.

	 Arguments:
		aVarName - <String> variable name.
		anOp - <Character> or nil, operator (+, #, ., /, ;, ?, &).
		aValue - <String> raw string value.
		aStream - <WriteStream> destination.
	 Answers:
		<McpUriTemplate> the receiver."

	anOp = $+
		ifTrue: [
			aStream nextPutAll: aValue.
			^self].
	anOp = $#
		ifTrue: [
			aValue notEmpty
				ifTrue: [
					aStream
						nextPut: $#;
						nextPutAll: aValue].
			^self].
	anOp = $.
		ifTrue: [
			aValue notEmpty
				ifTrue: [
					aStream
						nextPut: $.;
						nextPutAll: aValue].
			^self].
	anOp = $/
		ifTrue: [
			aValue notEmpty
				ifTrue: [
					aValue first = $/
						ifTrue: [aStream nextPutAll: aValue]
						ifFalse: [
							aStream
								nextPut: $/;
								nextPutAll: aValue]].
			^self].
	anOp = $;
		ifTrue: [
			aStream
				nextPut: $;;
				nextPutAll: aVarName.
			aValue notEmpty
				ifTrue: [
					aStream
						nextPut: $=;
						nextPutAll: aValue].
			^self].
	anOp = $?
		ifTrue: [
			aStream
				nextPut: $?;
				nextPutAll: aVarName;
				nextPut: $=;
				nextPutAll: aValue.
			^self].
	anOp = $&
		ifTrue: [
			aStream
				nextPut: $&;
				nextPutAll: aVarName;
				nextPut: $=;
				nextPutAll: aValue.
			^self].
	aStream nextPutAll: aValue.
	^self
]

{ #category : 'Matching' }
McpUriTemplate >> matchUri: aUriString [
	"Match aUriString against this template and answer extracted variables, or nil if no match.
	 Decodes percent-encoded components.

	 Arguments:
		aUriString - <String> concrete URI.
	 Answers:
		<KeyedCollection> variables map, or nil."

	| variables val |

	(self matcher matches: aUriString) ifFalse: [^nil].
	variables := EsOrderedDictionary new.
	1 to: self variableNames size do: [:idx |
		val := self matcher subexpression: idx + 1.
		val := val isNil ifTrue: [''] ifFalse: [val sstUrlDecodePathComponent].
		variables at: (self variableNames at: idx) put: val].
	^variables
]

{ #category : 'Accessing' }
McpUriTemplate >> matcher [
	"Answer the compiled regular expression matcher.

	 Answers:
		<RxMatcher>."

	^matcher
]

{ #category : 'Testing' }
McpUriTemplate >> matchesUri: aUriString [
	"Answer whether aUriString matches this template.

	 Arguments:
		aUriString - <String> concrete URI.
	 Answers:
		<Boolean>."

	^(self matchUri: aUriString) notNil
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpUriTemplate >> regexPatternFor: aVarName operator: anOp exploded: isExploded hasQueryAfter: hasQueryAfter [
	"Answer the regex pattern fragment for an RFC 6570 variable expression.

	 Arguments:
		aVarName - <String> variable name.
		anOp - <Character> or nil, operator (+, #, ., /, ;, ?, &).
		isExploded - <Boolean> whether the variable has an explode modifier (*).
		hasQueryAfter - <Boolean> whether query parameters follow in the template.
	 Answers:
		<String>."

	anOp = $+ ifTrue: [^hasQueryAfter ifTrue: ['([^?#]+)'] ifFalse: ['([^#]+)']].
	anOp = $# ifTrue: [^'#([^#]+)'].
	anOp = $. ifTrue: [^'\.([^/?#]+)'].
	anOp = $/ ifTrue: [^isExploded ifTrue: ['/([^?#]+)'] ifFalse: ['/([^/?#]+)']].
	anOp = $; ifTrue: [^';' , aVarName , '=([^;/?#]*)'].
	anOp = $? ifTrue: [^'\?' , aVarName , '=([^&#]*)'].
	anOp = $& ifTrue: [^'&' , aVarName , '=([^&#]*)'].
	^'([^/?#]+)'
]

{ #category : 'Accessing' }
McpUriTemplate >> templateString [
	"Answer the raw RFC 6570 URI template string.

	 Answers:
		<String>."

	^templateString
]

{ #category : 'Accessing' }
McpUriTemplate >> templateString: aString [
	"Set and compile the RFC 6570 URI template string.

	 Arguments:
		aString - <String> template pattern.
	 Answers:
		<McpUriTemplate> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Template string must be a nonempty string'].
	templateString := aString copy.
	self compile.
	^self
]

{ #category : 'Accessing' }
McpUriTemplate >> variableNames [
	"Answer the ordered list of extracted template variable names.

	 Answers:
		<OrderedCollection> of <String>."

	variableNames ifNil: [variableNames := OrderedCollection new].
	^variableNames
]
