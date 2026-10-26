// PwX Build Engine - PowerShell 7 host
// Gomulu payload.ps1 dosyasini benzersiz gecici klasore cikarir, PowerShell SDK ile calistirir,
// betigin cikis kodunu dondurur ve gecici klasoru temizler.
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace PwX.BuildHost
{
    internal static class Program
    {
#if PWX_ENCRYPTED_PAYLOAD
        private const string PayloadResource = "PwX.payload.enc";
#else
        private const string PayloadResource = "PwX.payload.ps1";
#endif

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

        [STAThread]
        private static int Main(string[] args)
        {
            string workDir = null;
            try
            {
                ConfigureModulePath();
                workDir = Path.Combine(Path.GetTempPath(), "pwx-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(workDir);
                string scriptPath = Path.Combine(workDir, "payload.ps1");
                ExtractPayload(scriptPath);

#if PWX_GUI
                return RunHidden(scriptPath, args);
#else
                return RunConsole(scriptPath, args);
#endif
            }
            catch (Exception ex)
            {
                ReportFatal("PwX host hatasi: " + ex.Message);
                return 1;
            }
            finally
            {
                try { if (workDir != null && Directory.Exists(workDir)) Directory.Delete(workDir, true); }
                catch { /* temizlik en iyi gayret esasli */ }
            }
        }

        private static void ExtractPayload(string target)
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream s = asm.GetManifestResourceStream(PayloadResource))
            {
                if (s == null) throw new InvalidOperationException("Gomulu betik bulunamadi: " + PayloadResource);

#if PWX_ENCRYPTED_PAYLOAD
                byte[] raw;
                using (MemoryStream ms = new MemoryStream())
                {
                    s.CopyTo(ms);
                    raw = ms.ToArray();
                }
                byte[] decrypted = DecryptPayload(raw);
                File.WriteAllBytes(target, decrypted);
#else
                using (FileStream fs = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    s.CopyTo(fs); // payload build sirasinda UTF-8 BOM ile yazilmistir
#endif
            }
        }

#if PWX_ENCRYPTED_PAYLOAD
        private static byte[] DecryptPayload(byte[] pkg)
        {
            if (pkg == null || pkg.Length < 8 + 1 + 16 + 2 + 32 + 4)
                throw new CryptographicException("Gecersiz sifreli paket boyutu.");

            // 1. Magic check: "PWXENC01"
            byte[] magic = Encoding.ASCII.GetBytes("PWXENC01");
            for (int i = 0; i < magic.Length; i++)
            {
                if (pkg[i] != magic[i]) throw new CryptographicException("Gecersiz sifreli paket basligi (magic header mismatch).");
            }

            int offset = 8;
            byte flag = pkg[offset++]; // 0 = standard, 1 = DPAPI bound
            byte[] iv = new byte[16];
            Buffer.BlockCopy(pkg, offset, iv, 0, 16);
            offset += 16;

            ushort keyLen = BitConverter.ToUInt16(pkg, offset);
            offset += 2;
            if (offset + keyLen + 32 + 4 > pkg.Length)
                throw new CryptographicException("Bozuk paket: key uzunlugu siniri asti.");

            byte[] keyBlob = new byte[keyLen];
            Buffer.BlockCopy(pkg, offset, keyBlob, 0, keyLen);
            offset += keyLen;

            byte[] tag = new byte[32];
            Buffer.BlockCopy(pkg, offset, tag, 0, 32);
            offset += 32;

            int cipherLen = BitConverter.ToInt32(pkg, offset);
            offset += 4;
            if (cipherLen < 0 || offset + cipherLen != pkg.Length)
                throw new CryptographicException("Bozuk paket: cipher uzunlugu uyusmuyor.");

            byte[] cipherBytes = new byte[cipherLen];
            Buffer.BlockCopy(pkg, offset, cipherBytes, 0, cipherLen);

            // 2. Unprotect Key if machine-bound
            byte[] rawKey;
            if (flag == 1)
            {
                byte[] entropy = Encoding.UTF8.GetBytes("PwX-Machine-Binding-Entropy-v1.8.0");
                try
                {
                    rawKey = ProtectedData.Unprotect(keyBlob, entropy, DataProtectionScope.CurrentUser);
                }
                catch (Exception ex)
                {
                    throw new CryptographicException("Bu calistirilabilir dosya farkli bir makineye veya kullaniciya kilitlenmistir (DPAPI kilidi acilamadi): " + ex.Message);
                }
            }
            else
            {
                rawKey = keyBlob;
            }

            // 3. Verify HMAC-SHA256 (Constant-time comparison)
            using (HMACSHA256 hmac = new HMACSHA256(rawKey))
            {
                using (MemoryStream msHmac = new MemoryStream())
                {
                    msHmac.WriteByte(flag);
                    msHmac.Write(iv, 0, iv.Length);
                    msHmac.Write(keyBlob, 0, keyBlob.Length);
                    msHmac.Write(cipherBytes, 0, cipherBytes.Length);
                    byte[] computedTag = hmac.ComputeHash(msHmac.ToArray());

                    if (!CryptographicOperations.FixedTimeEquals(computedTag, tag))
                    {
                        throw new CryptographicException("Sifreli betik veri butunlugu dogrulanamadi (HMAC-SHA256 imzasi gecersiz; dosya degistirilmis olabilir).");
                    }
                }
            }

            // 4. AES-256-CBC Decrypt
            using (Aes aes = Aes.Create())
            {
                aes.KeySize = 256;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;
                aes.Key = rawKey;
                aes.IV = iv;
                using (ICryptoTransform decryptor = aes.CreateDecryptor())
                {
                    return decryptor.TransformFinalBlock(cipherBytes, 0, cipherBytes.Length);
                }
            }
        }
#endif

        private static void ConfigureModulePath()
        {
            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                List<string> candidatePaths = new List<string>();

                string mod1 = Path.Combine(baseDir, "Modules");
                if (Directory.Exists(mod1)) candidatePaths.Add(mod1);

                string mod2 = Path.Combine(baseDir, "runtimes", "win", "lib", "net8.0", "Modules");
                if (Directory.Exists(mod2)) candidatePaths.Add(mod2);

                string current = Environment.GetEnvironmentVariable("PSModulePath");
                if (!string.IsNullOrEmpty(current))
                {
                    foreach (string part in current.Split(Path.PathSeparator))
                    {
                        if (string.IsNullOrWhiteSpace(part)) continue;
                        // Windows PowerShell 5.1 (Desktop) modulleri PS7 Core ile uyumsuzdur
                        if (part.IndexOf("WindowsPowerShell", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                        if (!candidatePaths.Exists(p => string.Equals(p, part, StringComparison.OrdinalIgnoreCase)))
                        {
                            candidatePaths.Add(part);
                        }
                    }
                }

                if (candidatePaths.Count > 0)
                {
                    Environment.SetEnvironmentVariable("PSModulePath", string.Join(Path.PathSeparator.ToString(), candidatePaths));
                }
            }
            catch { /* en iyi gayret */ }
        }

#if !PWX_GUI
        // Konsol modu: pwsh -File davranisi (parametreler, stdout/stderr, cikis kodu)
        private static int RunConsole(string scriptPath, string[] userArgs)
        {
#if PWX_UTF8_OUTPUT
            try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }
#endif
#if PWX_NO_OUTPUT
            try { Console.SetOut(TextWriter.Null); } catch { }
#endif

            string[] psArgs = new string[userArgs.Length + 6];
            psArgs[0] = "-NoLogo";
            psArgs[1] = "-NoProfile";
            psArgs[2] = "-ExecutionPolicy";
            psArgs[3] = "Bypass";
            psArgs[4] = "-File";
            psArgs[5] = scriptPath;
            Array.Copy(userArgs, 0, psArgs, 6, userArgs.Length);
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            return Microsoft.PowerShell.ConsoleShell.Start(iss, string.Empty, string.Empty, psArgs);
        }
#endif

#if PWX_GUI
        // GUI modu: konsol penceresi yok; STA runspace icinde calistirir.
        // PowerShell 'exit N' komutunu PSHost.SetShouldExit uzerinden bildirir.
        private static int RunHidden(string scriptPath, string[] args)
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            var host = new ExitCodeHost();

            using (Runspace rs = RunspaceFactory.CreateRunspace(host, iss))
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();

                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    // Payload metni pipeline'in ust duzey betigi olarak calisir (AddScript).
                    // PowerShell kaynak kodunda (LocalPipeline.InvokeHelper) ust duzey 'exit N',
                    // PSHost.SetShouldExit(N) cagrisina cevrilir. Betik DOSYASI olarak calistirilsaydi
                    // (AddCommand(path)) 'exit' yalnizca $LASTEXITCODE'u ayarlar ve host'a bildirilmezdi.
                    string scriptText = File.ReadAllText(scriptPath);
                    ps.AddScript(scriptText);
                    ScriptArguments.Apply(ps, scriptText, args);

                    try { ps.Invoke(); }
                    catch (RuntimeException ex)
                    {
                        ReportFatal(ex.Message);
                        return 1;
                    }

                    // Acik 'exit N' her zaman onceliklidir; betik daha once Write-Error ile
                    // sonlandirici olmayan hata yazmis olsa bile N dondurulur.
                    if (host.ShouldExit)
                        return host.ExitCode;

                    if (ps.HadErrors && ps.Streams.Error.Count > 0)
                    {
                        ReportFatal(ps.Streams.Error[0].ToString());
                        return 1;
                    }

                    // Normal bitis: pwsh -File ile ayni sekilde 0 (son yerel komutun
                    // $LASTEXITCODE degeri islem cikis koduna sizdirilmaz).
                    return 0;
                }
            }
        }

        private sealed class ExitCodeHost : PSHost
        {
            private readonly HeadlessHostUI _ui = new HeadlessHostUI();
            private readonly Guid _instanceId = Guid.NewGuid();

            internal bool ShouldExit { get; private set; }
            internal int ExitCode { get; private set; }

            public override string Name { get { return "PwX GUI Host"; } }
            public override Version Version { get { return typeof(PowerShell).Assembly.GetName().Version; } }
            public override Guid InstanceId { get { return _instanceId; } }
            public override PSHostUserInterface UI { get { return _ui; } }
            public override CultureInfo CurrentCulture { get { return Thread.CurrentThread.CurrentCulture; } }
            public override CultureInfo CurrentUICulture { get { return Thread.CurrentThread.CurrentUICulture; } }

            public override void SetShouldExit(int exitCode)
            {
                ExitCode = exitCode;
                ShouldExit = true;
            }

            public override void EnterNestedPrompt()
            {
                throw new NotSupportedException("GUI modunda ic ice konsol istemi desteklenmez.");
            }

            public override void ExitNestedPrompt() { }
            public override void NotifyBeginApplication() { }
            public override void NotifyEndApplication() { }
        }

        // Konsol bulunmadigi icin metinsel host ciktilari gizlidir; Write-Host hataya dusmez.
        // Read-Host/credential istemleri GUI host tarafindan desteklenmez.
        private sealed class HeadlessHostUI : PSHostUserInterface
        {
            public override PSHostRawUserInterface RawUI { get { return null; } }
            public override string ReadLine() { throw new NotSupportedException("GUI modunda Read-Host desteklenmez."); }
            public override SecureString ReadLineAsSecureString() { throw new NotSupportedException("GUI modunda parola istemi desteklenmez."); }
            public override void Write(string value) { }
            public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value) { }
            public override void WriteLine(string value) { }
            public override void WriteErrorLine(string value) { }
            public override void WriteDebugLine(string message) { }
            public override void WriteProgress(long sourceId, ProgressRecord record) { }
            public override void WriteVerboseLine(string message) { }
            public override void WriteWarningLine(string message) { }

            public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
            {
                throw new NotSupportedException("Interactive prompts are not supported in GUI mode.");
            }

            public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
            {
                throw new NotSupportedException("Credential prompts are not supported in GUI mode.");
            }

            public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
            {
                throw new NotSupportedException("GUI modunda kimlik bilgisi istemi desteklenmez.");
            }

            public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
            {
                throw new NotSupportedException("GUI modunda secim istemi desteklenmez.");
            }
        }
#endif

        // PWX_ERROR_LOG yalnizca test/otomasyon ortaminda (PWX_TESTHOOKS veya DEBUG acikken) etkindir.
        // Uretim derlemelerinde keyfi dosya ekleme (arbitrary file append) riskini onlemek icin derleme disi birakilir.
        private static void ReportFatal(string message)
        {
#if DEBUG || PWX_TESTHOOKS
            string log = Environment.GetEnvironmentVariable("PWX_ERROR_LOG");
            if (!string.IsNullOrEmpty(log))
            {
                try { File.AppendAllText(log, message + Environment.NewLine, new UTF8Encoding(false)); } catch { }
                return;
            }
#endif
#if PWX_GUI
            try { MessageBoxW(IntPtr.Zero, message, "PwX", 0x10); } catch { }
#else
            Console.Error.WriteLine(message);
#endif
        }
    }
}
