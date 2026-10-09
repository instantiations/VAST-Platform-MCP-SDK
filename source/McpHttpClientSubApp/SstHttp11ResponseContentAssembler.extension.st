Extension {
	#name : 'SstHttp11ResponseContentAssembler'
}

{ #category : 'Streaming',
  #vaVisibility : 'private' }
SstHttp11ResponseContentAssembler class >> contentsStreamedUntilCloseFrom: aSstSocketStream header: header policy: anHttpAssemblerPolicy [
	"Answer an asynchronous stream pulling chunks from aSstSocketStream until the connection closes.

	 Arguments:
		aSstSocketStream - <SstSocketStream>
		header - <SstHttpHeader>
		anHttpAssemblerPolicy - <SstHttpAssemblerPolicy>
	 Answers:
		<EsStream>"

	| controller pullChunk |

	pullChunk := [
		aSstSocketStream incomingSize > 0
			ifTrue: [aSstSocketStream next: aSstSocketStream incomingSize]
			ifFalse: [| rc |
				rc := aSstSocketStream basicReceiveNextChunk.
				(rc isSciError or: [rc == 0]) ifTrue: [nil] ifFalse: [aSstSocketStream next: rc]]].

	controller := EsStreamController new.
	controller add: pullChunk.

	^controller stream transform: (
		EsStreamTransformer
			fromHandlers: [:data :sink | | result |
				result :=
					[data value]
						on: Exception
						do: [:ex |
							ex exitWith:
								(EsAsyncError error: ex stackTrace: (EsAsyncStackTrace for: ex))].
				result isEsAsyncError
					ifTrue: [
						sink addError: result stackTrace: result stackTrace.
						controller close]
					ifFalse: [
						result isNil
							ifTrue: [controller close]
							ifFalse: [
								sink add: result.
								controller add: pullChunk]]]
			handleError: [:ex :st |
				controller
					addError: ex stackTrace: st;
					close]
			handleDone: [:sink | sink close])
]

{ #category : 'SST-API' }
SstHttp11ResponseContentAssembler class >> getContentsFrom: stream using: header policy: anHttpAssemblerPolicy [
	"Get the contents from the stream using header to choose the appropriate content assembler strategy.
	 Supports open-ended streaming responses (e.g. SSE) when streamContents is enabled.

	 Arguments:
		stream - <WriteStream>
		header - <SstHttpHeader>
		anHttpAssemblerPolicy - <SstHttpAssemblerPolicy>
	 Answers:
		<ByteArray|EsStream>"

	header specifiesContentLength
		ifTrue: [
			^anHttpAssemblerPolicy streamContents
				ifTrue: [
					self contentsStreamedFrom: stream header: header policy: anHttpAssemblerPolicy]
				ifFalse: [stream next: header contentLength]].

	header isChunkedTransferEncoding
		ifTrue: [
			^SstHttpChunkedContentAssembler
				getContentsFrom: stream
				using: header
				policy: anHttpAssemblerPolicy].

	(SstHttpCommunications isBodyEmptyForResponseStatus: header status)
		ifTrue: [^stream isEmpty ifTrue: [stream collectionClass new] ifFalse: [stream upToEnd]].

	anHttpAssemblerPolicy streamContents
		ifTrue: [
			header connection: HttpKeepAliveKey.
			^self contentsStreamedUntilCloseFrom: stream header: header policy: anHttpAssemblerPolicy].

	^self applyConnectionSemanticsInAssemblyFrom: stream using: header
]
