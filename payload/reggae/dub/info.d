module reggae.dub.info;

import reggae.build;
import reggae.rules;
import reggae.types;
import reggae.sorting;

public import std.typecons: Yes, No;
import std.typecons: Flag;
import std.algorithm: map, filter, find, splitter;
import std.array: array, join;
import std.path: buildPath;
import std.traits: isCallable;
import std.range: chain;

enum TargetType {
    autodetect,
    none,
    executable,
    library,
    sourceLibrary,
    dynamicLibrary,
    staticLibrary,
    object,
}


struct DubPackage {
    string name;
    string path;
    string mainSourceFile;
    string targetFileName;
    string[] dflags;
    string[] lflags;
    string[] importPaths;
    string[] stringImportPaths;
    string[] files;
    TargetType targetType;
    string[] versions;
    string[] dependencies;
    string[] libs;
    bool active;
    string[] preBuildCommands;
    string[] postBuildCommands;

    string toString() @safe pure const {
        import std.string: join;
        import std.conv: to;
        import std.traits: Unqual;

        auto ret = `DubPackage(`;
        string[] lines;

        foreach(ref elt; this.tupleof) {
            static if(is(Unqual!(typeof(elt)) == TargetType))
                lines ~= `TargetType.` ~ elt.to!string;
            else static if(is(Unqual!(typeof(elt)) == string))
                lines ~= `"` ~ elt.to!string ~ `"`;
            else
                lines ~= elt.to!string;
        }
        ret ~= lines.join(`, `);
        ret ~= `)`;
        return ret;
    }

    DubPackage dup() @safe pure nothrow const {
        DubPackage ret;
        foreach(i, member; this.tupleof) {
            static if(__traits(compiles, member.dup))
                ret.tupleof[i] = member.dup;
            else
                ret.tupleof[i] = member;
        }
        return ret;
    }
}

bool isStaticLibrary(in string fileName) @safe pure nothrow {
    import std.path: extension;
    return fileName.extension == ".a";
}

bool isObjectFile(in string fileName) @safe pure nothrow {
    import reggae.rules.common: objExt;
    import std.path: extension;
    return fileName.extension == objExt;
}

string inDubPackagePath(in string packagePath, in string filePath) @safe pure nothrow {
    import std.path: buildPath;
    import std.algorithm: startsWith;
    return filePath.startsWith("$project")
        ? filePath
        : buildPath(packagePath, filePath);
}

struct DubInfo {

    DubPackage[] packages;

    DubInfo dup() @safe pure nothrow const {
        import std.algorithm: map;
        import std.array: array;
        return DubInfo(packages.map!(a => a.dup).array);
    }

    Target[] toTargets(Flag!"main" includeMain = Yes.main,
                       in string compilerFlags = "",
                       Flag!"allTogether" allTogether = No.allTogether) @safe const {

        import reggae.config: options;
        import std.functional: not;

        Target[] targets;

        // -unittest should only apply to the main package
        string deUnitTest(T)(in T index, in string flags) {
            import std.string: replace;
            return index == 0
                ? flags
                : flags.replace("-unittest", "").replace("-main", "");
        }

        foreach(const i, const dubPackage; packages) {
            const importPaths = allImportPaths();
            const stringImportPaths = dubPackage.allOf!(a => a.packagePaths(a.stringImportPaths))(packages);

            //the path must be explicit for the other packages, implicit for the "main"
            //package
            const projDir = i == 0 ? "" : dubPackage.path;

            const sharedFlag = targetType == TargetType.dynamicLibrary ? ["-fPIC"] : [];
            immutable flags = chain(dubPackage.dflags,
                                    dubPackage.versions.map!(a => "-version=" ~ a).array,
                                    [options.dflags],
                                    sharedFlag,
                                    [deUnitTest(i, compilerFlags)])
                .join(" ");

            const files = dubPackage.files.
                filter!(a => includeMain || a != dubPackage.mainSourceFile).
                filter!(not!isStaticLibrary).
                filter!(not!isObjectFile).
                map!(a => buildPath(dubPackage.path, a))
                .array;

            auto func = allTogether ? &dlangPackageObjectFilesTogether : &dlangPackageObjectFiles;
            targets ~= func(files, flags, importPaths, stringImportPaths, projDir);
            // add any object files that are meant to be linked
            targets ~= dubPackage
                .files
                .filter!isObjectFile
                .map!(a => Target(inDubPackagePath(dubPackage.path, a)))
                .array;
        }

        return targets ~ allStaticLibrarySources;
    }

    TargetName targetName() @safe const pure nothrow {
        const fileName = packages[0].targetFileName;
        switch(targetType) with(TargetType) {
        default:
            return TargetName(fileName);
        case library:
            return TargetName("lib" ~ fileName ~ ".a");
        case dynamicLibrary:
            return TargetName("lib" ~ fileName ~ ".so");
        }
    }

    TargetType targetType() @safe const pure nothrow {
        return packages[0].targetType;
    }

    string[] mainLinkerFlags() @safe pure nothrow const {
        import std.array: join;

        const pack = packages[0];
        return (pack.targetType == TargetType.library || pack.targetType == TargetType.staticLibrary)
            ? ["-shared"]
            : [];
    }

    string[] linkerFlags() @safe const pure nothrow {
        const allLibs = packages.map!(a => a.libs).join;
        return
            allLibs.map!(a => "-L-l" ~ a).array ~
            packages.map!(a => a.lflags.map!(b => "-L" ~ b)).join;
    }

    string[] allImportPaths() @safe nothrow const {
        import reggae.config: options;

        string[] paths;
        auto rng = packages.map!(a => a.packagePaths(a.importPaths));
        foreach(p; rng) paths ~= p;
        return paths ~ options.projectPath;
    }

    // must be at the very end
    private Target[] allStaticLibrarySources() @trusted nothrow const pure {
        import std.algorithm: filter, map;
        import std.array: array, join;
        return packages.
            map!(a => cast(string[])a.files.filter!isStaticLibrary.array).
            join.
            map!(a => Target(a)).
            array;
    }

    // all postBuildCommands in one shell command. Empty if there are none
    string postBuildCommands() @safe pure nothrow const {
        import std.string: join;
        return packages[0].postBuildCommands.join(" && ");
    }
}


private auto packagePaths(in DubPackage dubPackage, in string[] paths) @trusted nothrow {
    return paths.map!(a => buildPath(dubPackage.path, a)).array;
}

//@trusted because of map.array
private string[] allOf(alias F)(in DubPackage pack, in DubPackage[] packages) @trusted nothrow {

    import std.range: chain, only;
    import std.array: array, front, empty;

    string[] result;

    foreach(dependency; chain(only(pack.name), pack.dependencies)) {
        auto depPack = packages.find!(a => a.name == dependency);
        if(!depPack.empty) {
            result ~= F(depPack.front).array;
        }
    }
    return result;
}
