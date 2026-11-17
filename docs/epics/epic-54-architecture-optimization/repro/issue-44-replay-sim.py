import re,sys,math
# 以真機原始事件（DOWN/MOVE/UP，含時間）忠實重播裁切層邏輯，比較不同規則
raw=[l for l in open(sys.argv[1],encoding='utf-8').read().splitlines() if re.match(r'\d+ ',l)]
L=[]
for l in raw:
    parts=l.split(' ',2)
    if re.match(r's\d+$',parts[1]): L.append(l)
    else: L.append(parts[0]+' s0 '+l.split(' ',1)[1])
ev=[]  # (t, kind, id, pos)
for l in L:
    t,s,b=l.split(' ',2);t=int(t)
    if b.startswith('initState'): ev.append((t,'RESET',None,None));continue
    m=re.match(r'DOWN id=(\d+) pos=Offset\(([\d.-]+), ([\d.-]+)\)',b)
    if m: ev.append((t,'DOWN',int(m[1]),(float(m[2]),float(m[3]))));continue
    m=re.match(r'MOVE id=(\d+) pos=Offset\(([\d.-]+), ([\d.-]+)\)',b)
    if m: ev.append((t,'MOVE',int(m[1]),(float(m[2]),float(m[3]))));continue
    m=re.match(r'UP id=(\d+)',b)
    if m: ev.append((t,'UP',int(m[1]),None))
R=150.0;PROMO=8.0;GRACE=250;IDLE=150
def d(a,b):return math.hypot(a[0]-b[0],a[1]-b[1])
RESTARTS={}
def sim(variant):
    RESTARTS[variant]=0
    P={};start=cur=None;leader=None;lact=-10**9;seq=0;pend=None
    out=[]  # (t, cur)  每次 cur 改變
    def promote(i,p,t,lead=True):
        nonlocal seq,leader,lact
        p['pro']=True;seq+=1;p['seq']=seq
        if lead: leader=i;lact=t
    for t,k,i,pos in ev:
        if pend is not None and t>=pend and not any(p['pro'] for p in P.values()):
            start=cur=None;pend=None;leader=None
        if k=='RESET': P={};start=cur=None;leader=None;pend=None;out.append((t,None));continue
        if k=='DOWN':
            p={'pos':pos,'down':pos,'pro':False,'seq':0,'moved':False}
            if start is not None:
                if d(pos,cur)<=R:
                    # v5：靠近按下的新 pointer 先升格，但等它真的動了才領頭
                    promote(i,p,t,lead=(variant not in('v5','v6') or leader not in P));pend=None
                elif not any(q['pro'] for q in P.values()):
                    if variant=='v6' and pend is not None:
                        promote(i,p,t,lead=True);pend=None   # 寬限期內：任何距離都接力
                    else:
                        start=cur=pos;promote(i,p,t);pend=None;RESTARTS[variant]+=1
            else:
                start=cur=pos;promote(i,p,t);RESTARTS[variant]+=1
            P[i]=p
        elif k=='MOVE':
            p=P.get(i)
            if not p: continue
            ch=pos!=p['pos'];p['pos']=pos
            if not p['pro']:
                if d(pos,p['down'])<PROMO: continue
                promote(i,p,t);pend=None
            elif variant in('v4','v5','v6') and leader!=i:
                if variant in('v5','v6'):
                    # 新 pointer 第一次真的移動：接手領頭
                    if not p['moved'] and ch and p['seq']>(P[leader]['seq'] if leader in P else 0):
                        leader=i
                    elif t-lact<IDLE: 
                        p['moved']=p['moved'] or ch
                        continue
                    elif not ch: continue
                    else: leader=i
                else:
                    if t-lact<IDLE: continue
                    if not ch: continue
                    leader=i
            if variant in('v5','v6'): p['moved']=p['moved'] or ch
            if not ch: continue
            lact=t;cur=pos;out.append((t,cur))
        elif k=='UP':
            p=P.pop(i,None)
            if p and p['pro']:
                if leader==i:
                    best=None;bs=-1
                    for j,q in P.items():
                        if q['pro'] and q['seq']>bs: best,bs=j,q['seq']
                    leader=best;lact=t
                if not any(q['pro'] for q in P.values()) and start is not None: pend=t+GRACE
    return out
def restarts(variant):
    # 一次連續操作中，起點被重設的次數（start 重新指定）
    P={};start=None;pend=None;n=0
    return n
def metrics(out):
    segs=[];s=[]
    for t,c in out:
        if c is None: segs.append(s);s=[]
        else: s.append((t,c))
    segs.append(s)
    rev=0;steps=0;big=0;pathlen=0
    for s in segs:
        for (t0,a),(t1,b),(t2,c) in zip(s,s[1:],s[2:]):
            ab=d(a,b);bc=d(b,c);steps+=1;pathlen+=ab
            if ab>50 and bc>50 and d(a,c)<0.5*max(ab,bc): rev+=1   # 跳出去又跳回
            if ab>100: big+=1
    return rev,big,steps
for v in ('v3','v4','v5','v6'):
    r,b,n=metrics(sim(v))
    print(f"{v}: 起點重設={RESTARTS[v]:3d}  來回跳={r:3d}  單次跳>100px={b:3d}  更新數={n}")
