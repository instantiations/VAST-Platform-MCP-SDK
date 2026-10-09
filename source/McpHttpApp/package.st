Package {
	#name : 'McpHttpApp',
	#vaPrerequisites : ['McpApp','SstHttpsCommunications','SstHttpServletSupport'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'McpHttpClientSubApp',
			'McpHttpServerSubApp'
		]
	}
]
}
