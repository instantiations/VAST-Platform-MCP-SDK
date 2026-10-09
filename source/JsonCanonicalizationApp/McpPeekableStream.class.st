Class {
	#name : 'McpPeekableStream',
	#superclass : 'Object',
	#instVars : [
		'stream',
		'atEnd',
		'current'
	],
	#category : 'JsonCanonicalizationApp'
}

{ #category : 'Not categorized' }
McpPeekableStream class >> on: stream [

	^ self basicNew initializeWithStream: stream
]

{ #category : 'Not categorized' }
McpPeekableStream >> atEnd [

	^ atEnd
]

{ #category : 'Not categorized' }
McpPeekableStream >> collectionSpecies [

	^ stream collectionSpecies
]

{ #category : 'Not categorized' }
McpPeekableStream >> initializeWithStream: initialStream [

	self initialize.
	stream := initialStream.
	atEnd := false.
	self readCurrent.
]

{ #category : 'Not categorized' }
McpPeekableStream >> next [

	| next |

	next := current.
	self readCurrent.
	^ next
]

{ #category : 'Not categorized' }
McpPeekableStream >> peek [

	^ current
]

{ #category : 'Not categorized' }
McpPeekableStream >> peekFor: object [

	self atEnd ifTrue: [ ^ false ].
	^ self peek = object ifTrue: [ self next. true ] ifFalse: [ false ]
]

{ #category : 'Not categorized' }
McpPeekableStream >> readCurrent [

	current := stream atEnd
		ifFalse: [ stream next ]
		ifTrue: [ atEnd := true. nil ]
]
