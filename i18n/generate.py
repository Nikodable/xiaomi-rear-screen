#!/usr/bin/env python3
"""Génère Strings.swift (Mac) et Strings.cs (Windows) depuis strings.py."""
import os
from strings import LANGS, S

HERE = os.path.dirname(os.path.abspath(__file__))
codes = [c for c, _ in LANGS]

def table(platform):
    pc = "Mac" if platform == "mac" else "PC"
    out = {}
    for key, v in S.items():
        base, _, suf = key.rpartition(".")
        if suf in ("win", "mac"):
            if suf != platform: continue
            key = base
        for c in codes:
            assert c in v, f"{key}: langue {c} manquante"
        out[key] = {c: v[c].replace("{pc}", pc) for c in codes}
    # une clé « .win » remplace la base : la base a pu être écrite avant → déjà écrasée par dict
    return out

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

def swift():
    t = table("mac")
    L = ["// GÉNÉRÉ par i18n/generate.py — ne pas modifier à la main.", "import Foundation", ""]
    L.append("enum Lang: String, CaseIterable {")
    L.append("    case " + ", ".join(codes))
    L.append("    var native: String {")
    L.append("        switch self {")
    for c, n in LANGS: L.append(f'        case .{c}: return "{n}"')
    L.append("        }\n    }\n}\n")
    L.append("enum I18N {")
    L.append("    static let table: [String: [String: String]] = [")
    for c in codes:
        L.append(f'        "{c}": [')
        for k, v in t.items(): L.append(f'            "{k}": "{esc(v[c])}",')
        L.append("        ],")
    L.append("    ]")
    L.append('''    static var current: Lang = {
        if let s = UserDefaults.standard.string(forKey: "lang"), let l = Lang(rawValue: s) { return l }
        let sys = String((Locale.preferredLanguages.first ?? "en").prefix(2))
        return Lang(rawValue: sys) ?? .en
    }()
    static func set(_ l: Lang) { current = l; UserDefaults.standard.set(l.rawValue, forKey: "lang") }
}

/// Texte traduit ; {0}, {1}… sont remplacés par les arguments.
func t(_ key: String, _ args: String...) -> String {
    var s = I18N.table[I18N.current.rawValue]?[key] ?? I18N.table["en"]?[key] ?? key
    for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\\(i)}", with: a) }
    return s
}''')
    open(os.path.join(HERE, "..", "macos", "swift", "Strings.swift"), "w").write("\n".join(L) + "\n")

def cs():
    t = table("win")
    L = ["// GÉNÉRÉ par i18n/generate.py — ne pas modifier à la main.",
         "using Microsoft.Win32;", "", "namespace EcranArriere;", "",
         "static class I18N", "{",
         "    public static readonly (string Code, string Native)[] Langs =",
         "    {"]
    for c, n in LANGS: L.append(f'        ("{c}", "{n}"),')
    L.append("    };\n")
    L.append("    static readonly Dictionary<string, Dictionary<string, string>> Table = new()")
    L.append("    {")
    for c in codes:
        L.append(f'        ["{c}"] = new()')
        L.append("        {")
        for k, v in t.items(): L.append(f'            ["{k}"] = "{esc(v[c])}",')
        L.append("        },")
    L.append("    };\n")
    L.append('''    const string RegPath = @"HKEY_CURRENT_USER\\Software\\EcranArriere";

    public static string Current { get; private set; } = Detect();

    static string Detect()
    {
        try
        {
            if (Registry.GetValue(RegPath, "Lang", null) is string s && Table.ContainsKey(s)) return s;
        }
        catch { }
        var sys = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        return Table.ContainsKey(sys) ? sys : "en";
    }

    public static void Set(string code)
    {
        Current = code;
        try { Registry.SetValue(RegPath, "Lang", code); } catch { }
    }

    public static string T(string key, params string[] args)
    {
        var s = Table[Current].TryGetValue(key, out var v) ? v : (Table["en"].TryGetValue(key, out var e) ? e : key);
        for (int i = 0; i < args.Length; i++) s = s.Replace("{" + i + "}", args[i]);
        return s;
    }
}''')
    open(os.path.join(HERE, "..", "windows", "Strings.cs"), "w").write("\n".join(L) + "\n")

swift(); cs()
print("OK :", len(table("mac")), "clés ×", len(codes), "langues")
