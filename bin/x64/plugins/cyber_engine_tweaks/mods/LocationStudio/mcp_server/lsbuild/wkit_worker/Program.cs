using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

static void Emit(object value) => Console.WriteLine(JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = false }));
static string? Arg(string[] a, string name) { var i = Array.IndexOf(a, name); return i >= 0 && i + 1 < a.Length ? a[i + 1] : null; }
try
{
    var cmd = args.Length == 0 ? "help" : args[0];
    var rest = args.Skip(1).ToArray();
    var bridge = new WkitBridge();
    if (cmd == "selftest")
    {
        var r = bridge.SelfTest(); Emit(r); return bridge.LastSelfTestReady ? 0 : 2;
    }
    if (cmd == "inspect")
    {
        Emit(bridge.Inspect()); return 0;
    }
    if (cmd == "templates")
    {
        var typesPath = Arg(rest, "--types") ?? throw new ArgumentException("--types required");
        var output = Arg(rest, "--output") ?? throw new ArgumentException("--output required");
        var types = JsonSerializer.Deserialize<List<string>>(File.ReadAllText(typesPath)) ?? new();
        var result = bridge.CreateBundle(types, output); Emit(result); return 0;
    }
    if (cmd == "deserialize")
    {
        var input = Arg(rest, "--input") ?? throw new ArgumentException("--input required");
        var output = Arg(rest, "--output") ?? throw new ArgumentException("--output required");
        var result = bridge.DeserializeToCr2w(input, output); Emit(result); return 0;
    }
    Emit(new { protocol = WkitBridge.Protocol, commands = new[] { "selftest", "inspect", "templates --types FILE --output FILE", "deserialize --input FILE --output FILE" } });
    return 0;
}
catch (Exception ex)
{
    Emit(new { protocol = WkitBridge.Protocol, error = ex.Message, detail = ex.ToString() });
    return 1;
}

sealed class WkitBridge
{
    public const string Protocol = "cp77wb-wkit-worker/1";
    public const string TemplateSchema = "cp77wb-wkit-templates/1";

    readonly Assembly red4;
    readonly List<Type> allTypes;
    readonly Type? serializerType;
    readonly Type? writerType;
    public bool LastSelfTestReady { get; private set; }

    public WkitBridge()
    {
        red4 = Assembly.Load("WolvenKit.RED4");
        foreach (var dep in new[] { "WolvenKit.Core", "WolvenKit.Common" }) { try { Assembly.Load(dep); } catch { } }
        allTypes = AppDomain.CurrentDomain.GetAssemblies().SelectMany(SafeTypes).ToList();
        serializerType = allTypes.FirstOrDefault(t => t.Name == "RedJsonSerializer");
        writerType = allTypes.FirstOrDefault(t => t.Name == "CR2WWriter");
    }

    static IEnumerable<Type> SafeTypes(Assembly a) { try { return a.GetTypes(); } catch (ReflectionTypeLoadException e) { return e.Types.Where(t => t is not null).Cast<Type>(); } }
    string WkitVersion => red4.GetName().Version?.ToString() ?? "unknown";

    Type ResolveRedType(string redName)
    {
        var exact = allTypes.Where(t => t.Name == redName && (t.Namespace?.Contains("WolvenKit.RED4.Types") ?? false)).ToList();
        if (exact.Count == 1) return exact[0];
        exact = allTypes.Where(t => string.Equals(t.Name, redName, StringComparison.Ordinal)).ToList();
        if (exact.Count == 1) return exact[0];
        throw new InvalidOperationException($"RED type {redName} not found uniquely ({exact.Count} candidates)");
    }

    object NewRed(string redName) => Activator.CreateInstance(ResolveRedType(redName)) ?? throw new InvalidOperationException($"Cannot create {redName}");

