// setup.cs - Native Windows C# Installer for Claude Code Proxy & Auto-Patcher (GOST)
// Part of Claude Code Proxy Toolkit
// Compiles with: C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:exe /optimize+ /out:setup.exe setup.cs

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;
using System.Threading;

[assembly: AssemblyTitle("Claude Proxy Setup")]
[assembly: AssemblyDescription("https://github.com/seowizardandrey/claudefix")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("Andrey Sokolov")]
[assembly: AssemblyProduct("Claude Code Proxy")]
[assembly: AssemblyCopyright("Copyright © 2026 Andrey Sokolov (seowizard.andrey@gmail.com)")]
[assembly: AssemblyTrademark("https://github.com/seowizardandrey/claudefix")]
[assembly: AssemblyCulture("")]
[assembly: AssemblyVersion("2.1.0.0")]
[assembly: AssemblyFileVersion("2.1.0.0")]

namespace ClaudeProxySetup
{
    class Program
    {
        const string DEFAULT_BYPASS = "localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,*.local,github.com,*.github.com,raw.githubusercontent.com,objects.githubusercontent.com,gitlab.com,*.gitlab.com,bitbucket.org,*.bitbucket.org,npmjs.org,*.npmjs.org,registry.npmjs.org,yarnpkg.com,*.yarnpkg.com,pypi.org,*.pypi.org,pythonhosted.org,*.pythonhosted.org,files.pythonhosted.org,crates.io,*.crates.io,pkg.go.dev,proxy.golang.org,rubygems.org,*.rubygems.org,packagist.org,*.packagist.org,docker.io,*.docker.io,docker.com,*.docker.com,*.ru,*.xn--p1ai,*.su";

        static int Main(string[] args)
        {
            try
            {
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)12288 | (SecurityProtocolType)3072 | (SecurityProtocolType)768 | SecurityProtocolType.Tls;
                ServicePointManager.ServerCertificateValidationCallback = (sender, cert, chain, sslErrors) => true;
            }
            catch { }

            Console.OutputEncoding = Encoding.UTF8;
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("=========================================================");
            Console.WriteLine(" Claude Code Proxy & Auto-Patcher Installer (Windows)");
            Console.WriteLine(" High-performance GOST Proxy Bridge & User Isolation");
            Console.WriteLine("=========================================================");
            Console.ResetColor();

            string currentUser = Environment.UserName;
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string userConfigDir = Path.Combine(userProfile, ".config", "claude-proxy");
            string userBinDir = Path.Combine(userConfigDir, "bin");
            string existingEnv = Path.Combine(userConfigDir, "proxy.env");
            string existingSocks5 = "";
            int proxyPort = 0;
            if (File.Exists(existingEnv))
            {
                try
                {
                    foreach (string line in File.ReadAllLines(existingEnv))
                    {
                        if (line.StartsWith("PROXY_PORT="))
                        {
                            int p;
                            if (int.TryParse(line.Substring(11).Trim(), out p)) proxyPort = p;
                        }
                        else if (line.StartsWith("SOCKS5_URL="))
                        {
                            existingSocks5 = line.Substring(11).Trim().Trim('"');
                        }
                    }
                }
                catch { }
            }

            int calculatedPort = CalculateUserPort();
            if (proxyPort == 0) proxyPort = calculatedPort;
            string socks5Url = "";
            bool isUninstall = false;
            bool isStatus = false;
            bool isPatch = false;

            // Parse arguments
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i].Trim();
                if (a.Equals("--uninstall", StringComparison.OrdinalIgnoreCase) || a.Equals("-u", StringComparison.OrdinalIgnoreCase))
                {
                    isUninstall = true;
                }
                else if (a.Equals("--status", StringComparison.OrdinalIgnoreCase) || a.Equals("-s", StringComparison.OrdinalIgnoreCase))
                {
                    isStatus = true;
                }
                else if (a.Equals("--patch", StringComparison.OrdinalIgnoreCase) || a.Equals("-p", StringComparison.OrdinalIgnoreCase))
                {
                    isPatch = true;
                }
                else if (a.Equals("--port", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
                {
                    int p;
                    if (int.TryParse(args[++i], out p)) proxyPort = p;
                }
                else if (a.StartsWith("socks5://", StringComparison.OrdinalIgnoreCase) || a.StartsWith("socks5h://", StringComparison.OrdinalIgnoreCase))
                {
                    socks5Url = a;
                }
                else if (!a.StartsWith("-") && string.IsNullOrEmpty(socks5Url))
                {
                    socks5Url = a;
                    if (!socks5Url.Contains("://"))
                    {
                        socks5Url = "socks5://" + socks5Url;
                    }
                }
            }

            if (isStatus)
            {
                ShowStatus(currentUser, proxyPort);
                return 0;
            }

            if (isUninstall)
            {
                return PerformUninstall(currentUser, userProfile, proxyPort);
            }

            if (isPatch)
            {
                Console.ForegroundColor = ConsoleColor.Cyan;
                Console.WriteLine("=========================================================");
                Console.WriteLine(" Claude Code Auto-Patcher for " + currentUser);
                Console.WriteLine("=========================================================");
                Console.ResetColor();

                EnsureCliBinaryInstalled(userProfile, proxyPort, userBinDir);
                PatchUserClaude(userProfile, userBinDir);
                ConfigureVsCodeSettings(userProfile, proxyPort);
                ConfigureClaudeGui(userProfile, proxyPort);

                Console.WriteLine();
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[OK] All components re-patched and synchronized successfully!");
                Console.ResetColor();
                return 0;
            }

            // Interactive input if SOCKS5 URL is not provided
            if (string.IsNullOrEmpty(socks5Url))
            {
                Console.WriteLine();
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("Target Windows User: " + currentUser);
                Console.WriteLine("Assigned Local Port: 127.0.0.1:" + proxyPort);
                if (!string.IsNullOrEmpty(existingSocks5))
                {
                    Console.WriteLine("Current Proxy Config: " + MaskProxyUrl(existingSocks5));
                    Console.WriteLine();
                    Console.WriteLine("Enter upstream SOCKS5 proxy URL (or press ENTER to keep current & re-patch):");
                }
                else
                {
                    Console.WriteLine();
                    Console.WriteLine("Enter your upstream SOCKS5 proxy URL:");
                    Console.WriteLine("  Format: socks5://USER:PASSWORD@HOST:PORT");
                    Console.WriteLine("      or: socks5://HOST:PORT (without auth)");
                    Console.WriteLine("      or: USER:PASSWORD@HOST:PORT");
                }
                Console.ResetColor();
                Console.Write("\nSOCKS5 URL: ");
                string input = Console.ReadLine();
                if (!string.IsNullOrEmpty(input))
                {
                    socks5Url = input.Trim();
                    if (!socks5Url.Contains("://"))
                    {
                        socks5Url = "socks5://" + socks5Url;
                    }
                }
                else if (!string.IsNullOrEmpty(existingSocks5))
                {
                    socks5Url = existingSocks5;
                }
            }

            if (string.IsNullOrEmpty(socks5Url))
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("\nError: SOCKS5 proxy URL is required!");
                Console.ResetColor();
                Console.WriteLine("Usage: setup.exe \"socks5://USER:PASS@HOST:PORT\" [--port PORT]");
                Console.WriteLine("   or: setup.exe --patch");
                Console.WriteLine("   or: setup.exe --uninstall");
                return 1;
            }

