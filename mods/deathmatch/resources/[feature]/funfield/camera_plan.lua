-- Plan one entire composition against forecast geometry, before its cut.
-- The caller resumes this coroutine in small batches while the prior shot runs.
FerrisCinemaPlanner={}
function FerrisCinemaPlanner.begin(start,duration,context,arrival,validate)
    local job={start=start,duration=duration,context=context,arrival=arrival}
    job.thread=coroutine.create(function()
        local variants={}
        for _,pair in ipairs({{0,0},{12,0},{-12,0},{24,.3},{-24,.3},{0,.3},
            {40,0},{-40,0},{65,0},{-65,0},{90,0},{-90,0},{120,0},{-120,0},{150,0},{-150,0},{180,0}}) do
            variants[#variants+1]={angle=pair[1],rise=pair[2]}
        end
        if context.ped then
            for _,radius in ipairs({0,8,16}) do
                for _,direction in ipairs({-1,1}) do variants[#variants+1]={style="two",radius=radius,direction=direction} end
            end
        end
        if FerrisCinemaPath.evaluate(start,context).name=="greeting" then
            for _,angle in ipairs({0,180,15,-15,165,195}) do variants[#variants+1]={style="portrait",angle=angle} end
        end
        variants[#variants+1]={style="sheltered",direction=1}
        variants[#variants+1]={style="sheltered",direction=-1}
        local contexts=context.candidates or {context}
        local forecasts={}
        -- Rank the mirrored reveals by clear halo samples during the ending.
        if context.sunVariants then
            local bestScore=0
            for _,variant in ipairs(context.sunVariants) do
                local score,previous=0,nil
                local valid=true
                forecasts[1]=forecasts[1] or {}
                for i=0,64 do
                    local offset=math.min(duration-.00001,duration*i/64)
                    local future=forecasts[1][i] or FerrisCinemaPath.predict(context,offset)
                    forecasts[1][i]=future
                    local frame=FerrisCinemaPath.planned(FerrisCinemaPath.evaluate(start+offset,future),future,variant)
                    local safe,glow=validate(frame,future,previous,false)
                    if not safe then valid=false break end
                    if i>=48 and glow then score=score+1 end
                    previous=frame
                    coroutine.yield()
                end
                if valid and score>=13 and score>bestScore then
                    job.variant=variant
                    bestScore=score
                end
                if bestScore==17 then break end
            end
            if job.variant then job.validated=true return end
        end
        for _,variant in ipairs(variants) do
            local count=variant.style=="sheltered" and 1 or #contexts
            for candidate=1,count do
                local selected=contexts[candidate]
                forecasts[candidate]=forecasts[candidate] or {}
                local samples=forecasts[candidate]
                local valid=true
                local previous
                -- 65 samples per shot, with swept lens checks between samples.
                for i=0,64 do
                    local offset=math.min(duration-.00001,duration*i/64)
                    local future=samples[i] or FerrisCinemaPath.predict(selected,offset)
                    samples[i]=future
                    local frame=arrival and FerrisCinemaPath.arrival(offset,future) or FerrisCinemaPath.evaluate(start+offset,future)
                    frame=FerrisCinemaPath.planned(frame,future,variant)
                    if not validate(frame,future,previous,variant.style~="sheltered" and variant.style~="portrait") then valid=false break end
                    previous=frame
                    coroutine.yield()
                end
                if valid then
                    job.variant=variant job.validated=true
                    job.ped=selected.pedElement or job.ped
                    return
                end
                coroutine.yield()
            end
        end
        -- Retain one deterministic interior path if even the conservative
        -- corridor could not be certified. Never search for angles mid-shot.
        job.variant={style="sheltered",direction=1}
        job.validated=false
    end)
    return job
end
function FerrisCinemaPlanner.resume(job,budget)
    if job.done then return end
    for i=1,budget do
        local ok,why=coroutine.resume(job.thread)
        if not ok then error(why) end
        if coroutine.status(job.thread)=="dead" then job.done=true return end
    end
end
