Extension {
	#name : 'SstTcpSocketSieve'
}

{ #category : 'SST-Internal' }
SstTcpSocketSieve >> add: aSocket [

	| state |

	state := Processor enableAsyncMessages: false.
	super add: aSocket.
	Processor enableAsyncMessages: state.
]

{ #category : 'SST-Internal',
  #vaVisibility : 'private' }
SstTcpSocketSieve >> siftForReadySocket [

	| state value |

	state := Processor enableAsyncMessages: false.
	value := super siftForReadySocket.
	Processor enableAsyncMessages: state.
	^ value
]
