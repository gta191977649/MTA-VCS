from pathlib import Path
import re,struct,zlib,sys
sys.path.insert(0,'tools')
import import_vcs_traffic as v
from vcs_model_assets import build_img,native_textures,complete_vehicle_textures,build_texture_dictionary
p=Path('mods/deathmatch/resources/[model]/vcs_model'); source=v.MODEL_RESOURCE/'src/vehicle'
raw=zlib.decompress(Path(r'D:/ps2_game/Grand Theft Auto - Vice City Stories (USA)/PS2/GAME.DTZ').read_bytes()); _,_,table=v.read_vehicle_bindings(raw,v.MODEL_RESOURCE)
cat=(p/'model_catalog.lua').read_text(); wanted=set(re.findall(r'"(\w+)"',Path('mods/deathmatch/resources/[feature]/placement/car_park/spawns.lua').read_text()))-set(re.findall(r'name = "([^"]+)"',cat))
blob=(p/'vehicle.img').read_bytes(); entries={}
for i in range(struct.unpack_from('<I',blob,4)[0]):
 sector,size,_,name=struct.unpack_from('<IHH24s',blob,8+32*i); name=name.split(b'\0')[0].decode(); data=blob[sector*2048:(sector+size)*2048]; entries[name]=data[:12+struct.unpack_from('<I',data,4)[0]]
shared=native_textures(entries['vehshare.txd']); donors={}
for f in source.iterdir():
 if f.suffix.lower()=='.txd':
  try: donors.update(native_textures(f.read_bytes()))
  except (ValueError,struct.error): pass
shared.update(donors)
manifest=(v.MODEL_RESOURCE/'mod.lua').read_text(); blocks={Path(m[2]).stem.lower():m[1] for m in re.finditer(r'\["[^"]+"\]\s*=\s*\{([^{}]*?dff\s*=\s*"([^"]+)"[^{}]*)\}',manifest)}
files={f.name.lower():f for f in source.iterdir()}; additions=[]
for name in sorted(wanted):
 ids=[i for i in range(171,281) if (ptr:=struct.unpack_from('<I',raw,table+i*4)[0]) and struct.unpack_from('<I',raw,ptr+8)[0]==v.model_name_key(name)]; assert len(ids)==1,name
 asset={'pheonix':'phoenix','sabretb':'sabret'}.get(name,name); mesh='sabretb' if name=='sabretb' else asset
 match=re.search(r'parent\s*=\s*(\d+)',blocks.get(mesh,'')); base={'policem':596,'electrag':463,'pheonix':603,'sabretb':475}.get(name,int(match[1]) if match else 0);assert base,name
 dff=files[mesh+'.dff'].read_bytes();txd=files[asset+'.txd'].read_bytes()
 dff=dff[:12+struct.unpack_from('<I',dff,4)[0]];txd=txd[:12+struct.unpack_from('<I',txd,4)[0]]
 dff,txd,common=complete_vehicle_textures(dff,txd,shared,{},name,{})
 entries[name+'.dff']=dff; entries[name+'.txd']=txd
 shared.update(common)
 variant = '' if name == 'policem' else ', variant = true'
 additions.append(f'    [{ids[0]}] = {{kind = "vehicle", base = {base}, name = "{name}"{variant}}},')
 print(name,ids[0],base)
entries['vehshare.txd']=build_texture_dictionary(shared,entries['vehshare.txd'][26:28])
(p/'vehicle.img').write_bytes(build_img(entries)); (p/'model_catalog.lua').write_text(cat.rsplit('}',1)[0]+'\n'.join(additions)+'\n}\n')
