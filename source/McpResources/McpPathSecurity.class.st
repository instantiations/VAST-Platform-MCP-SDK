"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpPathSecurity

`McpPathSecurity` provides filesystem path safety primitives for resource handlers,
preventing directory traversal and sandbox escape attacks.

## Responsibilities

- Detect relative directory traversal sequences (`..` across `/` and `\`).
- Detect null byte injections (`\0`).
- Detect absolute path overrides (leading slashes or Windows drive letters).
- Safely join relative paths onto sandbox base roots via `safeJoin:with:`,
  signaling `McpPathEscapeError` upon any escape attempt.

## Lifecycle and boundaries

Stateless utility class with class-side methods.
"
Class {
	#name : 'McpPathSecurity',
	#superclass : 'Object',
	#category : 'McpResources'
}

{ #category : 'Validation' }
McpPathSecurity class >> containsPathTraversal: aPathString [
	"Answer whether aPathString, treated as a relative path, contains directory traversal
	 or null byte escape sequences.

	 Arguments:
		aPathString - <String>.
	 Answers:
		<Boolean>."

	| normalized stream segment |

	(aPathString isString and: [aPathString notEmpty]) ifFalse: [^false].
	(aPathString anySatisfy: [:c | c codePoint = 0]) ifTrue: [^true].
	normalized := aPathString copyReplaceAll: '\' with: '/'.
	stream := normalized readStream.
	[stream atEnd] whileFalse: [
		segment := stream upTo: $/.
		segment trimBlanks = '..' ifTrue: [^true]].
	^false
]

{ #category : 'Validation' }
McpPathSecurity class >> isAbsolutePath: aPathString [
	"Answer whether aPathString is in absolute form (leading slash or drive letter).

	 Arguments:
		aPathString - <String>.
	 Answers:
		<Boolean>."

	| trimmed |

	aPathString isString ifFalse: [^false].
	trimmed := aPathString trimBlanks.
	trimmed isEmpty ifTrue: [^false].
	(trimmed first = $/ or: [trimmed first = $\]) ifTrue: [^true].
	(trimmed size >= 2
		and: [(trimmed first between: $A and: $Z) or: [(trimmed first between: $a and: $z)]])
			ifTrue: [(trimmed at: 2) = $: ifTrue: [^true]].
	^false
]

{ #category : 'Validation' }
McpPathSecurity class >> safeJoin: aBasePathString with: aRelativePathString [
	"Join aRelativePathString onto aBasePathString, ensuring the resolved target
	 path does not escape the base directory.

	 Arguments:
		aBasePathString - <String> sandbox root.
		aRelativePathString - <String> relative path to join.
	 Answers:
		<String> normalized resolved path."

	| normalizedBase normalizedRel cleanBase cleanRel joined |

	(aBasePathString isString and: [aBasePathString notEmpty])
		ifFalse: [McpPathEscapeError signal: 'Base path must be a nonempty string'].
	(aRelativePathString isString and: [aRelativePathString notEmpty])
		ifFalse: [McpPathEscapeError signal: 'Relative path must be a nonempty string'].

	((aBasePathString anySatisfy: [:c | c codePoint = 0])
		or: [aRelativePathString anySatisfy: [:c | c codePoint = 0]])
			ifTrue: [McpPathEscapeError signal: 'Path component contains a null byte'].

	(self isAbsolutePath: aRelativePathString)
		ifTrue: [McpPathEscapeError signal: 'Path component is absolute: ' , aRelativePathString].

	(self containsPathTraversal: aRelativePathString)
		ifTrue: [
			McpPathEscapeError signal: 'Path component contains traversal: ' , aRelativePathString].

	normalizedBase := aBasePathString copyReplaceAll: '\' with: '/'.
	normalizedRel := aRelativePathString copyReplaceAll: '\' with: '/'.
	cleanBase := normalizedBase trimBlanks.
	cleanBase last = $/ ifTrue: [cleanBase := cleanBase copyFrom: 1 to: cleanBase size - 1].
	cleanRel := normalizedRel trimBlanks.
	cleanRel first = $/ ifTrue: [cleanRel := cleanRel copyFrom: 2 to: cleanRel size].

	joined := cleanBase , '/' , cleanRel.
	^joined
]
