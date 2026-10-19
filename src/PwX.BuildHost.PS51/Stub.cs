// PwX Build Engine - Windows PowerShell 5.1 baslatici (C# 5 uyumlu; .NET Framework csc.exe ile derlenir)
// Gomulu betigi benzersiz gecici klasore UTF-8 BOM'lu cikarir, sistemdeki powershell.exe ile calistirir,
// cikis kodunu aktarir ve gecici klasoru siler. Windows PowerShell 5.1 hedef makinede MEVCUT olmalidir.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace PwX.Stub
{
    internal static class Program
    {
        private const string PayloadResource = "PwX.payload.ps1";

        [DllImport("kernel32.dll")] private static extern uint GetConsoleOutputCP();
        [DllImport("kernel32.dll")] private static extern bool SetConsoleOutputCP(uint cp);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

        private static int Main(string[] args)
        {
            string workDir = null;
            uint oldCp = 0;
            try
            {
                string psExe = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
                if (!File.Exists(psExe))
                {
                    Fatal("Windows PowerShell 5.1 (powershell.exe) bulunamadi: " + psExe);
                    return 1;
                }

                workDir = Path.Combine(Path.GetTempPath(), "pwx-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(workDir);
                string scriptPath = Path.Combine(workDir, "payload.ps1");

                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream s = asm.GetManifestResourceStream(PayloadResource))
                {
                    if (s == null) { Fatal("Gomulu betik bulunamadi."); return 1; }
                    using (FileStream fs = new FileStream(scriptPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    {
                        s.CopyTo(fs);
                    }
                }

                StringBuilder sb = new StringBuilder();
                sb.Append("-NoProfile -ExecutionPolicy Bypass -STA ");
#if PWX_GUI
                sb.Append("-WindowStyle Hidden ");
#endif
                sb.Append("-File ").Append(Quote(scriptPath));
                foreach (string a in args) sb.Append(' ').Append(Quote(a));

                ProcessStartInfo psi = new ProcessStartInfo(psExe, sb.ToString());
                psi.UseShellExecute = false;
#if PWX_GUI
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
#else
#if PWX_NO_OUTPUT
                psi.RedirectStandardOutput = true;
#endif
#if PWX_UTF8_OUTPUT
                // Turkce karakterler icin konsol cikis kod sayfasini gecici olarak UTF-8 yap
                try { oldCp = GetConsoleOutputCP(); if (oldCp != 0) SetConsoleOutputCP(65001); } catch { }
#endif
#endif
                using (Process p = Process.Start(psi))
                {
#if PWX_NO_OUTPUT
                    if (psi.RedirectStandardOutput) p.StandardOutput.ReadToEnd();
#endif
                    p.WaitForExit();
                    return p.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Fatal("PwX baslatici hatasi: " + ex.Message);
                return 1;
            }
            finally
            {
#if PWX_UTF8_OUTPUT
                try { if (oldCp != 0) SetConsoleOutputCP(oldCp); } catch { }
#endif
                try { if (workDir != null && Directory.Exists(workDir)) Directory.Delete(workDir, true); } catch { }
            }
        }

        // CommandLineToArgvW kurallarina uygun guvenli tirnaklama (kullanici girdisi shell komutuna eklenmez)
        private static string Quote(string arg)
        {
            if (arg.Length > 0 && arg.IndexOfAny(new char[] { ' ', '\t', '\n', '\v', '"' }) < 0) return arg;
            StringBuilder sb = new StringBuilder("\"");
            int backslashes = 0;
            foreach (char c in arg)
            {
                if (c == '\\') { backslashes++; }
                else if (c == '"')
                {
                    sb.Append('\\', backslashes * 2 + 1);
                    sb.Append('"');
                    backslashes = 0;
                }
                else
                {
                    sb.Append('\\', backslashes);
                    backslashes = 0;
                    sb.Append(c);
                }
            }
            sb.Append('\\', backslashes * 2);
            sb.Append('"');
            return sb.ToString();
        }

        private static void Fatal(string message)
        {
#if PWX_GUI
            try { MessageBoxW(IntPtr.Zero, message, "PwX", 0x10); } catch { }
#else
            Console.Error.WriteLine(message);
#endif
        }
    }
}
