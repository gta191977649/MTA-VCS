//
// Example shader - addBlend.fx
//
// Add pixels to render target
//

//---------------------------------------------------------------------
// addBlend settings
//---------------------------------------------------------------------
texture src;


//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique addblend
{
    pass P0
    {
        //BlendOp             = 3;
        SrcBlend			= 14;
        DestBlend			= 2;
        //BLENDFACTOR = 1;

        //BlendFactor = 50;
        //BLENDFACTOR         = 1;
        // Set up texture stage 0
        Texture[0] = src;
    }
}
