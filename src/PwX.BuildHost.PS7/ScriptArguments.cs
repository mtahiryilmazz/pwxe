// PwX Build Engine - GUI host arguman baglayici
// "pwsh -File" davranisini taklit eder: "-Ad deger", "-Ad:deger", [switch] parametreleri,
// parametre adi onekleri (ornek: -Mess abc) ve konumsal degerler.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Language;

namespace PwX.BuildHost
{
    internal static class ScriptArguments
    {
        internal static void Apply(PowerShell ps, string scriptText, string[] args)
        {
            Dictionary<string, bool> declared = GetDeclaredParameters(scriptText); // ad -> [switch] mi

            for (int i = 0; i < args.Length; i++)
            {
                string token = args[i];
                if (!IsParameterToken(token)) { ps.AddArgument(token); continue; }

                string name = token.Substring(1);
                string inlineValue = null;
                int colon = name.IndexOf(':');
                if (colon > 0)
                {
                    inlineValue = name.Substring(colon + 1);
                    name = name.Substring(0, colon);
                }

                bool isSwitch = IsSwitch(declared, name);

                if (isSwitch)
                {
                    // [switch] sonraki degeri tuketmez; yalnizca -Ad:$false / -Ad:true bicimi deger alir.
                    if (inlineValue == null) ps.AddParameter(name);
                    else ps.AddParameter(name, ParseBool(inlineValue));
                }
                else if (inlineValue != null)
                {
                    ps.AddParameter(name, inlineValue);
                }
                else if (i + 1 < args.Length && !IsParameterToken(args[i + 1]))
                {
                    ps.AddParameter(name, args[++i]);
                }
                else
                {
                    ps.AddParameter(name);
                }
            }
        }

        internal static bool IsParameterToken(string s)
        {
            return s != null && s.Length > 1 && s[0] == '-' && (char.IsLetter(s[1]) || s[1] == '_');
        }

        private static bool IsSwitch(Dictionary<string, bool> declared, string name)
        {
            bool sw;
            if (declared.TryGetValue(name, out sw)) return sw;

            // Benzersiz onek eslesmesi (PowerShell parametre kisaltmasi)
            var matches = declared.Where(kv => kv.Key.StartsWith(name, StringComparison.OrdinalIgnoreCase)).ToList();
            return matches.Count == 1 && matches[0].Value;
        }

        private static bool ParseBool(string text)
        {
            string t = text.Trim().TrimStart('$');
            if (t.Equals("true", StringComparison.OrdinalIgnoreCase) || t == "1") return true;
            if (t.Equals("false", StringComparison.OrdinalIgnoreCase) || t == "0") return false;
            throw new ArgumentException("Gecersiz [switch] degeri: " + text);
        }

        // Betigin param() blogundaki parametreleri okur (betik CALISTIRILMAZ, yalnizca ayristirilir).
        private static Dictionary<string, bool> GetDeclaredParameters(string scriptText)
        {
            var map = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            Token[] tokens;
            ParseError[] errors;
            ScriptBlockAst ast = Parser.ParseInput(scriptText, out tokens, out errors);
            if (ast == null || ast.ParamBlock == null) return map;

            foreach (ParameterAst p in ast.ParamBlock.Parameters)
            {
                bool isSwitch = p.Attributes.OfType<TypeConstraintAst>().Any(tc =>
                {
                    string n = tc.TypeName.Name;
                    return n.Equals("switch", StringComparison.OrdinalIgnoreCase)
                        || n.EndsWith("SwitchParameter", StringComparison.OrdinalIgnoreCase);
                });
                map[p.Name.VariablePath.UserPath] = isSwitch;
            }
            return map;
        }
    }
}
