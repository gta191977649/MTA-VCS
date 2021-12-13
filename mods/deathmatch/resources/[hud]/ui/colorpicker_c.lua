local ColorsPatterns = {
    {0,0,0},
    {245,245,245},
    {42,119,161},
    {132,4,16},
    {38,55,57},
    {134,68,110},
    {215,142,16},
    {76,117,183},
    {189,190,198},
    {94,112,114},
    {70,89,122},
    {101,106,121},
    {93,126,141},
    {88,89,90},
    {214,218,214},
    {156,161,163},
    {51,95,63},
    {115,14,26},
    {123,10,42},
    {159,157,148},
    {59,78,120},
    {115,46,62},
    {105,30,59},
    {150,145,140},
    {81,84,89},
    {63,62,69},
    {165,169,167},
    {99,92,90},
    {61,74,104},
    {151,149,146},
    {66,31,33},
    {95,39,43},
    {132,148,171},
    {118,123,124},
    {100,100,100},
    {90,87,82},
    {37,37,39},
    {45,58,53},
    {147,163,150},
    {109,122,136},
    {34,25,24},
    {111,103,95},
    {124,28,42},
    {95,10,21},
    {25,56,38},
    {93,27,32},
    {157,152,114},
    {122,117,96},
    {152,149,134},
    {173,176,176},
    {132,137,136},
    {48,79,69},
    {77,98,104},
    {22,34,72},
    {39,47,75},
    {125,98,86},
    {158,164,171},
    {156,141,113},
    {109,24,34},
    {78,104,129},
    {156,156,152},
    {145,115,71},
    {102,28,38},
    {148,157,159},
    {164,167,165},
    {142,140,70},
    {52,26,30},
    {106,122,140},
    {170,173,142},
    {171,152,143},
    {133,31,46},
    {111,130,151},
    {88,88,83},
    {154,167,144},
    {96,26,35},
    {32,32,44},
    {164,160,150},
    {170,157,132},
    {120,34,43},
    {14,49,109},
    {114,42,63},
    {123,113,94},
    {116,29,40},
    {30,46,50},
    {77,50,47},
    {124,27,68},
    {46,91,32},
    {57,90,131},
    {109,40,55},
    {167,162,143},
    {175,177,177},
    {54,65,85},
    {109,108,110},
    {15,106,137},
    {32,75,107},
    {43,62,87},
    {155,159,157},
    {108,132,149},
    {77.93,96},
    {174,155,127},
    {64,108,143},
    {31,37,59},
    {171,146,118},
    {19,69,115},
    {150,129,108},
    {100,104,106},
    {16,80,130},
    {161,153,131},
    {56,86,148},
    {82,86,97},
    {127,105,86},
    {140,146,154},
    {89,110,135},
    {71,53,50},
    {68,98,79},
    {115,10,39},
    {34,52,87},
    {100,13,27},
    {163,173,198},
    {105,88,83},
    {155,139,128},
    {98,11,28},
    {91,93,94},
    {98,68,40},
    {115,24,39},
    {27,55,109},
    {236,106,174},
}
local Colors = {}
local SelectedColor = 1

--DGS:dgsCreateImage(0,0,1,1,"sa-mp-090.png",true,_,tocolor(255,255,255,255))
--[[
local colorPicker = DGS:dgsCreateGridList (0.045, 0.325, 0.323,0.585, true ) 
DGS:dgsSetProperty(colorPicker,"columnColor",tocolor(0,0,0,0))
DGS:dgsSetProperty(colorPicker,"bgColor",tocolor(0,0,0,200))
DGS:dgsSetProperty(colorPicker,"leading",0)
DGS:dgsSetProperty(colorPicker,"columnHeight",0)
DGS:dgsSetProperty(colorPicker,"sortEnabled",false)
DGS:dgsSetProperty(colorPicker,"rowHeight",65)
DGS:dgsSetProperty(colorPicker,"clip",false)
DGS:dgsSetProperty(colorPicker,"scrollBarState",{false,false})
DGS:dgsSetProperty(colorPicker,"rowColor",{tocolor(0,0,0,0),tocolor(0,0,0,0),tocolor(0,0,0,0)})
--]]

