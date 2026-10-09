# stage 9a: library mode (Zig API + C ABI) and CLI quality of life
R='/data/qbe-zig/'
def fix(f, a, b, n=1):
    p=R+f; s=open(p).read()
    assert s.count(a)==n,(f,a,s.count(a))
    open(p,'w').write(s.replace(a,b))

M='src/main.zig'
for a in ['fn Deftgt() *Target {', 'var tlist: [7]?*Target', 'fn inittargets() void {',
          'var outf: *Writer = undefined;', 'var dbg = false;', 'fn data(d: *Dat) void {',
          'fn func(f: *Fn) void {', 'fn dbgfile(f: [*:0]const u8) void {']:
    fix(M, '\n'+a, '\npub '+a)

# --help, --version, --list-targets (not in upstream-compat mode)
fix(M, '''        if (std.mem.eql(u8, arg, "--")) {
            noopts = true;
            continue;
        }''',
'''        if (std.mem.eql(u8, arg, "--")) {
            noopts = true;
            continue;
        }
        if (!all.compat and arg[1] == '-') {
            if (std.mem.eql(u8, arg, "--help")) usageExit(prog, 0);
            if (std.mem.eql(u8, arg, "--version")) {
                outf.print("qbe (zig port) {s}\\n", .{version}) catch writeFailed();
                outf.flush() catch writeFailed();
                std.process.exit(0);
            }
            if (std.mem.eql(u8, arg, "--list-targets")) {
                for (tlist) |tp| {
                    const t = tp orelse break;
                    outf.print("{s}{s}\\n", .{ cs(&t.name), if (t == Deftgt()) " (default)" else "" }) catch writeFailed();
                }
                outf.flush() catch writeFailed();
                std.process.exit(0);
            }
            dprint("{s}: unrecognized option '{s}'\\n", .{ prog, arg });
            usageExit(prog, 1);
        }''')
fix(M, 'pub fn Deftgt() *Target {', 'pub const version = "1.4.0-zig";\n\npub fn Deftgt() *Target {')
fix(M, '''    try hf.print("\\t{s:<11} by constants (default: 2)\\n", .{""});''',
'''    try hf.print("\\t{s:<11} by constants (default: 2)\\n", .{""});
    try hf.print("\\t{s:<11} list targets\\n", .{"--list-targets"});
    try hf.print("\\t{s:<11} print the version\\n", .{"--version"});
    try hf.print("\\t{s:<11} QBE_COMPAT=1 in the environment = -O0 + upstream CLI\\n", .{""});''')
print('ok')
