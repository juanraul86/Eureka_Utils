// Lanzador del Eureka_Utils.
//  - Compilado sin SINGLEFILE  -> Eureka_Utils.exe: se coloca junto a Eureka_Utils.ps1.
//  - Compilado con SINGLEFILE  -> Eureka_Utils_Portable.exe: lleva todo Eureka_Utils dentro
//    (recurso payload.zip), lo extrae en una carpeta protegida de ProgramData solo accesible por
//    administradores y SYSTEM, lo ejecuta y la borra al terminar. Registros y exportaciones se
//    guardan junto al .exe, en la carpeta Eureka_Utils_Datos.
// El manifiesto pide elevación (requireAdministrator).
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;
#if SINGLEFILE
using System.IO.Compression;
#endif

[assembly: AssemblyTitle("Eureka_Utils")]
[assembly: AssemblyDescription("Utilidad portable para equipos Windows: software, bloatware, actualizaciones, hardware, cuentas, dominio, Intune y USB de instalación")]
[assembly: AssemblyProduct("Eureka_Utils")]
[assembly: AssemblyCopyright("Uso interno")]
[assembly: AssemblyVersion("2.2.0.0")]
[assembly: AssemblyFileVersion("2.2.0.0")]

static class Program
{
    const string Title = "Eureka_Utils";

    [STAThread]
    static int Main(string[] args)
    {
        string runDir = null;
        try
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string root = exeDir;
#if SINGLEFILE
            runDir = Extract();
            root = runDir;
            Environment.SetEnvironmentVariable("CFG_DATA", Path.Combine(exeDir, "Eureka_Utils_Datos"));
#endif
            string script = Path.Combine(root, "Eureka_Utils.ps1");
            if (!File.Exists(script))
            {
                MessageBox.Show("No se encuentra Eureka_Utils.ps1 junto al ejecutable.\n\nCopia la carpeta completa de Eureka_Utils (Modules, UI, Catalog...) o usa Eureka_Utils_Portable.exe.",
                    Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 2;
            }
#if !SINGLEFILE
            // Seguridad: el .exe lleva la huella SHA-256 de cada archivo de código. Si alguno se ha
            // modificado o se ha añadido un script, no se ejecuta nada (estaría corriendo como administrador).
            string problem = Integrity.Verify(root);
            if (problem != null)
            {
                MessageBox.Show("Por seguridad no se ha iniciado Eureka_Utils: los archivos de código no coinciden con los que se publicaron junto a este ejecutable.\n\n" + problem +
                    "\n\nVuelve a descargar Eureka_Utils completo desde su página oficial. Si has modificado el código a propósito, usa Eureka_Utils.cmd o genera de nuevo el .exe con Build\\Build-Exe.ps1.",
                    Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 3;
            }
#endif

            StringBuilder sb = new StringBuilder("-NoProfile -ExecutionPolicy Bypass -STA -File " + Quote(script));
            foreach (string a in args) sb.Append(' ').Append(Quote(a));

            bool console = IsConsoleMode(args);
            string ps = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            ProcessStartInfo psi = new ProcessStartInfo(ps, sb.ToString());
            psi.UseShellExecute = false;
            psi.WorkingDirectory = Environment.SystemDirectory;   // nunca la carpeta de la herramienta (podría contener ejecutables homónimos)
            psi.CreateNoWindow = !console;
            if (!console) psi.WindowStyle = ProcessWindowStyle.Hidden;

            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("No se pudo iniciar Eureka_Utils:\n\n" + ex.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            if (runDir != null) { try { Directory.Delete(runDir, true); } catch { } }
        }
    }

    // Modo consola: acciones desatendidas o listado. Si solo hay -Perfil/-Pestana, se abre la interfaz.
    static bool IsConsoleMode(string[] args)
    {
        foreach (string a in args)
        {
            string x = a.TrimStart('-', '/').ToLowerInvariant();
            if (x == "desatendido" || x == "instalar" || x == "quitarbloatware" || x == "ajustes" || x == "actualizartodo" ||
                x == "sincronizarintune" || x == "listarcatalogo") return true;
        }
        return false;
    }

    static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return a;
        return "\"" + a.Replace("\\\"", "\\\\\"").Replace("\"", "\\\"") + "\"";
    }

#if SINGLEFILE
    static string Extract()
    {
        string baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Eureka_Utils");
        Directory.CreateDirectory(baseDir);
        // Limpia ejecuciones anteriores que no se pudieron borrar
        foreach (string old in Directory.GetDirectories(baseDir, "run-*"))
        {
            try { if (Directory.GetCreationTimeUtc(old) < DateTime.UtcNow.AddHours(-12)) Directory.Delete(old, true); } catch { }
        }
        // Carpeta nueva con nombre impredecible y permisos explícitos solo para Administradores y SYSTEM
        string dir = Path.Combine(baseDir, "run-" + Guid.NewGuid().ToString("N"));
        DirectorySecurity sec = new DirectorySecurity();
        sec.SetAccessRuleProtection(true, false);
        InheritanceFlags inh = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
        sec.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null), FileSystemRights.FullControl, inh, PropagationFlags.None, AccessControlType.Allow));
        sec.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, inh, PropagationFlags.None, AccessControlType.Allow));
