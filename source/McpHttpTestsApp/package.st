Package {
	#name : 'McpHttpTestsApp',
	#vaPrerequisites : ['McpHttpApp','McpTestsApp'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'McpHttpClientTests',
			'McpHttpSecurityTests',
			'McpHttpServerTests',
			'McpSseTests'
		]
	}
]
}
