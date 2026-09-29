Package {
	#name : 'McpHttpApp',
	#vaPrerequisites : ['SstHttpsCommunications','SstHttpServletSupport','McpApp'],
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
