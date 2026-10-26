// PwX Build Engine - In-Process Hybrid Research Prototype (Experimental)
// Ar-Ge Kapsamı: PowerShell 7 SMA'sının izole çalışma ortamında yüklenmesi ve
// bellek içi güvenli şifre çözme için AES-256-GCM + HKDF prototipi.

using System.Security.Cryptography;
using System.Text;

namespace Pwxe.Core.Security;

public sealed class PayloadProtector
{
    private const int NonceSize = 12;
    private const int TagSize = 16;
    private const int KeySize = 32;

    /// <summary>Script'i AES-256-GCM ile şifreler. Anahtar çağırandan gelir.</summary>
    public EncryptedPayload Encrypt(string script, byte[] key, byte[] salt)
    {
        var plaintext = Encoding.UTF8.GetBytes(script);
        var nonce = RandomNumberGenerator.GetBytes(NonceSize);
        var cipher = new byte[plaintext.Length];
        var tag = new byte[TagSize];

        using var aes = new AesGcm(key, TagSize);
        aes.Encrypt(nonce, plaintext, cipher, tag, salt);

        CryptographicOperations.ZeroMemory(plaintext);
        return new EncryptedPayload(nonce, cipher, tag, salt);
    }

    /// <summary>Şifreli payload'ı çözer; dönen buffer çağıran tarafından sıfırlanmalı.</summary>
    public byte[] Decrypt(EncryptedPayload payload, byte[] key)
    {
        var plaintext = new byte[payload.Cipher.Length];
        using var aes = new AesGcm(key, TagSize);
        aes.Decrypt(payload.Nonce, payload.Cipher, payload.Tag, plaintext, payload.Salt);
        return plaintext;
    }

    /// <summary>Makineye bağlı anahtar türetme. masterKey DPAPI ile korunur.</summary>
    public byte[] DeriveKey(byte[] masterKey, string machineGuid, byte[] salt)
    {
        var info = Encoding.UTF8.GetBytes(machineGuid);
        return HKDF.DeriveKey(HashAlgorithmName.SHA256, masterKey, KeySize, salt, info);
    }
}

public sealed record EncryptedPayload(byte[] Nonce, byte[] Cipher, byte[] Tag, byte[] Salt);
