DGS = exports.dgs --get exported functions from dgs

function createSampDialog()
    dialog = DGS:dgsCreateWindow (0,0, 0.4, 0.2, " Dialog Style Message Box", true )
    memo = DGS:dgsCreateMemo(0,0.06,0.95,0.5,"",true,dialog)
    btn = DGS:dgsCreateButton ( 0.4, 0.6, 0.16, 0.18, "Close", true, dialog )
    DGS:dgsCenterElement(dialog)
    DGS:dgsCenterElement(memo,false,true)
    DGS:dgsWindowSetCloseButtonEnabled (dialog,false )
    DGS:dgsSetProperty(dialog,"alignment",{"left","center"})
    DGS:dgsSetProperty(dialog,"color",tocolor(0,0,0,220))
    DGS:dgsSetProperty(memo,"bgColor",tocolor(0,0,0,0))
    local font = dxCreateFont('arial.ttf', 10, false, 'proof') or 'default'
    DGS:dgsSetFont(dialog, font)
    DGS:dgsSetFont(btn, font)
    DGS:dgsSetFont(memo, font)
    --local btn_img = DGS:dgsCreateImage(0,0,130,47,"res/samp_button.png",false)
    local btn_img = dxCreateTexture ("res/samp_button.png" )
    DGS:dgsAttachToAutoDestroy(btn_img,btn)
    DGS:dgsSetProperty(btn,"image",{btn_img,btn_img,btn_img})
    DGS:dgsSetProperty(btn,"textSize",{1.25,1.25})
    DGS:dgsSetProperty(memo,"text","This is a SAMP Dialog Info.\nTest\nTest\n!@#$%^&*()_+")

end