// claude_wrapper.cs - Native Windows Wrapper for Claude Code (VS Code & CLI)
// Part of Claude Code Proxy Toolkit for Windows
// Compiles with: C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:exe /optimize+ /out:claude_wrapper.exe claude_wrapper.cs

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

[assembly: AssemblyTitle("Claude Code Proxy Wrapper")]
[assembly: AssemblyDescription("https://github.com/seowizardandrey/claudefix")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("Andrey Sokolov")]
[assembly: AssemblyProduct("Claude Code Proxy")]
[assembly: AssemblyCopyright("Copyright © 2026 Andrey Sokolov (seowizard.andrey@gmail.com)")]
[assembly: AssemblyTrademark("https://github.com/seowizardandrey/claudefix")]
[assembly: AssemblyCulture("")]
[assembly: AssemblyVersion("2.1.0.0")]
[assembly: AssemblyFileVersion("2.1.0.0")]

namespace ClaudeProxyWrapper
{
    class Program
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateProcess(
            string lpApplicationName,
            string lpCommandLine,
            IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes,
            bool bInheritHandles,
            uint dwCreationFlags,
            IntPtr lpEnvironment,
            string lpCurrentDirectory,
            ref STARTUPINFO lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr GetCommandLine();

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct STARTUPINFO
        {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        const uint INFINITE = 0xFFFFFFFF;

        static int Main(string[] args)
        {
            // Ignore Ctrl+C in wrapper so child process can gracefully handle or exit
            Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e)
            {
                e.Cancel = true;
            };

            string currentExe = Process.GetCurrentProcess().MainModule.FileName;
            string dir = Path.GetDirectoryName(currentExe);
            string baseName = Path.GetFileNameWithoutExtension(currentExe);
            string realExe = Path.Combine(dir, baseName + ".real.exe");

            if (!File.Exists(realExe))
            {
                string altReal = Path.Combine(dir, baseName + ".real");
                if (File.Exists(altReal))
                {
                    realExe = altReal;
                }
                else
                {
                    Console.Error.WriteLine("[Claude Proxy Wrapper] Error: target binary not found: " + realExe);
                    return 127;
                }
            }

            // Read proxy settings from ~/.config/claude-proxy/proxy.env
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string envPath = Path.Combine(userProfile, Path.Combine(".config", Path.Combine("claude-proxy", "proxy.env")));
            string proxyPort = "19000";
            string noProxy = "localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,github.com,.github.com,gitlab.com,.gitlab.com,bitbucket.org,.bitbucket.org,npmjs.org,.npmjs.org,registry.npmjs.org,yarnpkg.com,.yarnpkg.com,pypi.org,.pypi.org,pythonhosted.org,.pythonhosted.org,files.pythonhosted.org,crates.io,.crates.io,pkg.go.dev,proxy.golang.org,rubygems.org,.rubygems.org,packagist.org,.packagist.org,docker.io,.docker.io,docker.com,.docker.com,ubuntu.com,.ubuntu.com,debian.org,.debian.org,*.ru,*.рф,*.su";

            if (File.Exists(envPath))
            {
                try
                {
                    string[] lines = File.ReadAllLines(envPath);
                    foreach (string line in lines)
                    {
                        string trimmed = line.Trim();
                        if (string.IsNullOrEmpty(trimmed) || trimmed.StartsWith("#") || !trimmed.Contains("="))
                            continue;
                        int eqIdx = trimmed.IndexOf('=');
                        string key = trimmed.Substring(0, eqIdx).Trim();
                        string val = trimmed.Substring(eqIdx + 1).Trim().Trim('\"', '\'');
                        if (key == "PROXY_PORT") proxyPort = val;
                        else if (key == "NO_PROXY") noProxy = val;
                    }
                }
                catch { }
            }

            string proxyUrl = "http://127.0.0.1:" + proxyPort;

            // Set environment variables for this process (inherited by child process)
            Environment.SetEnvironmentVariable("HTTP_PROXY", proxyUrl);
            Environment.SetEnvironmentVariable("HTTPS_PROXY", proxyUrl);
            Environment.SetEnvironmentVariable("ALL_PROXY", proxyUrl);
            Environment.SetEnvironmentVariable("http_proxy", proxyUrl);
            Environment.SetEnvironmentVariable("https_proxy", proxyUrl);
            Environment.SetEnvironmentVariable("all_proxy", proxyUrl);
            Environment.SetEnvironmentVariable("NO_PROXY", noProxy);
            Environment.SetEnvironmentVariable("no_proxy", noProxy);

            // Extract the original command line arguments after the executable name
            IntPtr pCmdLine = GetCommandLine();
            string rawCmdLine = Marshal.PtrToStringUni(pCmdLine);
            string argsOnly = "";

            if (!string.IsNullOrEmpty(rawCmdLine))
            {
                string trimmed = rawCmdLine.TrimStart();
                if (trimmed.StartsWith("\""))
                {
                    int secondQuote = trimmed.IndexOf('\"', 1);
                    if (secondQuote != -1)
                    {
                        argsOnly = trimmed.Substring(secondQuote + 1).TrimStart();
                    }
                }
                else
                {
                    int firstSpace = trimmed.IndexOfAny(new char[] { ' ', '\t' });
                    if (firstSpace != -1)
                    {
                        argsOnly = trimmed.Substring(firstSpace + 1).TrimStart();
                    }
                }
            }

            string childCmdLine = string.IsNullOrEmpty(argsOnly)
                ? ("\"" + realExe + "\"")
                : ("\"" + realExe + "\" " + argsOnly);

            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(si);
            PROCESS_INFORMATION pi = new PROCESS_INFORMATION();

            bool success = CreateProcess(
                realExe,
                childCmdLine,
                IntPtr.Zero,
                IntPtr.Zero,
                true,   // inherit handles (stdin, stdout, stderr console streams)
                0,
                IntPtr.Zero, // inherit process environment variables
                null,
                ref si,
                out pi);

            if (!success)
            {
                int err = Marshal.GetLastWin32Error();
                Console.Error.WriteLine("[Claude Proxy Wrapper] Failed to start real binary: " + realExe + " (error: " + err + ")");
                return 127;
            }

            WaitForSingleObject(pi.hProcess, INFINITE);

            uint exitCode = 0;
            GetExitCodeProcess(pi.hProcess, out exitCode);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);

            return (int)exitCode;
        }
    }
}
