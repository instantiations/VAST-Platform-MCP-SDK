Class {
	#name : 'McpUnicodeScalarStream',
	#superclass : 'Object',
	#instVars : [
		'stream',
		'unicodeScalars'
	],
	#category : 'JsonCanonicalizationApp'
}

{ #category : 'Not categorized' }
McpUnicodeScalarStream class >> on: stream [

	^ self basicNew initializeWithStream: stream
]

{ #category : 'Not categorized' }
McpUnicodeScalarStream >> atEnd [

	^ unicodeScalars atEnd and: [ stream atEnd ]
]

{ #category : 'Not categorized' }
McpUnicodeScalarStream >> initializeWithStream: initialStream [

	self initialize.
	stream := initialStream.
	unicodeScalars := '' unicodeScalars.
]

{ #category : 'Not categorized' }
McpUnicodeScalarStream >> next [

	unicodeScalars atEnd ifTrue: [
		stream atEnd ifTrue: [ ^ nil ].
		unicodeScalars := stream next asString unicodeScalars ].
	^ unicodeScalars next
]
