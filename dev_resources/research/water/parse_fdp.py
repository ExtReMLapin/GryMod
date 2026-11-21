import re,sys
d=open('snd/Sounds/physics/physics.fdp','rb').read().decode('latin1').replace('\r','')
names=sys.argv[1].split(',')
ev={}
for m in re.finditer(r'<event>\n<name>([^<]*)</name>(.*?)\n</event>',d,re.S):
    ev.setdefault(m.group(1),[]).append(m.group(2))
sd={}
for m in re.finditer(r'<sounddef>\n<name>([^<]*)</name>(.*?)</sounddef>',d,re.S):
    sd.setdefault(m.group(1),[]).append(m.group(2))
def g(b,t):
    m=re.search(r'<%s>([^<]*)</%s>'%(t,t),b); return m.group(1) if m else None
for n in names:
    for b in ev.get(n,[]):
        cat=g(b,'category')
        if not cat or 'player_foley' not in cat: continue
        print('EVENT',n,'vol_db',g(b,'volume_db'),'pitch',g(b,'pitch'),'pitchrand',g(b,'pitch_randomization'),'volrand',g(b,'volume_randomization'),'mode',g(b,'mode'),'maxpb',g(b,'maxplaybacks'),'oneshot',g(b,'oneshot'),'fadein',g(b,'fadein_time'),'fadeout',g(b,'fadeout_time'),'cat',cat)
        for s in re.finditer(r'<sound>\n<name>([^<]*)</name>(.*?)</sound>',b,re.S):
            print('  layer sound',s.group(1),'loopmode',g(s.group(2),'loopmode'),'startmode',g(s.group(2),'startmode'),'vol',g(s.group(2),'volume'),'width',g(s.group(2),'width'))
        for l in sd.get(n,[]):
            print('  sounddef type',g(l,'type'),'spawn',g(l,'spawntime_min'),g(l,'spawntime_max'),g(l,'spawn_max'),'pitch',g(l,'pitch'),'vol',g(l,'volume'))
            for w in re.finditer(r'<filename>([^<]*)</filename>.*?<weight>([^<]*)</weight>',l,re.S): print('    ',w.group(1),w.group(2))