            bool isAdmin = IsAdministrator();
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("Configuration Parameters:");
            Console.WriteLine("  Target User   : " + currentUser + " (ONLY this user is configured)");
            Console.WriteLine("  Profile Dir   : " + userProfile);
            Console.WriteLine("  SOCKS5 Proxy  : " + MaskProxyUrl(socks5Url));
            Console.WriteLine("  Local Bridge  : 127.0.0.1:" + proxyPort);
            Console.WriteLine("  Admin Rights  : " + (isAdmin ? "YES (System boot task)" : "NO (User logon task)"));
            Console.ResetColor();
            Console.WriteLine();

            // 1. Deploy shared GOST binary
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[1/5] Deploying GOST proxy engine...");
            Console.ResetColor();
            string gostExe = DeployGostBinary();
            if (string.IsNullOrEmpty(gostExe) || !File.Exists(gostExe))
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("Error: Unable to locate or deploy gost.exe!");
                Console.ResetColor();
                return 1;
            }
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("      [OK] GOST binary ready: " + gostExe);
            Console.ResetColor();

            // 2. Deploy user configuration
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[2/5] Creating user configuration in profile...");
            Console.ResetColor();
            userConfigDir = Path.Combine(userProfile, ".config", "claude-proxy");
            userBinDir = Path.Combine(userConfigDir, "bin");
            Directory.CreateDirectory(userConfigDir);
            Directory.CreateDirectory(userBinDir);

            string proxyEnvFile = Path.Combine(userConfigDir, "proxy.env");
            string envContent = string.Format(
                "# Claude Code Proxy Configuration\nPROXY_PORT={0}\nSOCKS5_URL=\"{1}\"\nPROXY_MODE=\"anthropic_only\"\nNO_PROXY=\"{2}\"\nTASK_AUTOSTART=true\n",
                proxyPort, socks5Url, DEFAULT_BYPASS);
            File.WriteAllText(proxyEnvFile, envContent, Encoding.UTF8);

            string bypassFile = Path.Combine(userConfigDir, "bypass.conf");
            if (!File.Exists(bypassFile))
            {
                File.WriteAllText(bypassFile, DEFAULT_BYPASS.Replace(",", "\n") + "\n", Encoding.UTF8);
            }
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("      [OK] Config saved: " + proxyEnvFile);
            Console.ResetColor();

            // 3. Deploy wrapper and helper command scripts
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[3/5] Deploying CLI helpers to " + userBinDir + "...");
            Console.ResetColor();
            DeployHelperScripts(userBinDir, proxyPort, socks5Url, gostExe);
            AddPathToUserEnvironment(userBinDir);

            // 4. Register Autostart & Start Proxy immediately
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[4/5] Configuring resilient autostart & starting proxy bridge...");
            Console.ResetColor();
            RegisterAndStartProxy(currentUser, proxyPort, socks5Url, gostExe, isAdmin);

            // 5. Patch Claude Code in THIS user's profile ONLY
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[5/5] Auto-patching all Claude components (CLI, VS Code, GUI) for " + currentUser + "...");
            Console.ResetColor();
            EnsureCliBinaryInstalled(userProfile, proxyPort, userBinDir);
            PatchUserClaude(userProfile, userBinDir);
            ConfigureVsCodeSettings(userProfile, proxyPort);
            ConfigureClaudeGui(userProfile, proxyPort);

            // Trust Code Signing Certificate if present
            if (isAdmin)
            {
                try
                {
                    string appDir = AppDomain.CurrentDomain.BaseDirectory;
                    string cerFile = Path.Combine(appDir, "ClaudeProxy.cer");
                    if (File.Exists(cerFile))
                    {
                        X509Certificate2 cert = new X509Certificate2(cerFile);
                        using (X509Store store = new X509Store(StoreName.Root, StoreLocation.LocalMachine))
                        {
                            store.Open(OpenFlags.ReadWrite);
                            store.Add(cert);
                        }
                        using (X509Store storePub = new X509Store(StoreName.TrustedPublisher, StoreLocation.LocalMachine))
                        {
                            storePub.Open(OpenFlags.ReadWrite);
                            storePub.Add(cert);
                        }
                        Console.ForegroundColor = ConsoleColor.Green;
                        Console.WriteLine("      [OK] Certificate 'Andrey Sokolov' trusted in Root & Trusted Publisher.");
                        Console.ResetColor();
                    }
                }
                catch { }
            }

            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("=========================================================");
            Console.WriteLine(" Installation completed successfully for " + currentUser + "!");
            Console.WriteLine("=========================================================");
            Console.ResetColor();
            Console.WriteLine(" Available commands (added to your User PATH):");
            Console.WriteLine("   claude         - Run Claude Code CLI (routes via 127.0.0.1:" + proxyPort + ")");
            Console.WriteLine("   status.cmd     - Check proxy status and port listening");
            Console.WriteLine("   start.cmd      - Start background proxy bridge");
            Console.WriteLine("   stop.cmd       - Stop background proxy bridge");
            Console.WriteLine("   patch.cmd      - Re-patch VS Code & CLI after any extension updates");
            Console.WriteLine("   gui.cmd        - Launch Claude Desktop GUI via proxy");
            Console.WriteLine("   install_cli.cmd- Install Claude Code CLI via active proxy bridge");
            Console.WriteLine("   uninstall.cmd  - Remove proxy bridge and restore original binaries");
            Console.WriteLine("=========================================================");
            return 0;
        }

        static int CalculateUserPort()
        {
            try
            {
                string sid = WindowsIdentity.GetCurrent().User.Value;
                string[] parts = sid.Split('-');
                int rid;
                if (parts.Length > 0 && int.TryParse(parts[parts.Length - 1], out rid))
                {
                    if (rid >= 1000)
                    {
                        return 19000 + (rid - 1001);
                    }
                }
            }
            catch { }
            return 19000;
        }

        static bool IsAdministrator()
        {
            try
            {
                var identity = WindowsIdentity.GetCurrent();
                var principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch { return false; }
        }

        static string MaskProxyUrl(string url)
        {
            try
            {
                Uri u = new Uri(url);
                if (!string.IsNullOrEmpty(u.UserInfo))
                {
                    return u.Scheme + "://***:***@" + u.Authority.Substring(u.Authority.IndexOf('@') + 1);
                }
            }
            catch { }
            return url;
        }

        static string DeployGostBinary()
        {
            string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            string targetDir = Path.Combine(programData, "claude-proxy", "bin");
            string targetGost = Path.Combine(targetDir, "gost.exe");

            try { Directory.CreateDirectory(targetDir); } catch { }

            if (File.Exists(targetGost))
            {
                return targetGost;
            }

            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string localGost = Path.Combine(appDir, "gost.exe");
            if (File.Exists(localGost))
            {
                try
                {
                    File.Copy(localGost, targetGost, true);
                    return targetGost;
                }
                catch
                {
                    return localGost;
                }
            }

            if (File.Exists(@"C:\gost\gost.exe"))
            {
                try
                {
                    File.Copy(@"C:\gost\gost.exe", targetGost, true);
                    return targetGost;
                }
                catch { return @"C:\gost\gost.exe"; }
            }

            return null;
        }

        static void DeployHelperScripts(string userBinDir, int port, string socks5, string gostExe)
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string localWrapper = Path.Combine(appDir, "claude_wrapper.exe");
            string targetWrapper = Path.Combine(userBinDir, "claude_wrapper.exe");
            if (!File.Exists(targetWrapper))
            {
                if (File.Exists(localWrapper))
                {
                    try { File.Copy(localWrapper, targetWrapper, true); } catch { }
                }
                else
                {
                    string localCs = Path.Combine(appDir, "claude_wrapper.cs");
                    if (File.Exists(localCs))
                    {
                        string csc = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"Microsoft.NET\Framework64\v4.0.30319\csc.exe");
                        if (!File.Exists(csc)) csc = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"Microsoft.NET\Framework\v4.0.30319\csc.exe");
                        if (File.Exists(csc))
                        {
                            string o, e;
                            RunProcessSync(csc, string.Format("/nologo /target:exe /optimize+ /out:\"{0}\" \"{1}\"", targetWrapper, localCs), out o, out e);
                        }
                    }
                }
            }

            // claude.cmd
            string claudeCmd = Path.Combine(userBinDir, "claude.cmd");
            string claudeCmdContent = "@echo off\r\n" +
                "setlocal enabledelayedexpansion\r\n" +
                "set \"HTTP_PROXY=http://127.0.0.1:" + port + "\"\r\n" +
                "set \"HTTPS_PROXY=http://127.0.0.1:" + port + "\"\r\n" +
                "set \"ALL_PROXY=http://127.0.0.1:" + port + "\"\r\n" +
                "set \"http_proxy=http://127.0.0.1:" + port + "\"\r\n" +
                "set \"https_proxy=http://127.0.0.1:" + port + "\"\r\n" +
                "set \"all_proxy=http://127.0.0.1:" + port + "\"\r\n" +
                "set \"NO_PROXY=" + DEFAULT_BYPASS + "\"\r\n" +
                "set \"no_proxy=" + DEFAULT_BYPASS + "\"\r\n" +
                "if exist \"%USERPROFILE%\\.local\\bin\\claude.exe\" (\r\n" +
                "    \"%USERPROFILE%\\.local\\bin\\claude.exe\" %*\r\n" +
                "    exit /b %ERRORLEVEL%\r\n" +
                ")\r\n" +
                "for /f \"delims=\" %%f in ('dir /b /s \"%USERPROFILE%\\.local\\share\\claude\\versions\\claude.exe\" 2^>nul') do (\r\n" +
                "    \"%%f\" %*\r\n" +
                "    exit /b %ERRORLEVEL%\r\n" +
                ")\r\n" +
                "for /d %%d in (\"%USERPROFILE%\\.vscode\\extensions\\anthropic.claude-code-*\") do (\r\n" +
                "    if not exist \"%%d\\resources\\native-binaries\\win32-x64\\claude.exe\" (\r\n" +
                "        if exist \"%USERPROFILE%\\.local\\bin\\claude.real.exe\" (\r\n" +
                "            mkdir \"%%d\\resources\\native-binaries\\win32-x64\" >nul 2>&1\r\n" +
                "            copy /y \"%USERPROFILE%\\.local\\bin\\claude.real.exe\" \"%%d\\resources\\native-binaries\\win32-x64\\claude.real.exe\" >nul 2>&1\r\n" +
                "            copy /y \"%USERPROFILE%\\.config\\claude-proxy\\bin\\claude_wrapper.exe\" \"%%d\\resources\\native-binaries\\win32-x64\\claude.exe\" >nul 2>&1\r\n" +
                "        )\r\n" +
                "    )\r\n" +
                "    if exist \"%%d\\resources\\native-binary\\claude.exe\" (\r\n" +
                "        \"%%d\\resources\\native-binary\\claude.exe\" %*\r\n" +
                "        exit /b %ERRORLEVEL%\r\n" +
                "    )\r\n" +
                "    if exist \"%%d\\resources\\native-binaries\\win32-x64\\claude.exe\" (\r\n" +
                "        \"%%d\\resources\\native-binaries\\win32-x64\\claude.exe\" %*\r\n" +
                "        exit /b %ERRORLEVEL%\r\n" +
                "    )\r\n" +
                ")\r\n" +
                "if exist \"%APPDATA%\\npm\\claude.cmd\" (\r\n" +
                "    call \"%APPDATA%\\npm\\claude.cmd\" %*\r\n" +
                "    exit /b %ERRORLEVEL%\r\n" +
                ")\r\n" +
                "echo [Error] Claude Code executable not found! >&2\r\n" +
                "echo Please run: install_cli.cmd to install official Claude Code via your proxy bridge. >&2\r\n" +
                "exit /b 1\r\n";
            File.WriteAllText(claudeCmd, claudeCmdContent, Encoding.ASCII);

            // status.cmd
            string statusCmd = Path.Combine(userBinDir, "status.cmd");
            string statusCmdContent = "@echo off\r\n" +
                "echo =========================================================\r\n" +
                "echo  Claude Code Proxy Status for %USERNAME%\r\n" +
                "echo =========================================================\r\n" +
                "echo Local Port: 127.0.0.1:" + port + "\r\n" +
                "netstat -ano | findstr \":" + port + "\" | findstr \"LISTENING\" >nul 2>&1\r\n" +
                "if %ERRORLEVEL% EQU 0 (\r\n" +
                "    echo [PORT]    Port " + port + " is LISTENING [ACTIVE]\r\n" +
                "    netstat -ano | findstr \":" + port + "\" | findstr \"LISTENING\"\r\n" +
                ") else (\r\n" +
                "    echo [PORT]    Port " + port + " is NOT LISTENING [STOPPED]\r\n" +
                ")\r\n" +
                "echo.\r\n" +
                "echo Process Status (GOST):\r\n" +
                "tasklist /fi \"imagename eq gost.exe\" 2>nul | findstr /i \"gost.exe\"\r\n" +
                "if %ERRORLEVEL% NEQ 0 echo [PROCESS] gost.exe is NOT running\r\n" +
                "echo.\r\n" +
                "echo Scheduled Task Status:\r\n" +
                "schtasks /query /tn \"ClaudeProxy_%USERNAME%\" >nul 2>&1\r\n" +
                "if %ERRORLEVEL% EQU 0 (\r\n" +
                "    echo [TASK]    Task \"ClaudeProxy_%USERNAME%\" is REGISTERED\r\n" +
                "    schtasks /query /tn \"ClaudeProxy_%USERNAME%\" /fo LIST 2>nul\r\n" +
                ") else (\r\n" +
                "    echo [TASK]    Task \"ClaudeProxy_%USERNAME%\" is NOT registered\r\n" +
                ")\r\n" +
                "echo =========================================================\r\n";
            File.WriteAllText(statusCmd, statusCmdContent, Encoding.ASCII);

            // start.cmd
            string startCmd = Path.Combine(userBinDir, "start.cmd");
            string startCmdContent = "@echo off\r\n" +
                "echo Starting ClaudeProxy_%USERNAME%...\r\n" +
                "schtasks /run /tn \"ClaudeProxy_%USERNAME%\" >nul 2>&1\r\n" +
                "timeout /t 2 >nul\r\n" +
                "call \"%~dp0status.cmd\"\r\n";
            File.WriteAllText(startCmd, startCmdContent, Encoding.ASCII);

            // stop.cmd
            string stopCmd = Path.Combine(userBinDir, "stop.cmd");
            string stopCmdContent = "@echo off\r\n" +
                "echo Stopping ClaudeProxy_%USERNAME%...\r\n" +
                "schtasks /end /tn \"ClaudeProxy_%USERNAME%\" >nul 2>&1\r\n" +
                "taskkill /f /im gost.exe >nul 2>&1\r\n" +
                "powershell -NoProfile -ExecutionPolicy Bypass -File \"%~dp0setup_claude_gui.ps1\" -Disable >nul 2>&1\r\n" +
                "echo [OK] Proxy bridge stopped.\r\n";
            File.WriteAllText(stopCmd, stopCmdContent, Encoding.ASCII);

            // gui.cmd
            string guiCmd = Path.Combine(userBinDir, "gui.cmd");
            string guiCmdContent = "@echo off\r\n" +
                "set \"PORT=" + port + "\"\r\n" +
                "echo [INFO] Closing any running Claude Desktop instances to apply proxy...\r\n" +
                "taskkill /f /im Claude.exe >nul 2>&1\r\n" +
                "timeout /t 1 >nul\r\n" +
                "powershell -NoProfile -ExecutionPolicy Bypass -File \"%~dp0setup_claude_gui.ps1\" -ProxyPort %PORT%\r\n";
            File.WriteAllText(guiCmd, guiCmdContent, Encoding.ASCII);

            string appExe = Assembly.GetExecutingAssembly().Location;

            // patch.cmd
            string patchCmd = Path.Combine(userBinDir, "patch.cmd");
            string patchCmdContent = "@echo off\r\n" +
                "\"" + appExe + "\" --patch\r\n";
            File.WriteAllText(patchCmd, patchCmdContent, Encoding.ASCII);

            // Copy helper scripts from appDir to userBinDir
            string[] helpersToCopy = new string[] {
                "install_cli.cmd",
                "install_claude_cli.ps1",
                "patch.cmd",
                "patch_vscode.cmd",
                "patch_vscode.ps1",
                "setup_claude_gui.ps1",
                "ClaudeProxyPatcher.exe",
                "build_gui.cmd",
                "app.ico",
                "ClaudeProxy.cer"
            };
            foreach (string helper in helpersToCopy)
            {
                string src = Path.Combine(appDir, helper);
                string dst = Path.Combine(userBinDir, helper);
                if (File.Exists(src))
                {
                    try { File.Copy(src, dst, true); } catch { }
                }
            }

            // uninstall.cmd
            string uninstallCmd = Path.Combine(userBinDir, "uninstall.cmd");
            string uninstallCmdContent = "@echo off\r\n" +
                "\"" + appExe + "\" --uninstall\r\n";
            File.WriteAllText(uninstallCmd, uninstallCmdContent, Encoding.ASCII);

            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("      [OK] Helper scripts created in " + userBinDir);
            Console.ResetColor();
        }

        static void AddPathToUserEnvironment(string userBinDir)
        {
            try
            {
                string currentPath = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";
                if (!currentPath.Contains(userBinDir))
                {
                    string newPath = userBinDir + ";" + currentPath;
                    Environment.SetEnvironmentVariable("PATH", newPath, EnvironmentVariableTarget.User);
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("      [OK] Added " + userBinDir + " to User PATH.");
                    Console.ResetColor();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("      Note: Unable to update User PATH registry: " + ex.Message);
            }
        }

        static void RegisterAndStartProxy(string username, int port, string socks5, string gostExe, bool isAdmin)
        {
            string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            string binDir = Path.Combine(programData, "claude-proxy", "bin");
            Directory.CreateDirectory(binDir);

            string logFile = Path.Combine(binDir, "gost_" + username + ".log");

            // Write runner script with log redirection
            string runCmdFile = Path.Combine(binDir, "run_" + username + ".cmd");
            string runCmdContent = string.Format(
                "@echo off\r\nchcp 65001 >nul\r\n\"{0}\" -L \"http://127.0.0.1:{1}\" -F \"{2}\" > \"{3}\" 2>&1\r\n",
                gostExe, port, socks5, logFile);
            File.WriteAllText(runCmdFile, runCmdContent, new UTF8Encoding(false));

            string taskName = "ClaudeProxy_" + username;

            // Remove previous task if exists
            string ignoreOut, ignoreErr;
            RunProcessSync("schtasks.exe", string.Format("/delete /tn \"{0}\" /f", taskName), out ignoreOut, out ignoreErr);

            bool registered = false;

            // Attempt 1: PowerShell script to register task with universal SYSTEM account
            if (isAdmin)
            {
                string psScriptPath = Path.Combine(binDir, "register_task_" + username + ".ps1");
                string psScriptContent = string.Format(
                    "$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c \"{0}\"'\r\n" +
                    "$trigger = New-ScheduledTaskTrigger -AtStartup\r\n" +
                    "$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\\SYSTEM' -LogonType ServiceAccount -RunLevel Highest\r\n" +
                    "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)\r\n" +
                    "Register-ScheduledTask -TaskName '{1}' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force\r\n" +
                    "Start-ScheduledTask -TaskName '{1}'\r\n",
                    runCmdFile, taskName);
                File.WriteAllText(psScriptPath, psScriptContent, Encoding.ASCII);

                string psOut, psErr;
                int psExit = RunProcessSync("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + psScriptPath + "\"", out psOut, out psErr);
                if (psExit == 0)
                {
                    registered = true;
                }
            }

            // Attempt 2: schtasks fallback
            if (!registered)
            {
                string schArgs = isAdmin
                    ? string.Format("/create /tn \"{0}\" /tr \"cmd.exe /c \\\"{1}\\\"\" /sc ONSTART /ru \"SYSTEM\" /rl HIGHEST /f", taskName, runCmdFile)
                    : string.Format("/create /tn \"{0}\" /tr \"cmd.exe /c \\\"{1}\\\"\" /sc ONLOGON /f", taskName, runCmdFile);

                string schOut, schErr;
                int schExit = RunProcessSync("schtasks.exe", schArgs, out schOut, out schErr);
                if (schExit == 0)
                {
                    registered = true;
                    RunProcessSync("schtasks.exe", string.Format("/run /tn \"{0}\"", taskName), out ignoreOut, out ignoreErr);
                }
            }

            // Attempt 3: User Startup folder fallback (using native shortcut, no .vbs!)
            string startupFolder = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
            string oldVbs = Path.Combine(startupFolder, "ClaudeProxyStartup.vbs");
            try { if (File.Exists(oldVbs)) File.Delete(oldVbs); } catch { }

            string startupLnk = Path.Combine(startupFolder, "ClaudeProxy.lnk");
            try
            {
                CreateShortcut(startupLnk, "cmd.exe", "/c \"" + runCmdFile + "\"",
                    "Claude Proxy Startup Runner", Path.GetDirectoryName(runCmdFile), gostExe, 0);
            }
            catch { }

            if (registered)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("      [OK] Task Scheduler registered: " + taskName + (isAdmin ? " (Trigger: AtStartup / SYSTEM)" : " (Trigger: AtLogOn)"));
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("      [OK] Autostart runner registered in Windows Startup folder (Fallback).");
                Console.ResetColor();
            }

            // Active verification: check if port 19000 is open
            bool isListening = false;
            for (int i = 0; i < 6; i++)
            {
                Thread.Sleep(500);
                if (CheckPortListening(port))
                {
                    isListening = true;
                    break;
                }
            }

            // If not yet listening, launch directly in background
            if (!isListening)
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c \"" + runCmdFile + "\"")
                    {
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        WindowStyle = ProcessWindowStyle.Hidden
                    };
                    Process.Start(psi);

                    for (int i = 0; i < 6; i++)
                    {
                        Thread.Sleep(500);
                        if (CheckPortListening(port))
                        {
                            isListening = true;
                            break;
                        }
                    }
                }
                catch { }
            }

            if (isListening)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("      [OK] Proxy bridge is actively listening on http://127.0.0.1:" + port);
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("      [!] Note: Port " + port + " did not respond within 3 seconds.");
                if (File.Exists(logFile))
                {
                    try
                    {
                        string logTail = File.ReadAllText(logFile);
                        if (!string.IsNullOrEmpty(logTail))
                        {
                            Console.WriteLine("      GOST Log (" + logFile + "): " + logTail.Trim());
                        }
                    }
                    catch { }
                }
                Console.ResetColor();
            }

            // Enable UWP LoopbackExempt for Claude Desktop if installed
            try
            {
                RunProcessSync("CheckNetIsolation.exe", "LoopbackExempt -a -n=Claude_pzs8sxrjxfjjc", out ignoreOut, out ignoreErr);
            }
            catch { }
        }

        static bool CheckPortListening(int port)
        {
            try
            {
                using (TcpClient client = new TcpClient())
                {
                    IAsyncResult res = client.BeginConnect("127.0.0.1", port, null, null);
                    bool success = res.AsyncWaitHandle.WaitOne(400);
                    if (success && client.Connected)
                    {
                        client.EndConnect(res);
                        return true;
                    }
                }
            }
            catch { }
            return false;
        }

        static void PatchUserClaude(string userProfile, string userBinDir)
        {
            string wrapperExe = Path.Combine(userBinDir, "claude_wrapper.exe");
            if (!File.Exists(wrapperExe))
            {
                string localWrapper = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "claude_wrapper.exe");
                if (File.Exists(localWrapper))
                {
                    try { File.Copy(localWrapper, wrapperExe, true); } catch { }
                }
            }

            if (!File.Exists(wrapperExe))
            {
                Console.WriteLine("      Note: claude_wrapper.exe not found. Skipping auto-patching.");
                return;
            }

            List<string> candidateDirs = new List<string>();

            // 1. VS Code standard & Insiders extensions
            string[] extRoots = new string[] {
                Path.Combine(userProfile, ".vscode", "extensions"),
                Path.Combine(userProfile, ".vscode-insiders", "extensions"),
                Path.Combine(userProfile, ".vscode-server", "extensions"),
                Path.Combine(userProfile, ".cursor", "extensions"),
                Path.Combine(userProfile, ".windsurf", "extensions")
            };
            foreach (string root in extRoots)
            {
                if (Directory.Exists(root))
                {
                    try
                    {
                        foreach (string d in Directory.GetDirectories(root))
                        {
                            string dirName = Path.GetFileName(d).ToLowerInvariant();
                            if (dirName.Contains("claude"))
                            {
                                candidateDirs.Add(d);
                                candidateDirs.Add(Path.Combine(d, "resources", "native-binary"));
                                candidateDirs.Add(Path.Combine(d, "resources", "native-binaries", "win32-x64"));
                            }
                        }
                    }
                    catch { }
                }
            }

            // 2. Standalone CLI in user profile (.local)
            candidateDirs.Add(Path.Combine(userProfile, ".local", "share", "claude", "versions"));
            candidateDirs.Add(Path.Combine(userProfile, ".local", "bin"));

            // 3. Claude Desktop GUI
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

            candidateDirs.Add(Path.Combine(localAppData, "Programs", "Claude"));
            candidateDirs.Add(Path.Combine(appData, "Claude", "claude-code"));
            string packagesDir = Path.Combine(localAppData, "Packages");
            if (Directory.Exists(packagesDir))
            {
                try
                {
                    foreach (string pkg in Directory.GetDirectories(packagesDir, "*Claude*"))
                    {
                        string roamingClaude = Path.Combine(pkg, "LocalCache", "Roaming", "Claude", "claude-code");
                        if (Directory.Exists(roamingClaude))
                        {
                            candidateDirs.Add(roamingClaude);
                        }
                    }
                }
                catch { }
            }

            // 4. Global npm modules
            candidateDirs.Add(Path.Combine(appData, "npm"));
            candidateDirs.Add(Path.Combine(appData, "npm", "node_modules", "@anthropic-ai", "claude-code"));

            // Locate real binary if available
            string globalRealBinary = null;
            string versDir = Path.Combine(userProfile, ".local", "share", "claude", "versions");
            if (Directory.Exists(versDir))
            {
                try
                {
                    string[] exes = Directory.GetFiles(versDir, "claude*.exe", SearchOption.AllDirectories);
                    foreach (string e in exes)
                    {
                        if (new FileInfo(e).Length > 1000000) { globalRealBinary = e; break; }
                    }
                }
                catch { }
            }
            if (string.IsNullOrEmpty(globalRealBinary))
            {
                string localReal = Path.Combine(userProfile, ".local", "bin", "claude.real.exe");
                if (File.Exists(localReal)) globalRealBinary = localReal;
                else
                {
                    string localExe = Path.Combine(userProfile, ".local", "bin", "claude.exe");
                    if (File.Exists(localExe) && new FileInfo(localExe).Length > 1000000) globalRealBinary = localExe;
                }
            }

            int patched = 0;
            HashSet<string> scannedDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (string baseDir in candidateDirs)
            {
                if (!Directory.Exists(baseDir))
                {
                    // Create if it's a native-binary directory inside an existing extension
                    if (baseDir.Contains("resources") && Directory.Exists(Path.GetDirectoryName(Path.GetDirectoryName(baseDir))))
                    {
                        try { Directory.CreateDirectory(baseDir); } catch { }
                    }
                    else continue;
                }

                try
                {
                    List<string> dirsToInspect = new List<string>();
                    dirsToInspect.Add(baseDir);

                    try
                    {
                        foreach (string sub in Directory.GetDirectories(baseDir))
                        {
                            dirsToInspect.Add(sub);
                        }
                    }
                    catch { }

                    foreach (string dir in dirsToInspect)
                    {
                        if (scannedDirs.Contains(dir)) continue;
                        scannedDirs.Add(dir);

                        string claudeExe = Path.Combine(dir, "claude.exe");
                        string claudeReal = Path.Combine(dir, "claude.real.exe");

                        // Case 0: Both missing, but we have global real binary and it's a native-binary folder
                        if (!File.Exists(claudeExe) && !File.Exists(claudeReal) && !string.IsNullOrEmpty(globalRealBinary) && dir.ToLowerInvariant().Contains("native-binar"))
                        {
                            try
                            {
                                File.Copy(globalRealBinary, claudeReal, true);
                                File.Copy(wrapperExe, claudeExe, true);
                                Console.ForegroundColor = ConsoleColor.Green;
                                Console.WriteLine("      [OK] Populated missing binary & wrapper in: " + dir);
                                Console.ResetColor();
                                patched++;
                            }
                            catch { }
                        }
                        // Case A: claude.real.exe exists, but claude.exe is missing (caused "No compatible Claude Code binary found")
                        else if (File.Exists(claudeReal) && !File.Exists(claudeExe))
                        {
                            try
                            {
                                File.Copy(wrapperExe, claudeExe, true);
                                Console.ForegroundColor = ConsoleColor.Green;
                                Console.WriteLine("      [OK] Replaced missing claude.exe with wrapper in: " + dir);
                                Console.ResetColor();
                                patched++;
                            }
                            catch (Exception ex)
                            {
                                Console.WriteLine("      [!] Error copying wrapper: " + ex.Message);
                            }
                        }
                        // Case B: claude.exe exists
                        else if (File.Exists(claudeExe))
                        {
                            FileInfo fi = new FileInfo(claudeExe);
                            if (!File.Exists(claudeReal))
                            {
                                if (fi.Length > 1000000) // Original Anthropic binary (> 1MB)
                                {
                                    try
                                    {
                                        File.Move(claudeExe, claudeReal);
                                        File.Copy(wrapperExe, claudeExe, true);
                                        Console.ForegroundColor = ConsoleColor.Green;
                                        Console.WriteLine("      [OK] Patched binary: " + claudeExe);
                                        Console.ResetColor();
                                        patched++;
                                    }
                                    catch (Exception ex)
                                    {
                                        Console.WriteLine("      [!] Error patching " + claudeExe + ": " + ex.Message);
                                    }
                                }
                            }
                            else
                            {
                                try
                                {
                                    File.Copy(wrapperExe, claudeExe, true);
                                    Console.ForegroundColor = ConsoleColor.Green;
                                    Console.WriteLine("      [OK] Updated wrapper at: " + claudeExe);
                                    Console.ResetColor();
                                    patched++;
                                }
                                catch { }
                            }
                        }
                    }
                }
                catch { }
            }

            if (patched == 0)
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("      [INFO] Claude Code native binary is not installed yet.");
                Console.WriteLine("      To install Claude Code CLI through the active proxy bridge, run:");
                Console.WriteLine("        install_cli.cmd");
                Console.WriteLine("      Or in PowerShell:");
                Console.WriteLine("        .\\install_claude_cli.ps1");
                Console.ResetColor();
            }
        }

        static void ConfigureVsCodeSettings(string userProfile, int port)
        {
            try
            {
                string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string[] settingsPaths = new string[] {
                    Path.Combine(appData, "Code", "User", "settings.json"),
                    Path.Combine(appData, "Code - Insiders", "User", "settings.json"),
                    Path.Combine(appData, "Cursor", "User", "settings.json"),
                    Path.Combine(appData, "Windsurf", "User", "settings.json")
                };

                string proxyUrl = "http://127.0.0.1:" + port;

                foreach (string file in settingsPaths)
                {
                    string dir = Path.GetDirectoryName(file);
                    if (!Directory.Exists(dir)) continue;

                    string json = File.Exists(file) ? File.ReadAllText(file, Encoding.UTF8) : "{\n}";
                    if (json.Contains("\"http.proxy\""))
                    {
                        json = System.Text.RegularExpressions.Regex.Replace(
                            json,
                            "\"http\\.proxy\"\\s*:\\s*\"[^\"]*\"",
                            string.Format("\"http.proxy\": \"{0}\"", proxyUrl)
                        );
                        File.WriteAllText(file, json, Encoding.UTF8);
                        Console.ForegroundColor = ConsoleColor.Green;
                        Console.WriteLine("      [OK] Updated VS Code proxy settings in: " + file);
                        Console.ResetColor();
                    }
                    else
                    {
                        json = json.Trim();
                        if (json.EndsWith("}"))
                        {
                            json = json.Substring(0, json.Length - 1).TrimEnd();
                            if (json.Length > 1 && !json.EndsWith(",")) json += ",";
                            json += string.Format("\n  \"http.proxy\": \"{0}\",\n  \"http.proxySupport\": \"override\"\n}}", proxyUrl);
                            File.WriteAllText(file, json, Encoding.UTF8);
                            Console.ForegroundColor = ConsoleColor.Green;
                            Console.WriteLine("      [OK] Configured VS Code proxy settings in: " + file);
                            Console.ResetColor();
                        }
                    }
                }
            }
            catch { }
        }

        static string EnsureCliBinaryInstalled(string userProfile, int port, string userBinDir)
        {
            // 1. Check if already present
            string localBin = Path.Combine(userProfile, ".local", "bin");
            string localExe = Path.Combine(localBin, "claude.exe");
            string localReal = Path.Combine(localBin, "claude.real.exe");
            if (File.Exists(localReal)) return localReal;
            if (File.Exists(localExe) && new FileInfo(localExe).Length > 1000000) return localExe;

            string versDir = Path.Combine(userProfile, ".local", "share", "claude", "versions");
            if (Directory.Exists(versDir))
            {
                try
                {
                    foreach (string f in Directory.GetFiles(versDir, "claude*.exe", SearchOption.AllDirectories))
                    {
                        if (new FileInfo(f).Length > 1000000) return f;
                    }
                }
                catch { }
            }

            // 2. Download via local proxy bridge
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("      [INFO] Claude CLI binary not found locally. Downloading official Anthropic binary via proxy...");
            Console.ResetColor();

            try
            {
                Directory.CreateDirectory(localBin);
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)12288 | (SecurityProtocolType)3072 | (SecurityProtocolType)768 | SecurityProtocolType.Tls;
                ServicePointManager.ServerCertificateValidationCallback = (sender, cert, chain, sslErrors) => true;
                using (WebClient wc = new WebClient())
                {
                    wc.Proxy = new WebProxy("127.0.0.1", port);
                    string ver = wc.DownloadString("https://downloads.claude.ai/claude-code-releases/latest").Trim();
                    if (!string.IsNullOrEmpty(ver))
                    {
                        string dlUrl = string.Format("https://downloads.claude.ai/claude-code-releases/{0}/win32-x64/claude.exe", ver);
                        wc.DownloadFile(dlUrl, localExe);
                        if (File.Exists(localExe) && new FileInfo(localExe).Length > 1000000)
                        {
                            Console.ForegroundColor = ConsoleColor.Green;
                            Console.WriteLine("      [OK] Successfully downloaded Claude Code v" + ver + " to: " + localExe);
                            Console.ResetColor();
                            return localExe;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("      Note downloading CLI: " + ex.Message);
            }

            return null;
        }

        static void ConfigureClaudeGui(string userProfile, int port)
        {
            try
            {
                // 1. LoopbackExempt for UWP Claude Desktop
                string ignoreOut, ignoreErr;
                RunProcessSync("CheckNetIsolation.exe", "LoopbackExempt -a -n=Claude_pzs8sxrjxfjjc", out ignoreOut, out ignoreErr);
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("      [OK] Granted UWP LoopbackExempt for Claude Desktop.");
                Console.ResetColor();

                // 2. Windows Internet Settings (WinINet)
                using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings", true))
                {
                    if (key != null)
                    {
                        key.SetValue("ProxyEnable", 1, Microsoft.Win32.RegistryValueKind.DWord);
                        key.SetValue("ProxyServer", string.Format("http=127.0.0.1:{0};https=127.0.0.1:{0}", port), Microsoft.Win32.RegistryValueKind.String);
                        key.SetValue("ProxyOverride", "localhost;127.0.0.1;<local>;*.ru;*.xn--p1ai;*.su;*.local;10.*;172.16.*;192.168.*", Microsoft.Win32.RegistryValueKind.String);
                        try { key.DeleteValue("AutoConfigURL"); } catch { }
                    }
                }
                RunProcessSync("powershell.exe", "-NoProfile -Command \"$n = Add-Type -MemberDefinition '[DllImport(\\\"wininet.dll\\\")] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);' -Name W -Namespace N -PassThru; $n::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0); $n::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)\"", out ignoreOut, out ignoreErr);
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("      [OK] Configured Windows proxy for Claude Desktop (port " + port + ").");
                Console.ResetColor();

                // 3. Create Desktop shortcut
                CreateDesktopShortcut(userProfile, port);
            }
            catch (Exception ex)
            {
                Console.WriteLine("      Note configuring GUI: " + ex.Message);
            }
        }

        static void CreateDesktopShortcut(string userProfile, int port)
        {
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string claudeExe = Path.Combine(localAppData, "Programs", "Claude", "Claude.exe");
                if (!File.Exists(claudeExe))
                {
                    string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
                    string candidate = Path.Combine(pf, "Claude", "Claude.exe");
                    if (File.Exists(candidate)) claudeExe = candidate;
                }

                string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);

                if (File.Exists(claudeExe))
                {
                    string shortcutPath = Path.Combine(desktop, "Claude-Proxy.lnk");
                    CreateShortcut(shortcutPath, claudeExe, "--proxy-server=\"http://127.0.0.1:" + port + "\"",
                        "Claude Desktop via SOCKS5 Proxy Bridge", Path.GetDirectoryName(claudeExe), claudeExe, 0);
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("      [OK] Created Desktop shortcut: Claude-Proxy.lnk");
                    Console.ResetColor();
                }

                // Claude Proxy Manager (GUI) Shortcut
                string appDir = AppDomain.CurrentDomain.BaseDirectory;
                string patcherExe = Path.Combine(userProfile, ".config", "claude-proxy", "bin", "ClaudeProxyPatcher.exe");
                if (!File.Exists(patcherExe)) patcherExe = Path.Combine(appDir, "ClaudeProxyPatcher.exe");
                if (File.Exists(patcherExe))
                {
                    string shortcutPath = Path.Combine(desktop, "Claude Proxy Manager.lnk");
                    CreateShortcut(shortcutPath, patcherExe, "",
                        "Claude Proxy Manager (Dashboard & System Tray)", Path.GetDirectoryName(patcherExe), patcherExe, 0);
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("      [OK] Created Desktop shortcut: Claude Proxy Manager.lnk");
                    Console.ResetColor();
                }
            }
            catch { }
        }

        static void CreateShortcut(string shortcutPath, string targetPath, string arguments, string description, string workingDir, string iconPath, int iconIndex)
        {
            try
            {
                IShellLinkW link = (IShellLinkW)new ShellLink();
                link.SetPath(targetPath);
                if (!string.IsNullOrEmpty(arguments)) link.SetArguments(arguments);
                if (!string.IsNullOrEmpty(description)) link.SetDescription(description);
                if (!string.IsNullOrEmpty(workingDir)) link.SetWorkingDirectory(workingDir);
                if (!string.IsNullOrEmpty(iconPath)) link.SetIconLocation(iconPath, iconIndex);

                System.Runtime.InteropServices.ComTypes.IPersistFile file = (System.Runtime.InteropServices.ComTypes.IPersistFile)link;
                file.Save(shortcutPath, true);
                return;
            }
            catch { }

            // Fallback: WScript.Shell in-memory COM object (no .vbs files needed)
            try
            {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType != null)
                {
                    dynamic shell = Activator.CreateInstance(shellType);
                    dynamic sc = shell.CreateShortcut(shortcutPath);
                    sc.TargetPath = targetPath;
                    if (!string.IsNullOrEmpty(arguments)) sc.Arguments = arguments;
                    if (!string.IsNullOrEmpty(description)) sc.Description = description;
                    if (!string.IsNullOrEmpty(workingDir)) sc.WorkingDirectory = workingDir;
                    if (!string.IsNullOrEmpty(iconPath)) sc.IconLocation = string.Format("{0},{1}", iconPath, iconIndex);
                    sc.Save();
                }
            }
            catch { }
        }

        static int PerformUninstall(string username, string userProfile, int port)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("\n[UNINSTALL] Removing Claude Code Proxy for user: " + username);
            Console.ResetColor();

            // 1. Remove Scheduled Task
            string taskName = "ClaudeProxy_" + username;
            string ignoreOut, ignoreErr;
            RunProcessSync("schtasks.exe", string.Format("/delete /tn \"{0}\" /f", taskName), out ignoreOut, out ignoreErr);
            Console.WriteLine("  [OK] Scheduled Task removed (if existed).");

            // 2. Remove Startup folder shortcuts/VBS if present
            string startupFolder = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
            string vbsFile = Path.Combine(startupFolder, "ClaudeProxyStartup.vbs");
            if (File.Exists(vbsFile))
            {
                try { File.Delete(vbsFile); Console.WriteLine("  [OK] Removed " + vbsFile); } catch { }
            }
            string lnkFile = Path.Combine(startupFolder, "ClaudeProxy.lnk");
            if (File.Exists(lnkFile))
            {
                try { File.Delete(lnkFile); Console.WriteLine("  [OK] Removed " + lnkFile); } catch { }
            }

            // 3. Remove runner cmd
            string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            string runCmdFile = Path.Combine(programData, "claude-proxy", "bin", "run_" + username + ".cmd");
            if (File.Exists(runCmdFile))
            {
                try { File.Delete(runCmdFile); } catch { }
            }

            // 4. Restore patched binaries in current user profile
            string[] searchRoots = new string[] {
                Path.Combine(userProfile, ".vscode", "extensions"),
                Path.Combine(userProfile, ".vscode-insiders", "extensions"),
                Path.Combine(userProfile, ".local", "share", "claude"),
                Path.Combine(userProfile, ".local", "bin")
            };

            foreach (string root in searchRoots)
            {
                if (!Directory.Exists(root)) continue;
                try
                {
                    string[] realFiles = Directory.GetFiles(root, "claude.real.exe", SearchOption.AllDirectories);
                    foreach (string real in realFiles)
                    {
                        string target = Path.Combine(Path.GetDirectoryName(real), "claude.exe");
                        try
                        {
                            if (File.Exists(target)) File.Delete(target);
                            File.Move(real, target);
                            Console.WriteLine("  [OK] Restored original binary: " + target);
                        }
                        catch { }
                    }
                }
                catch { }
            }

            // 5. Remove User PATH
            string userBinDir = Path.Combine(userProfile, ".config", "claude-proxy", "bin");
            try
            {
                string currentPath = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";
                if (currentPath.Contains(userBinDir))
                {
                    string[] parts = currentPath.Split(';');
                    List<string> clean = new List<string>();
                    foreach (string p in parts)
                    {
                        if (!string.IsNullOrEmpty(p) && !p.Equals(userBinDir, StringComparison.OrdinalIgnoreCase))
                            clean.Add(p);
                    }
                    Environment.SetEnvironmentVariable("PATH", string.Join(";", clean.ToArray()), EnvironmentVariableTarget.User);
                    Console.WriteLine("  [OK] Removed " + userBinDir + " from User PATH.");
                }
            }
            catch { }

            // 6. Remove .config/claude-proxy
            string configDir = Path.Combine(userProfile, ".config", "claude-proxy");
            if (Directory.Exists(configDir))
            {
                try
                {
                    Directory.Delete(configDir, true);
                    Console.WriteLine("  [OK] Cleaned config folder: " + configDir);
                }
                catch { }
            }

            // 7. Remove Desktop shortcut if present
            try
            {
                string desktopShortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Claude (Proxy).lnk");
                if (File.Exists(desktopShortcut)) { File.Delete(desktopShortcut); Console.WriteLine("  [OK] Removed " + desktopShortcut); }
                string desktopShortcut2 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Claude-Proxy.lnk");
                if (File.Exists(desktopShortcut2)) { File.Delete(desktopShortcut2); Console.WriteLine("  [OK] Removed " + desktopShortcut2); }
            }
            catch { }

            // 8. Disable Windows Internet Settings proxy
            try
            {
                RunProcessSync("powershell.exe", "-NoProfile -Command \"Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' -Name 'ProxyEnable' -Value 0 -Type DWord; Remove-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' -Name 'AutoConfigURL' -ErrorAction SilentlyContinue\"", out ignoreOut, out ignoreErr);
                Console.WriteLine("  [OK] Reset Windows proxy settings to direct connection.");
            }
            catch { }

            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("\nUninstallation completed successfully for " + username + ".");
            Console.ResetColor();
            return 0;
        }

        static void ShowStatus(string username, int port)
        {
            Console.WriteLine("\nProxy Status for " + username + ":");
            Console.WriteLine("  Local Port: 127.0.0.1:" + port);
            bool listening = CheckPortListening(port);
            if (listening)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("  Status    : ACTIVE (Port " + port + " is listening)");
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("  Status    : STOPPED (Port " + port + " is not listening)");
                Console.ResetColor();
            }
            Console.WriteLine("\nScheduled Task:");
            string outStr, errStr;
            RunProcessSync("schtasks.exe", "/query /tn \"ClaudeProxy_" + username + "\" /fo LIST", out outStr, out errStr);
            if (!string.IsNullOrEmpty(outStr)) Console.WriteLine(outStr.Trim());
            else Console.WriteLine("  Task ClaudeProxy_" + username + " is not registered.");
        }

        static int RunProcessSync(string file, string arguments, out string standardOutput, out string standardError)
        {
            standardOutput = "";
            standardError = "";
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(file, arguments)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                StringBuilder sbOut = new StringBuilder();
                StringBuilder sbErr = new StringBuilder();
                using (Process p = new Process())
                {
                    p.StartInfo = psi;
                    p.OutputDataReceived += (s, e) => { if (e.Data != null) sbOut.AppendLine(e.Data); };
                    p.ErrorDataReceived += (s, e) => { if (e.Data != null) sbErr.AppendLine(e.Data); };
                    p.Start();
                    p.BeginOutputReadLine();
                    p.BeginErrorReadLine();
                    p.WaitForExit(10000);
                    standardOutput = sbOut.ToString();
                    standardError = sbErr.ToString();
                    return p.ExitCode;
                }
            }
            catch (Exception ex)
            {
                standardError = ex.Message;
                return -1;
            }
        }
    }

    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLink { }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    internal interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, out IntPtr pfd, int fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short pwHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, int dwReserved);
        void Resolve(IntPtr hwnd, int fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }
}
