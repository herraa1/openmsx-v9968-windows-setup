"""Validate all merged records against the original mathematical sampling."""
from pathlib import Path
import json, math
root=Path(__file__).resolve().parent
layout=json.loads((root/'assets/bank-layout.json').read_text())
data=(root/'assets/megarom-data.bin').read_bytes()
assert layout['WATER']['bytes']==256*512
start=(layout['WATER']['bank']-1)*16384
assert 0<=start and start+256*512<=len(data)
largest_error=0
commands=[]
for phase in range(256):
    record=data[start+phase*512:start+(phase+1)*512]
    n=record[0];assert 0<n and 1+n*5<=512
    y=0;shifted=0
    for i in range(n):
        sx,dx,w,sy,h=record[1+i*5:6+i*5]
        assert h>0 and h%2==0 and sy+h<=192 and y+h<=192
        assert (sx,dx,w) in ((0,0,0),(0,2,254),(2,0,254))
        # Main copy plus two clamped edge pixels covers every horizontal pixel.
        width=w or 256
        covered=set(range(dx,dx+width))
        if dx: covered.update((0,1))
        elif sx: covered.update((254,255))
        assert covered==set(range(256))
        shifted+=bool(sx or dx)
        for offset in range(0,h,2):
            yy=y+offset
            reference=max(0,min(190,yy+4*math.sin((yy+1)*math.tau/64-phase*math.tau/256)))
            error=abs((sy+offset)-reference)
            assert error<=0.5000001,(phase,yy,sy+offset,reference)
            horizontal=2*round(math.sin((yy+1)*math.tau/96-phase*math.tau/256))
            assert (sx,dx)==(max(0,-horizontal),max(0,horizontal))
            largest_error=max(largest_error,error)
        y+=h
    assert y==192
    commands.append(n+2*shifted)
identity=(layout['IDENTITY']['bank']-1)*16384
assert data[identity:identity+6]==bytes((1,0,0,0,0,192))
print(json.dumps({'phases':256,'rows':49152,'two_row_bands':24576,
                  'mean_commands':sum(commands)/256,'max_sampling_error_pixels':largest_error,
                  'identity_exact':True,'pass':True},indent=2))
