Extension {
	#name : 'SstTcpSocketSieve'
}

{ #category : 'SST-Internal' }
SstTcpSocketSieve >> add: aSocket [

	[ super add: aSocket ] critical
]

{ #category : 'SST-Internal',
  #vaVisibility : 'private' }
SstTcpSocketSieve >> siftForReadySocket [

	^ [ super siftForReadySocket ] critical
]
