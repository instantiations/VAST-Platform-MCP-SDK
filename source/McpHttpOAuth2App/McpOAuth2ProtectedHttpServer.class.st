Class {
	#name : 'McpOAuth2ProtectedHttpServer',
	#superclass : 'McpHttpServer',
	#category : 'McpHttpOAuth2App'
}

{ #category : 'Configuration' }
McpOAuth2ProtectedHttpServer >> servletConfig [

	^super servletConfig
		defineServlet: 'McpAuthMetadataServlet' as: 'authMetadataServlet';
		addServletMap: '/.well-known/oauth-authorization-server' forServletNamed: 'authMetadataServlet';
		addServletMap: '/.well-known/oauth-protected-resource' forServletNamed: 'authMetadataServlet';
		yourself
]
