import json,sys,urllib.request,urllib.error
K="sb_publishable_FHN4ODlO5E4bt0ezliSoqQ_3CgYEyQs"
BASE="https://api.zeniptv.app/rest/v1/"
import os
S=json.load(open(os.environ.get("MIZU_SESSION", os.path.expanduser("~/.config/mizu/session.json"))))
T=S["access_token"]
def q(path):
    req=urllib.request.Request(BASE+path,headers={"apikey":K,"Authorization":f"Bearer {T}"})
    try:
        with urllib.request.urlopen(req,timeout=25) as r: return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {"__error__":e.code,"body":e.read(300).decode()}
out={}
for name,path in [
  ("watch_profiles","watch_profiles?select=*"),
  ("user_preferences","user_preferences?select=*"),
  ("playlist_sources","playlist_sources?select=*"),
  ("favorites","favorites?select=*&limit=50&order=sort_order"),
  ("serie_progress","serie_progress?select=*&limit=50&order=last_watched.desc"),
  ("masked_categories","masked_categories?select=*&limit=5"),
  ("tmdb_mappings","tmdb_mappings?select=*&limit=5"),
]:
    out[name]=q(path)
json.dump(out,open("re/live-dump.json","w"),indent=2,ensure_ascii=False)
for k,v in out.items():
    if isinstance(v,dict) and "__error__" in v:
        print(f"{k}: ERREUR {v}"); continue
    print(f"{k}: {len(v)} ligne(s)")
print("\n--- profils ---"); print(json.dumps(out["watch_profiles"],ensure_ascii=False,indent=1)[:800])
print("\n--- prefs ---"); print(json.dumps(out["user_preferences"],ensure_ascii=False,indent=1)[:1200])
print("\n--- sources (mdp masqué) ---")
for s in out["playlist_sources"]:
    m=dict(s); 
    if m.get("password"): m["password"]="***"
    print(json.dumps(m,ensure_ascii=False))
