Package {
	#name : 'VastMcpHttpTestsApp',
	#vaPrerequisites : ['VastMcpHttpApp','VastMcpTestsApp'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'VastMcpHttpClientTests',
			'VastMcpHttpSecurityTests',
			'VastMcpHttpServerTests',
			'VastMcpSseTests'
		]
	}
]
}
