

addEventHandler( "onClientResourceStart",resourceRoot,
    function (  )
		alphaShader1 = dxCreateShader ( "client/WindowHandler_C.fx",0,0,false,'object' )
		
		
		applyList = {'*wind*','*neon*','*cl_ofis_gls2*','*waterclear256*'}

		for i,v in pairs(applyList) do
			engineApplyShaderToWorldTexture(alphaShader1,v,nil,false)
		end
    end
);