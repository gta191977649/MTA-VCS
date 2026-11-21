"""Recover the PS2 timed circuits, water ramps and the mall's 50 stunt coronas."""
import argparse
from collections import Counter
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "mods/deathmatch/resources/[mission]/mission"
# Script, course count, coordinate-array capacity, count slot, target array, area box.
LAYOUTS = {
    "watersports": ("TTRIAL",8,36,5501,5493,5503),
    "quadtrial": ("QTTRIAL",4,20,5413,5409,5416),
    "bmxtrial": ("BTRIAL",8,20,5417,5409,5420),
    "sancheztrial": ("DTRIAL",12,25,5436,5424,5439),
    "caddydaddy": ("GTRIAL",1,36,5458,5457,5461),
}
NUMBER = r"-?\d+(?:\.\d+)?"

def assignments(text):
    return {int(k):v for k,v in re.findall(rf"(?m)^[$](\d+) = ({NUMBER})$",text)}

def row(data):
    return "{"+",".join(map(str,data))+"}"

def course_data(main):
    out=["-- Extracted by tools/import_vcs_trials.py from the US PS2 MAIN.txt.","TrialCourses = {"]
    for key,(name,total,stride,count_slot,target_slot,bounds_slot) in LAYOUTS.items():
        body=main.split("\n:"+name+"\n",1)[1].split("// Originally:",1)[0]
        globals_=assignments(body)
        starts=list(re.finditer(rf"(?m)^[$]{count_slot} = (\d+)$",body))
        starts=[m for m in starts if "$5348 = " in body[m.start():].split("\n:",1)[0]]
        assert len(starts)==total,(key,len(starts))
        out.append("    "+key+"={")
        for index,m in enumerate(starts):
            block=body[m.start():].split("\n:",1)[0]
            values=assignments(block)
            count=int(m[1])
            points=[row(values[5348+k*stride+i] for k in range(3)) for i in range(count)]
            bounds=row(values[bounds_slot+k] for k in range(4))
            out.append(f"        {{target={globals_[target_slot+index]},bounds={bounds},points={{")
            out.extend("            "+",".join(points[i:i+4])+"," for i in range(0,len(points),4))
            if key=="watersports":
                ramps_block=body.split(":"+name+"_2607\n",1)[1].split(f"0@ == {index}\n",1)[1].split("\n:",1)[0]
                ramps=re.findall(rf"create_object #(NDC_BOATRAMP\w+) at ({NUMBER}) ({NUMBER}) 1@ store_to ([$]\d+)\n00D3: set_object_heading \4 to ({NUMBER})",ramps_block)
                assert ramps and len(ramps)==ramps_block.count("create_object #"),index
                out.append("        },ramps={")
                out.extend('            '+row([f'"{kind.lower()}"',x,y,5.43,yaw])+',' for kind,x,y,_,yaw in ramps)
            out.append("        }},")
        out.append("    },")
    mall=main.split(":BMXMALL_2914\n",1)[1]
    a=mall.index("$5551 = ")
    vals=assignments(mall[a:mall.index(":BMXMALL_",a)])
    out.append("    mallbmx={")
    out.extend("        "+row(vals[k+i] for k in (5551,5601,5651,5701))+"," for i in range(50))
    out.extend(["    },","}",""])
    return "\n".join(out)

def export_ramps(disc,converter):
    sys.path.insert(0,str(converter))
    from convert import StreamAssets, make_model
    from modelnames import NameRegistry
    from ps2 import GameData, Instance, u32
    from renderware import txd
    game=GameData(disc)
    names={0xEDF28213:"ndc_boatramphump",0xA8709809:"ndc_boatrampnarrow",0x4CABC06C:"ndc_boatrampwide"}
    shared=u32(game.data,u32(game.data,u32(game.data,96))+2*28)
    identity=(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)
    with (disc/"GTA3PS2.IMG").open("rb") as archive:
        for model in range(game.model_count):
            ptr=game.model(model)
            name=names.pop(u32(game.data,ptr+8),None) if ptr else None
            if not name: continue
            report=dict(missing_prop_textures={},empty_render_models=[],effects=Counter(),surfaces=Counter())
            assets=StreamAssets(game,archive,model,report,shared_dictionary=shared)
            parts={0:(Instance(0,4,-1,0,(),identity,False),identity,(model,identity,0),None)}
            result=make_model(game,((0,0),-1,model,"high"),parts,assets,{},report,NameRegistry(),name)
            mesh,collision,names_used=result[3],result[4],result[7]
            assert mesh and collision and names_used and not report["missing_prop_textures"],name
            for ext,data in (("dff",mesh),("col",collision),("txd",txd([assets.hashes[t] for t in names_used]))):
                (MISSION/"assets"/f"{name}.{ext}").write_bytes(data)
    assert not names,names

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc",type=Path)
    parser.add_argument("--ramps",action="store_true")
    parser.add_argument("--converter",type=Path,default=ROOT.parent/"mta_map_tools")
    args=parser.parse_args()
    (MISSION/"trials_data.lua").write_text(course_data((args.disc/"MAIN.txt").read_text(encoding="latin1")),encoding="utf8")
    if args.ramps: export_ramps(args.disc,args.converter)
