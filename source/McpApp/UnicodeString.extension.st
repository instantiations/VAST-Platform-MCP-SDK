Extension {
	#name : 'UnicodeString'
}

{ #category : 'Not categorized' }
UnicodeString >> inetAddr [
	"Answer inet address form of the receiver as a 4-byte ByteArray.

	 Answers:
		<ByteArray>."

	^self asSBString inetAddr
]

{ #category : 'Not categorized' }
UnicodeString >> isIPv4AddressString [
	"Answer whether the receiver has the signature of an IPv4 address.

	 Answers:
		<Boolean>."

	^self asSBString isIPv4AddressString
]

{ #category : 'Not categorized' }
UnicodeString >> isIPv6AddressString [
	"Answer whether the receiver has the signature of an IPv6 address.

	 Answers:
		<Boolean>."

	^self asSBString isIPv6AddressString
]

{ #category : 'Not categorized' }
UnicodeString >> parseIPAddress [
	"Answer a 3-element Array (ipAddress string, scopeID string, and port string)
	 constructed from the contents of the receiver. The receiver may represent a
	 hostname, a URL, or an IPv4 or IPv6 address (all with or without a port number).
	 If the scopeID and/or port are not specified, their array elements will be empty strings.

	 Answers:
		<Array> 3-element Array (ipAddress string, scopeID string, and port string)
		<SciError> if parsing fails."

	^self asSBString parseIPAddress
]
