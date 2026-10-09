"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

Servlet probe that uses an explicitly supplied transport.
It exercises the production entity writer without a servlet engine.
"
Class {
	#name : 'TestMcpDeliveryServlet',
	#superclass : 'McpHttpServlet',
	#instVars : [
		'configuredTransport'
	],
	#category : 'McpHttpServerTests'
}

{ #category : 'Fixtures' }
TestMcpDeliveryServlet >> transport [
	"Answer the fixture transport.
	Answers:
		<McpStreamableHttpTransport>."
	^configuredTransport

]

{ #category : 'Fixtures' }
TestMcpDeliveryServlet >> transport: aTransport [
	"Set the fixture transport.
	Arguments:
		aTransport - <McpStreamableHttpTransport> test transport.
	Answers:
		<TestMcpDeliveryServlet> the receiver."
	configuredTransport := aTransport

]