-- Create color images
local colorPicker = DGS:dgsCreateImage(0.045, 0.325, 0.323,0.585,_,true,nil,tocolor(0,0,0,210))
local c_width = 0.11
local c_height = 0.11
local c_offset = 1.1
local idx = 1
local padding = 0.02
for i=1,8 do 
    for j = 1,8 do 
        table.insert(Colors,{
            img = DGS:dgsCreateImage(padding + ((j-1) * c_width ) * c_offset,padding +  ((i-1) * c_height ) * c_offset,c_width,c_height ,_,true,colorPicker,tocolor(ColorsPatterns[idx][1],ColorsPatterns[idx][2],ColorsPatterns[idx][3],
            255)),
            color = ColorsPatterns[idx]
        })
        idx = idx + 1
    end
end


DGS:dgsSetVisible (colorPicker,false )

function onColorPickerKey(key,press)
    if DGS:dgsGetVisible(colorPicker) == false then return end

    if key == "arrow_r" and press then
        if SelectedColor < 64 then 
            DGS:dgsSetProperty(Colors[SelectedColor].img,"outline",{"out",0,tocolor(255,255,255,0)})
            SelectedColor = SelectedColor + 1
            triggerEvent ( "onColorPickerSelected", colorPicker,false,Colors[SelectedColor].color[1],Colors[SelectedColor].color[2],Colors[SelectedColor].color[3],Colors[SelectedColor].color[4])
            playSoundFrontEnd( 3 )
        end
    end 
    if key == "arrow_l" and press then
        if SelectedColor > 1 then 
            DGS:dgsSetProperty(Colors[SelectedColor].img,"outline",{"out",0,tocolor(255,255,255,0)})
            SelectedColor = SelectedColor - 1
            triggerEvent ( "onColorPickerSelected", colorPicker,false,Colors[SelectedColor].color[1],Colors[SelectedColor].color[2],Colors[SelectedColor].color[3],Colors[SelectedColor].color[4])
            playSoundFrontEnd( 3 )
        end
    end 
    if key == "arrow_d" and press then
        if SelectedColor+8 <= 64 then 
            DGS:dgsSetProperty(Colors[SelectedColor].img,"outline",{"out",0,tocolor(255,255,255,0)})
            SelectedColor = SelectedColor +8
            triggerEvent ( "onColorPickerSelected", colorPicker,false,Colors[SelectedColor].color[1],Colors[SelectedColor].color[2],Colors[SelectedColor].color[3],Colors[SelectedColor].color[4])
            playSoundFrontEnd( 3 )
        end
    end 
    if key == "arrow_u" and press then
        if SelectedColor-8 > 0 then 
            DGS:dgsSetProperty(Colors[SelectedColor].img,"outline",{"out",0,tocolor(255,255,255,0)})
            SelectedColor = SelectedColor -8
            triggerEvent ( "onColorPickerSelected", colorPicker,false,Colors[SelectedColor].color[1],Colors[SelectedColor].color[2],Colors[SelectedColor].color[3],Colors[SelectedColor].color[4])
            playSoundFrontEnd( 3 )
        end
    end 
    if key == "space" and press then
        triggerEvent ( "onColorPickerSelected", colorPicker,true,Colors[SelectedColor].color[1],Colors[SelectedColor].color[2],Colors[SelectedColor].color[3],Colors[SelectedColor].color[4])
        playSoundFrontEnd( 1 )
    end 

    DGS:dgsSetProperty(Colors[SelectedColor].img,"outline",{"out",3,tocolor(255,255,255,255)})
    if key == "f" and press then
        DGS:dgsSetProperty(Colors[SelectedColor].img,"outline",{"out",0,tocolor(0,0,0,0)})
        triggerEvent ( "onColorPickerExit", colorPicker)
        playSoundFrontEnd( 1 )
    end 
    
end
function getColorPicker()
    return colorPicker
end
function showColorPicker()
    SelectedColor = 1
    -- clear outline
    for i = 1,#Colors do 
        DGS:dgsSetProperty(Colors[i].img,"outline",{"out",0,tocolor(0,0,0,0)})
    end
    
    DGS:dgsSetVisible (colorPicker,true )
    addEventHandler("onClientKey", root, onColorPickerKey)
end
function hideColorPicker()  
    DGS:dgsSetVisible (colorPicker,false )
    removeEventHandler("onClientKey", root,onColorPickerKey )
end

addEvent ( "onColorPickerSelected", true  )
addEvent ( "onColorPickerExit", true  )