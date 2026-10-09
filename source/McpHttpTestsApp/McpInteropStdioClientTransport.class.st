"
Test-only stdio transport adapter.
Uses the production request correlation, JSON parsing and result validation
with a real McpStdioServer running in another Smalltalk process. Overrides
connection establishment, byte delivery and cleanup to avoid subprocesses.
This fixture does not test process startup, stderr or native pipe behavior.
"
Class {
	#name : 'McpInteropStdioClientTransport',
	#superclass : 'McpStdioClientTransport',
	#instVars : [
		'inputChannel',
		'outputChannel',
		'stdioServer'
	],
	#category : 'McpHttpTestsApp'
}

{ #category : 'Lifecycle' }
McpInteropStdioClientTransport >> attachToServer: aStdioServer [
	"Connect real stdio protocol endpoints through test-owned streams.
	Process creation and OS pipe behavior are deliberately outside scope."

	isClosing := false.
	inputChannel := McpInteropStdioStream new.
	outputChannel := McpInteropStdioStream new.
	stdioServer := aStdioServer.
	stdioServer
		inputStream: inputChannel;
		outputStream: outputChannel.
	stdoutProcess :=
		[
			[
				[outputChannel atEnd] whileFalse: [| line |
					line := outputChannel nextLine.
					line ifNotNil: [self handleStdoutLine: line]]]
						ensure: [self handleProcessTerminated]]
							forkAt: Processor userBackgroundPriority.
	stdioServer start
]

{ #category : 'Lifecycle' }
McpInteropStdioClientTransport >> close [
	"Release fixture streams and workers, including on assertion failure."

	isClosing := true.
	[
		inputChannel ifNotNil: [inputChannel close].
		outputChannel ifNotNil: [outputChannel close].
		stdioServer ifNotNil: [stdioServer stop]]
			ensure: [super close]
]

{ #category : 'Lifecycle' }
McpInteropStdioClientTransport >> ensureConnected [
	"Require the fixture connection; never launch an external process."

	self isRunning ifFalse: [self error: 'Interop stdio server is stopped']
]

{ #category : 'Testing' }
McpInteropStdioClientTransport >> isRunning [
	"Answer whether the attached stdio server is active."

	^isClosing not and: [stdioServer notNil and: [stdioServer isRunning]]
]

{ #category : 'Accessing' }
McpInteropStdioClientTransport >> requestLines [
	"Answer recorded input lines for this test."

	^inputChannel writtenLines
]

{ #category : 'Accessing' }
McpInteropStdioClientTransport >> responseLines [
	"Answer recorded output lines for this test."

	^outputChannel writtenLines
]

{ #category : 'Writing' }
McpInteropStdioClientTransport >> sendLine: aJsonString [
	"Write serialized UTF-8 JSON through the blocking input stream.
	Inherited sendRequest:id: owns correlation, timeouts and validation."

	self ensureConnected.
	processMutex critical: [
		inputChannel
			nextPutAll: (aJsonString , (String with: Character lf)) asUtf8Bytes;
			flush]
]
