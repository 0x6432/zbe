# Repeatedly build; for optional-pointer misuse errors, insert `.?` at the reported spot.
import re, subprocess, sys
env_path='/data/tools/zig:'
import os
os.environ['PATH']=env_path+os.environ['PATH']
for it in range(400):
    r=subprocess.run(['zig','build'],cwd='/data/qbe-zig',capture_output=True,text=True)
    out=r.stderr
    m=re.search(r"^(src/\S+?):(\d+):(\d+): error: (.*)$",out,re.M)
    if not m:
        print('build ok after',it,'fixes'); sys.exit(0)
    f,l,c,msg=m.group(1),int(m.group(2)),int(m.group(3)),m.group(4)
    p='/data/qbe-zig/'+f
    lines=open(p).read().split('\n')
    s=lines[l-1]
    col=c-1
    if "does not support indexing" in msg and '?[*:0]' in msg:
        # error column points at the '[' or at the expr start; find the '[' after the expr
        j=s.find('[',col) if s[col]!='[' else col
        if s[col]=='[': j=col
        lines[l-1]=s[:j]+'.?'+s[j:]
    elif "cannot convert optional to payload type" in out.split('\n',out.count('\n'))[0] or ("found '?[*:0]" in msg and "expected type '[*:0]" in msg):
        # col points at start of expression; extend over a simple postfix expression
        mm=re.match(r"[A-Za-z_@][\w.\"@]*(\([^()]*\))?(\[[^\]]*\])*(\.[\w@\"]+)*",s[col:])
        e=col+mm.end()
        lines[l-1]=s[:e]+'.?'+s[e:]
    elif "destination pointer requires '0' sentinel" in out and re.match(r"expected type '\??\[\*:0\]const u8', found '\*\[\d+\]u8'", msg):
        mm=re.match(r"&[\w.]+(\[[^\]]*\])*",s[col:])
        e=col+mm.end()
        lines[l-1]=s[:col]+'@ptrCast('+s[col:e]+')'+s[e:]
    else:
        print(out[:1500]); sys.exit(1)
    print('fix',f,l,':',lines[l-1].strip()[:110])
    open(p,'w').write('\n'.join(lines))
print('too many'); sys.exit(1)
