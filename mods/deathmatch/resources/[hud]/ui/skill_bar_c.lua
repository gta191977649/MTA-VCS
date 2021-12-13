DGS = exports.dgs
local FadeTimer = nil
local font = dxCreateFont('tip.ttf', 22, false, 'proof') or 'default'
local SkillBar = {
	bk = DGS:dgsCreateImage(25, 183, 450,50,_,false,nil,tocolor(0,0,0,180))
}

local title = "Shotgun-Skill"
SkillBar.title = DGS:dgsCreateLabel(0.02,0.1,1,1,title,true,SkillBar.bk)
DGS:dgsSetProperty(SkillBar.title,"font",font)

SkillBar.progress_new = DGS:dgsCreateProgressBar(0.5,0.2,0.4,0.6, true,SkillBar.bk) 
DGS:dgsProgressBarSetProgress(SkillBar.progress_new,55)

SkillBar.progress_old = DGS:dgsCreateProgressBar(0.5,0.2,0.4,0.6, true,SkillBar.bk) 
DGS:dgsProgressBarSetProgress(SkillBar.progress_old,50)
DGS:dgsSetProperty(SkillBar.progress_old,"bgColor",tocolor(0,0,0,0))
DGS:dgsSetProperty(SkillBar.progress_new,"bgColor",tocolor(100,100,100,255))
DGS:dgsSetProperty(SkillBar.progress_old,"indicatorColor",tocolor(255,255,255,255))
DGS:dgsSetProperty(SkillBar.progress_new,"indicatorColor",tocolor(60,179,113,255))
DGS:dgsSetProperty(SkillBar.progress_new,"padding",{0,0})
DGS:dgsSetProperty(SkillBar.progress_old,"padding",{0,0})

DGS:dgsSetProperty(SkillBar.progress_new,"outline",{"out",0,0,left,right,up,down})
SkillBar.indicator = DGS:dgsCreateLabel(0.91,0.1,1,1,"+",true,SkillBar.bk)
DGS:dgsSetProperty(SkillBar.indicator,"font",font)
DGS:dgsSetVisible(SkillBar.bk,false)

function showSkillBar(title,old,new,time)
	playSoundFrontEnd(11)
	if isTimer(FadeTimer) then killTimer(FadeTimer) end
	time = tonumber(time) or 3000
	-- set property
	if new > old then
		DGS:dgsProgressBarSetProgress(SkillBar.progress_new,new)
		DGS:dgsProgressBarSetProgress(SkillBar.progress_old,old)
		DGS:dgsSetProperty(SkillBar.progress_new,"indicatorColor",tocolor(60,179,113,255))
	else
		DGS:dgsProgressBarSetProgress(SkillBar.progress_new,old)
		DGS:dgsProgressBarSetProgress(SkillBar.progress_old,new)
		DGS:dgsSetProperty(SkillBar.progress_new,"indicatorColor",tocolor(200,60,60,255))
	end
	DGS:dgsSetProperty(SkillBar.title,"text",title)
	DGS:dgsSetProperty(SkillBar.indicator,"text",new > old and "+" or "-")

	DGS:dgsSetAlpha (SkillBar.bk, 1)
	DGS:dgsSetVisible (SkillBar.bk, true)
	FadeTimer = setTimer(function() 
        DGS:dgsAlphaTo(SkillBar.bk,0,false,"OutQuad",500) 
    end,time,1)
end