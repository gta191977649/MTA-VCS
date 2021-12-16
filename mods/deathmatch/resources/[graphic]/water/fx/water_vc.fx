texture Tex0; 
  
technique simple 
{ 
    pass P0 
    { 
        AlphaBlendEnable = TRUE;
        AlphaRef = 1;
        Texture[0] = Tex0; 

    } 
} 
  