#if TESTACL
        // Solo para pruebas sin elevación (nunca en los ejecutables distribuidos)
        sec.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User, FileSystemRights.FullControl, inh, PropagationFlags.None, AccessControlType.Allow));
#endif
        Directory.CreateDirectory(dir, sec);

        Assembly asm = Assembly.GetExecutingAssembly();
        using (Stream s = asm.GetManifestResourceStream("payload.zip"))
        {
            if (s == null) throw new InvalidOperationException("El ejecutable no contiene Eureka_Utils (payload.zip).");
            using (ZipArchive zip = new ZipArchive(s, ZipArchiveMode.Read))
            {
                string full = Path.GetFullPath(dir) + Path.DirectorySeparatorChar;
                foreach (ZipArchiveEntry e in zip.Entries)
                {
                    string target = Path.GetFullPath(Path.Combine(dir, e.FullName.Replace('/', Path.DirectorySeparatorChar)));
                    if (!target.StartsWith(full, StringComparison.OrdinalIgnoreCase)) continue; // evita rutas fuera de la carpeta
                    if (e.FullName.EndsWith("/")) { Directory.CreateDirectory(target); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    e.ExtractToFile(target, true);
                }
            }
        }
        return dir;
    }
#endif
}

#if !SINGLEFILE
// Verificación de integridad: compara los scripts con la lista de huellas incrustada al compilar
// (recurso "manifest.txt", líneas "<sha256> <ruta relativa>").
public static class Integrity
{
    static readonly string[] Patterns = { "*.ps1", "*.psm1", "*.xaml" };
    static readonly string[] SkipDirs = { "Build", "Dist", "Logs", "Exports", "Docs", ".git", ".github", "Eureka_Utils_Datos" };

    public static string Verify(string root)
    {
        System.Collections.Generic.Dictionary<string, string> expected = Load();
        if (expected == null) return null;   // compilación sin lista (desarrollo)
        StringBuilder problems = new StringBuilder();
        int n = 0;
        foreach (System.Collections.Generic.KeyValuePair<string, string> kv in expected)
        {
            string file = Path.Combine(root, kv.Key.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(file)) { Add(problems, ref n, "Falta: " + kv.Key); continue; }
            if (!string.Equals(Hash(file), kv.Value, StringComparison.OrdinalIgnoreCase)) Add(problems, ref n, "Modificado: " + kv.Key);
        }
        string full = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        foreach (string pattern in Patterns)
        {
            foreach (string f in Directory.GetFiles(full, pattern, SearchOption.AllDirectories))
            {
                string rel = f.Substring(full.Length).Replace(Path.DirectorySeparatorChar, '/');
                string top = rel.Contains("/") ? rel.Substring(0, rel.IndexOf('/')) : "";
                if (Array.IndexOf(SkipDirs, top) >= 0) continue;
                if (!expected.ContainsKey(rel)) Add(problems, ref n, "Añadido: " + rel);
            }
        }
        return n == 0 ? null : problems.ToString();
    }

    static void Add(StringBuilder sb, ref int n, string line)
    {
        n++;
        if (n <= 8) sb.AppendLine("• " + line);
        else if (n == 9) sb.AppendLine("• ...");
    }

    static System.Collections.Generic.Dictionary<string, string> Load()
    {
        Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("manifest.txt");
        if (s == null) return null;
        System.Collections.Generic.Dictionary<string, string> d = new System.Collections.Generic.Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        using (StreamReader r = new StreamReader(s, Encoding.UTF8))
        {
            string line;
            while ((line = r.ReadLine()) != null)
            {
                int sp = line.IndexOf(' ');
                if (sp == 64) d[line.Substring(65).Trim()] = line.Substring(0, 64);
            }
        }
        return d;
    }

    public static string Hash(string file)
    {
        using (System.Security.Cryptography.SHA256 sha = System.Security.Cryptography.SHA256.Create())
        using (FileStream fs = File.OpenRead(file))
            return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "");
    }
}
#endif
