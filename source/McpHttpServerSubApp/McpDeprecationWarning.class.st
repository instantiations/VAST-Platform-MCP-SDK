"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

Nonblocking notification for MCP configuration scheduled to change.
Unhandled notices are written to the Transcript without a modal prompt.
Applications may handle this notification to route or escalate diagnostics.
"
Class {
	#name : 'McpDeprecationWarning',
	#superclass : 'Notification',
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Reporting' }
McpDeprecationWarning >> defaultAction [
	"Report an unhandled configuration notice without blocking a server.
	Answers:
		<Object> unspecified notification result."
	Transcript cr; show: self messageText

]
