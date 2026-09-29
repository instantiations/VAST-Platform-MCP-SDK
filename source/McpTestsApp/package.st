Package {
	#name : 'McpTestsApp',
	#vaPrerequisites : ['EsAsynchronousSupport','SUnit','McpApp'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'McpPromptTests',
			'McpProtocolTests',
			'McpResourceTests',
			'McpStructuralTests',
			'McpToolTests'
		]
	}
]
}
