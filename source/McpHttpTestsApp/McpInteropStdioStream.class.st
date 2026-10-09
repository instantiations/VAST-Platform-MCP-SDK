"
Test-only blocking LF stream with UTF-8
text adaptation. One reader and synchronized writers exchange complete byte
lines when flushed. Close wakes the reader. Recorded lines support framing
assertions and live only for a test. This is not a native OS pipe.
"
Class {
	#name : 'McpInteropStdioStream',
	#superclass : 'Object',
	#instVars : [
		'mutex',
		'available',
		'pending',
		'lines',
		'history',
		'closed'
	],
	#category : 'McpHttpTestsApp'
}

{ #category : 'Instance Creation' }
McpInteropStdioStream class >> new [
	"Answer a fresh blocking stream fixture."

	^super new initialize
]

{ #category : 'Reading' }
McpInteropStdioStream >> atEnd [
	"Block until data or close; answer true after all lines are consumed."

	self awaitReadable.
	^mutex critical: [closed and: [lines isEmpty]]
]

{ #category : 'Synchronization',
  #vaVisibility : 'private' }
McpInteropStdioStream >> awaitReadable [
	"Wait for a complete line or EOF. Exactly one reader owns each stream."

	[mutex critical: [lines notEmpty or: [closed]]] whileFalse: [available wait]
]

{ #category : 'Lifecycle' }
McpInteropStdioStream >> close [
	"Publish a final partial line and release a blocked reader."

	mutex critical: [
		closed ifTrue: [^self].
		pending notEmpty
			ifTrue: [| line |
				line := pending asByteArray.
				lines add: line.
				history add: line copy.
				pending removeAll].
		closed := true].
	available signal
]

{ #category : 'Writing' }
McpInteropStdioStream >> flush [
	"Publish only complete LF-delimited byte lines and wake the reader."

	| count remainder |

	count := 0.
	mutex critical: [
		remainder := OrderedCollection new.
		pending do: [:byte |
			byte = Character lf value
				ifTrue: [| line |
					line := remainder asByteArray.
					lines add: line.
					history add: line copy.
					remainder := OrderedCollection new.
					count := count + 1]
				ifFalse: [remainder add: byte]].
		pending := remainder].
	count timesRepeat: [available signal]
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpInteropStdioStream >> initialize [
	"Initialize synchronization and test-owned byte buffers."

	super initialize.
	mutex := Semaphore forMutualExclusion.
	available := Semaphore new.
	pending := OrderedCollection new.
	lines := OrderedCollection new.
	history := OrderedCollection new.
	closed := false
]

{ #category : 'Reading' }
McpInteropStdioStream >> nextLine [
	"Answer one byte line without LF, or nil at EOF."

	self awaitReadable.
	^mutex critical: [lines isEmpty ifTrue: [nil] ifFalse: [lines removeFirst]]
]

{ #category : 'Writing' }
McpInteropStdioStream >> nextPutAll: aCollection [
	"Buffer bytes, encoding String writes as UTF-8 at this text adapter.
	This fixture does not model OsWritePipeStream encoding behavior."

	| bytes |

	bytes := aCollection isString
		ifTrue: [aCollection asUtf8Bytes]
		ifFalse: [aCollection asByteArray].
	mutex critical: [
		closed ifTrue: [self error: 'Interop stdio stream is closed'].
		pending addAll: bytes]
]

{ #category : 'Reading' }
McpInteropStdioStream >> upTo: aDelimiter [
	"Read one physical LF-delimited line, or nil at drained EOF."

	(aDelimiter = Character lf or: [aDelimiter = Character lf value])
		ifFalse: [self error: 'Interop stdio stream requires LF'].
	^self nextLine
]

{ #category : 'Accessing' }
McpInteropStdioStream >> writtenLines [
	"Answer detached complete lines for framing and ordering assertions."

	^mutex critical: [history collect: [:line | line copy]]
]
