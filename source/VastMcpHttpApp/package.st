Package {
	#name : 'VastMcpHttpApp',
	#vaPrerequisites : ['SstHttpsCommunications','SstHttpServletSupport','VastMcpApp'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'VastMcpHttpClient',
			'VastMcpHttpServer'
		]
	}
]
}
