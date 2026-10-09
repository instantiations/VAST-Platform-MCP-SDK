"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

In-memory HTTP connection/stream probe with a controlled write action.
It can fail delivery or observe session pins without opening a socket.
"
Class {
	#name : 'TestMcpDeliveryConnection',
	#superclass : 'Object',
	#instVars : [
		'writeAction'
	],
	#category : 'McpHttpServerTests'
}

{ #category : 'Fixtures' }
TestMcpDeliveryConnection >> flush [
	"Complete a fixture write without performing I/O.
	Answers:
		<TestMcpDeliveryConnection> the receiver."

]

{ #category : 'Fixtures' }
TestMcpDeliveryConnection >> nextPutAll: bytes [
	"Run the caller-controlled delivery action.
	Arguments:
		bytes - <ByteArray> encoded response.
	Answers:
		<Object> action result."
	^writeAction cull: bytes

]

{ #category : 'Fixtures' }
TestMcpDeliveryConnection >> stream [
	"Answer this endpoint-free output stream.
	Answers:
		<TestMcpDeliveryConnection>."
	^self

]

{ #category : 'Fixtures' }
TestMcpDeliveryConnection >> writeAction: aBlock [
	"Set the action performed by the next byte write.
	Arguments:
		aBlock - <Block> accepting response bytes.
	Answers:
		<TestMcpDeliveryConnection> the receiver."
	writeAction := aBlock

]
