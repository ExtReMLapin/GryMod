import sys, xml.etree.ElementTree as ET
t=ET.parse('qm.xml'); root=t.getroot()
tags=root.find('tags')
def mat(p):
    m=p.find('matrix')
    if m is None: return ''
    g=lambda k,d='0': float(m.get(k,d))
    sx=g('scaleX','1') if m.get('hasScale')=='true' else 1; sy=g('scaleY','1') if m.get('hasScale')=='true' else 1
    r0=g('rotateSkew0') ; r1=g('rotateSkew1')
    return 'T(%.1f,%.1f) S(%.3f,%.3f)%s'%(g('translateX')/20,g('translateY')/20,sx,sy,(' R(%.3f,%.3f)'%(r0,r1)) if m.get('hasRotate')=='true' else '')
def cx(p):
    c=p.find('colorTransform')
    if c is None: return ''
    s=''
    if c.get('hasMultTerms')=='true': s+=' mul(%s,%s,%s,%s)'%(c.get('redMultTerm'),c.get('greenMultTerm'),c.get('blueMultTerm'),c.get('alphaMultTerm'))
    if c.get('hasAddTerms')=='true': s+=' add(%s,%s,%s,%s)'%(c.get('redAddTerm'),c.get('greenAddTerm'),c.get('blueAddTerm'),c.get('alphaAddTerm'))
    return s
def dump(tl,indent=''):
    f=1
    for it in tl:
        ty=it.get('type')
        if ty=='ShowFrameTag': f+=1
        elif ty=='FrameLabelTag': print(indent,'f%d LABEL %s'%(f,it.get('name')))
        elif ty.startswith('PlaceObject'):
            print(indent,'f%d PLACE d%s char=%s name=%s move=%s clip=%s blend=%s ratio=%s %s%s'%(f,it.get('depth'),it.get('characterId'),it.get('name'),it.get('placeFlagMove'),it.get('clipDepth'),it.get('blendMode'),it.get('ratio'),mat(it),cx(it)))
        elif ty=='RemoveObject2Tag': print(indent,'f%d REMOVE d%s'%(f,it.get('depth')))
        elif ty=='DoActionTag': print(indent,'f%d ACTION'%f)
which=sys.argv[1]
if which=='root':
    dump([i for i in tags if i.get('type') not in ('DefineSpriteTag',)])
else:
    for i in tags:
        if i.get('type')=='DefineSpriteTag' and i.get('spriteId')==which:
            print('SPRITE',which,'frames',i.get('frameCount')); dump(i.find('subTags'))
