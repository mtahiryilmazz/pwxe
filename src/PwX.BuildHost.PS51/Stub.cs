using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
#if PWX_ENCRYPTED_PAYLOAD
using System.Security.Cryptography;
#endif
using System.Text;

namespace PwX.Stub
{
    internal static class Program
    {
#if PWX_ENCRYPTED_PAYLOAD
        private const string PayloadResource = "PwX.payload.enc";
#else
        private const string PayloadResource = "PwX.payload.ps1";
#endif

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
                    if (s == null) { Fatal("Gomulu betik bulunamadi: " + PayloadResource); return 1; }

#if PWX_ENCRYPTED_PAYLOAD
                    byte[] raw;
                    using (MemoryStream ms = new MemoryStream())
                    {
                        s.CopyTo(ms);
                        raw = ms.ToArray();
                    }
                    byte[] decrypted = DecryptPayload(raw);
                    File.WriteAllBytes(scriptPath, decrypted);
#else
                    using (FileStream fs = new FileStream(scriptPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    {
                        s.CopyTo(fs);
                    }
#endif
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

            // 2. Unprotect Key if machine-bound (DPAPI)
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

                    if (!FixedTimeEquals(computedTag, tag))
                    {
                        throw new CryptographicException("Sifreli betik veri butunlugu dogrulanamadi (HMAC-SHA256 imzasi gecersiz; dosya degistirilmis olabilir).");
                    }
                }
            }

            // 4. AES-256-CBC Decrypt
            using (AesCryptoServiceProvider aes = new AesCryptoServiceProvider())
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

        private static bool FixedTimeEquals(byte[] a, byte[] b)
        {
            if (a == null || b == null || a.Length != b.Length) return false;
            int diff = 0;
            for (int i = 0; i < a.Length; i++)
            {
                diff |= (a[i] ^ b[i]);
            }
            return diff == 0;
        }
#endif
    }
}
