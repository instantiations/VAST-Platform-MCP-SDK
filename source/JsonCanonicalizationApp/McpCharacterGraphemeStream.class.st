Class {
	#name : 'McpCharacterGraphemeStream',
	#superclass : 'Object',
	#instVars : [
		'stream'
	],
	#category : 'JsonCanonicalizationApp'
}

{ #category : 'Not categorized' }
McpCharacterGraphemeStream class >> on: stream [

	^ self basicNew initializeWithStream: stream
]

{ #category : 'Not categorized' }
McpCharacterGraphemeStream >> atEnd [

	^ stream atEnd
]

{ #category : 'Not categorized' }
McpCharacterGraphemeStream >> collectionSpecies [

	^ String
]

{ #category : 'Not categorized' }
McpCharacterGraphemeStream >> initializeWithStream: initialStream [

	self initialize.
	stream := initialStream.
]

{ #category : 'Not categorized' }
McpCharacterGraphemeStream >> next [

	^ self atEnd ifFalse: [
		| value |
		value := stream next value.
		value <= 127
			ifTrue: [ Character codePoint: value ]
			ifFalse: [ Grapheme codePoint: value ] ]
]
