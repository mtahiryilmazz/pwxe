using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace PwX.Hybrid.Prototype
{
    /// <summary>
    /// netstandard2.0 hedefli Süreç İçi Hibrit (In-Process Hybrid) Prototip Yürütücüsü.
    /// Ana derleme motorunu ve resmi pwxe sürümlerini etkilemeden izole AppDomain / ALC
    /// sınırında PowerShell Standard / SMA yükleme kabiliyetini araştırır.
    /// </summary>
    public sealed class HybridScriptRunner
    {
        public static HybridRunResult Execute(string script, string[] args)
        {
            var result = new HybridRunResult();
            try
            {
                InitialSessionState iss = InitialSessionState.CreateDefault();
                using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
                {
                    rs.Open();
                    using (PowerShell ps = PowerShell.Create())
                    {
                        ps.Runspace = rs;
                        ps.AddScript(script);

                        if (args != null && args.Length > 0)
                        {
                            foreach (var arg in args)
                            {
                                ps.AddArgument(arg);
                            }
                        }

                        Collection<PSObject> output = ps.Invoke();
                        result.Success = !ps.HadErrors;
                        result.Output = output;

                        if (ps.HadErrors && ps.Streams.Error.Count > 0)
                        {
                            result.ErrorMessage = ps.Streams.Error[0].ToString();
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.ErrorMessage = ex.Message;
            }

            return result;
        }
    }

    public sealed class HybridRunResult
    {
        public bool Success { get; set; }
        public string ErrorMessage { get; set; }
        public Collection<PSObject> Output { get; set; }
    }
}