    string SerializeRed(object value)
    {
        if (serializerType == null) throw new InvalidOperationException("RedJsonSerializer type not found");
        var methods = serializerType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance)
            .Where(m => m.Name.Contains("Serialize", StringComparison.OrdinalIgnoreCase)).ToList();
        foreach (var m0 in methods)
        {
            var m = m0.IsGenericMethodDefinition ? TryCloseGeneric(m0, value.GetType()) : m0;
            if (m == null) continue;
            var target = m.IsStatic ? null : TryCreate(serializerType);
            if (!m.IsStatic && target == null) continue;
            if (!TryBind(m.GetParameters(), value, null, out var argv, out var capture)) continue;
            try
            {
                var r = m.Invoke(target, argv);
                if (r is string s && LooksJson(s)) return ExtractRootIfCr2w(s);
                if (capture is MemoryStream ms)
                {
                    var s2 = Encoding.UTF8.GetString(ms.ToArray()); if (LooksJson(s2)) return ExtractRootIfCr2w(s2);
                }
            }
            catch { }
        }
        throw new InvalidOperationException("No compatible RedJsonSerializer Serialize method discovered");
    }

    static string ExtractRootIfCr2w(string json)
    {
        try { var n = JsonNode.Parse(json); var root = n?["Data"]?["RootChunk"]; if (root != null) return root.ToJsonString(); } catch { }
        return json;
    }
    static bool LooksJson(string s) { var t = s.TrimStart(); return t.StartsWith("{") || t.StartsWith("["); }
    static MethodInfo? TryCloseGeneric(MethodInfo m, Type t) { try { var ga=m.GetGenericArguments(); return ga.Length==1 ? m.MakeGenericMethod(t) : null; } catch { return null; } }
    static object? TryCreate(Type t) { try { return Activator.CreateInstance(t); } catch { return null; } }

    static bool TryBind(ParameterInfo[] ps, object primary, string? json, out object?[] args, out object? capture)
    {
        args = new object?[ps.Length]; capture = null; var usedPrimary = false;
        for (var i=0;i<ps.Length;i++)
        {
            var p=ps[i]; var pt=p.ParameterType;
            if (!usedPrimary && (pt==typeof(object) || pt.IsAssignableFrom(primary.GetType()))) { args[i]=primary; usedPrimary=true; continue; }
            if (json != null && pt==typeof(string)) { args[i]=json; continue; }
            if (typeof(Stream).IsAssignableFrom(pt)) { var ms=new MemoryStream(); args[i]=ms; capture=ms; continue; }
            if (typeof(TextWriter).IsAssignableFrom(pt)) { var sw=new StringWriter(); args[i]=sw; capture=sw; continue; }
            if (p.HasDefaultValue) { args[i]=p.DefaultValue; continue; }
            if (!pt.IsValueType || Nullable.GetUnderlyingType(pt)!=null) { args[i]=null; continue; }
            return false;
        }
        return usedPrimary || json != null;
    }

    object DeserializeCr2w(string json)
    {
        if (serializerType == null) throw new InvalidOperationException("RedJsonSerializer type not found");
        foreach (var m in serializerType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance)
                     .Where(m => m.Name.Contains("Deserialize", StringComparison.OrdinalIgnoreCase)))
        {
            if (m.ContainsGenericParameters) continue;
            var target=m.IsStatic?null:TryCreate(serializerType); if(!m.IsStatic&&target==null) continue;
            var ps=m.GetParameters(); var argv=new object?[ps.Length]; var bound=false; var streams=new List<IDisposable>();
            try
            {
                for(var i=0;i<ps.Length;i++)
                {
                    var p=ps[i]; var pt=p.ParameterType;
                    if(!bound && pt==typeof(string)){argv[i]=json;bound=true;continue;}
                    if(!bound && typeof(Stream).IsAssignableFrom(pt)){var ms=new MemoryStream(Encoding.UTF8.GetBytes(json));streams.Add(ms);argv[i]=ms;bound=true;continue;}
                    if(!bound && typeof(TextReader).IsAssignableFrom(pt)){var sr=new StringReader(json);streams.Add(sr);argv[i]=sr;bound=true;continue;}
                    if(p.HasDefaultValue){argv[i]=p.DefaultValue;continue;}
                    if(!pt.IsValueType||Nullable.GetUnderlyingType(pt)!=null){argv[i]=null;continue;}
                    bound=false;break;
                }
                if(!bound) continue;
                var r=m.Invoke(target,argv); if(r!=null) return r;
            }
            catch { }
            finally { foreach(var x in streams)x.Dispose(); }
        }
        throw new InvalidOperationException("No compatible RedJsonSerializer Deserialize method discovered");
    }

    bool WriteCr2w(object file, string output, out string method)
    {
        method=""; if(writerType==null) return false;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
        using var fs=File.Create(output);
        foreach(var ctor in writerType.GetConstructors(BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance).OrderBy(c=>c.GetParameters().Length))
        {
            fs.SetLength(0); fs.Position=0;
            if(!BindWriterCtor(ctor.GetParameters(),fs,out var cargs))continue;
            object? writer=null; try{writer=ctor.Invoke(cargs);}catch{continue;}
            foreach(var m in writerType.GetMethods(BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance)
                        .Where(m=>m.Name.Contains("Write",StringComparison.OrdinalIgnoreCase)))
            {
                if(!TryBindWriterMethod(m.GetParameters(),file,out var a))continue;
                try{m.Invoke(writer,a);fs.Flush(); if(fs.Length>=4){fs.Position=0;var b=new byte[4];fs.ReadExactly(b); if(Encoding.ASCII.GetString(b)=="CR2W"){method=$"{writerType.FullName}.{m.Name}";return true;}}}catch{}
            }
        }
        return false;
    }
    static bool BindWriterCtor(ParameterInfo[] ps, Stream stream, out object?[] args)
    { args=new object?[ps.Length]; for(var i=0;i<ps.Length;i++){var p=ps[i]; if(typeof(Stream).IsAssignableFrom(p.ParameterType)){args[i]=stream;continue;} if(p.HasDefaultValue){args[i]=p.DefaultValue;continue;} if(!p.ParameterType.IsValueType||Nullable.GetUnderlyingType(p.ParameterType)!=null){args[i]=null;continue;} return false;} return ps.Any(p=>typeof(Stream).IsAssignableFrom(p.ParameterType)); }
    static bool TryBindWriterMethod(ParameterInfo[] ps, object file, out object?[] args)
    { args=new object?[ps.Length];var used=false;for(var i=0;i<ps.Length;i++){var p=ps[i];if(!used&&(p.ParameterType==typeof(object)||p.ParameterType.IsAssignableFrom(file.GetType()))){args[i]=file;used=true;continue;}if(p.HasDefaultValue){args[i]=p.DefaultValue;continue;}if(!p.ParameterType.IsValueType||Nullable.GetUnderlyingType(p.ParameterType)!=null){args[i]=null;continue;}return false;}return used; }

    string MakeCr2wJson(string rootJson)
    {
        var root=JsonNode.Parse(rootJson) ?? throw new InvalidOperationException("serialized RED root is empty");
        var doc=new JsonObject{
            ["Header"]=new JsonObject{{"WolvenKitVersion",WkitVersion},{"WKitJsonVersion","0.0.8"},{"DataType","CR2W"}},
            ["Data"]=new JsonObject{{"Version",195},{"BuildVersion",0},{"RootChunk",root},{"EmbeddedFiles",new JsonArray()}}
        };
        return doc.ToJsonString();
    }

    static string MethodSignature(MethodBase m)
    {
        var ps = string.Join(",", m.GetParameters().Select(p => $"{p.ParameterType.FullName ?? p.ParameterType.Name}:{p.Name}"));
        var ret = m is MethodInfo mi ? (mi.ReturnType.FullName ?? mi.ReturnType.Name) : ".ctor";
        return $"{m.DeclaringType?.FullName}::{m.Name}({ps})->{ret}";
    }

    string ApiProfile()
    {
        var sigs = new List<string>();
        if (serializerType != null)
            sigs.AddRange(serializerType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance)
                .Where(m => m.Name.Contains("Serialize", StringComparison.OrdinalIgnoreCase) || m.Name.Contains("Deserialize", StringComparison.OrdinalIgnoreCase))
                .Select(MethodSignature));
        if (writerType != null)
        {
            sigs.AddRange(writerType.GetConstructors(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance).Select(MethodSignature));
            sigs.AddRange(writerType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                .Where(m => m.Name.Contains("Write", StringComparison.OrdinalIgnoreCase)).Select(MethodSignature));
        }
        sigs.Sort(StringComparer.Ordinal);
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("\n", sigs)));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public object Inspect()
    {
        var wkitAssemblies = AppDomain.CurrentDomain.GetAssemblies()
            .Where(a => (a.GetName().Name ?? "").StartsWith("WolvenKit", StringComparison.OrdinalIgnoreCase))
            .OrderBy(a => a.GetName().Name)
            .Select(a => new { name = a.GetName().Name, version = a.GetName().Version?.ToString(), location = SafeLocation(a) })
            .ToArray();
        var serializerMethods = serializerType == null ? Array.Empty<string>() : serializerType
            .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance)
            .Where(m => m.Name.Contains("Serialize", StringComparison.OrdinalIgnoreCase) || m.Name.Contains("Deserialize", StringComparison.OrdinalIgnoreCase))
            .Select(MethodSignature).OrderBy(x => x).ToArray();
        var writerConstructors = writerType == null ? Array.Empty<string>() : writerType
            .GetConstructors(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
            .Select(MethodSignature).OrderBy(x => x).ToArray();
        var writerMethods = writerType == null ? Array.Empty<string>() : writerType
            .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
            .Where(m => m.Name.Contains("Write", StringComparison.OrdinalIgnoreCase))
            .Select(MethodSignature).OrderBy(x => x).ToArray();
        return new {
            protocol = WkitBridge.Protocol, apiProfile = ApiProfile(), wolvenKitVersion = WkitVersion,
            dotnetVersion = Environment.Version.ToString(), framework = RuntimeInformation.FrameworkDescription,
            os = RuntimeInformation.OSDescription, architecture = RuntimeInformation.ProcessArchitecture.ToString(),
            baseDirectory = AppContext.BaseDirectory,
            discovery = new {
                red4 = red4.FullName, serializer = serializerType?.FullName, writer = writerType?.FullName,
                redTypeCount = allTypes.Count(t => t.Namespace?.Contains("WolvenKit.RED4.Types") == true),
                assemblies = wkitAssemblies, serializerMethods, writerConstructors, writerMethods
            }
        };
    }

    static string? SafeLocation(Assembly a) { try { return a.Location; } catch { return null; } }

    public object SelfTest()
    {
        bool create=false, cr2w=false; string? reason=null; string? writeMethod=null;
        try
        {
            var root=NewRed("worldStreamingBlock"); var rootJson=SerializeRed(root); create=LooksJson(rootJson);
            var file=DeserializeCr2w(MakeCr2wJson(rootJson));
            var tmp=Path.Combine(Path.GetTempPath(),$"cp77wb-worker-{Guid.NewGuid():N}.streamingblock");
            try{cr2w=WriteCr2w(file,tmp,out writeMethod)&&File.ReadAllBytes(tmp).Take(4).SequenceEqual("CR2W"u8.ToArray());}finally{try{File.Delete(tmp);}catch{}}
        }
        catch(Exception ex){reason=ex.Message;}
        var discovery=new{red4=red4.FullName,serializer=serializerType?.FullName,writer=writerType?.FullName,writeMethod};
        LastSelfTestReady = create && cr2w;
        return new { ready=LastSelfTestReady, protocol=Protocol, apiProfile=ApiProfile(), wolvenKitVersion=WkitVersion, dotnetVersion=Environment.Version.ToString(), capabilities=new{createTemplates=create,jsonToCr2w=cr2w}, reason, discovery };
    }

    public object CreateBundle(List<string> types, string output)
    {
        var dict=new Dictionary<string,JsonNode?>();
        foreach(var name in types){var json=SerializeRed(NewRed(name));dict[name]=JsonNode.Parse(json);}
        var result=new JsonObject{{"schema",TemplateSchema},{"generatedBy","cp77wb-wkit-worker"},{"wolvenKitVersion",WkitVersion},{"wkitJsonVersion","0.0.8"}};
        var typeObj=new JsonObject();foreach(var kv in dict)typeObj[kv.Key]=kv.Value;result["types"]=typeObj;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);File.WriteAllText(output,result.ToJsonString());
        return new { ok=true, protocol=Protocol, output=Path.GetFullPath(output), count=types.Count, wolvenKitVersion=WkitVersion };
    }

    public object DeserializeToCr2w(string input, string output)
    {
        var file=DeserializeCr2w(File.ReadAllText(input));
        if(!WriteCr2w(file,output,out var method))throw new InvalidOperationException("No compatible CR2W writer method produced CR2W output");
        return new { ok=true, protocol=Protocol, input=Path.GetFullPath(input), output=Path.GetFullPath(output), writer=method };
    }
}
