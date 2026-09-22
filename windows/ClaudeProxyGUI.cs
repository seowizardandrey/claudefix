// ClaudeProxyGUI.cs - Modern Native Windows GUI & System Tray Manager for Claude Code Proxy & Auto-Patcher
// Compiles with: C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /optimize+ /out:ClaudeProxyPatcher.exe /reference:System.Windows.Forms.dll,System.Drawing.dll,System.dll,System.Core.dll ClaudeProxyGUI.cs

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Claude Proxy Manager")]
[assembly: AssemblyDescription("https://github.com/seowizardandrey/claudefix")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("Andrey Sokolov")]
[assembly: AssemblyProduct("Claude Code Proxy")]
[assembly: AssemblyCopyright("Copyright © 2026 Andrey Sokolov (seowizard.andrey@gmail.com)")]
[assembly: AssemblyTrademark("https://github.com/seowizardandrey/claudefix")]
[assembly: AssemblyCulture("")]
[assembly: AssemblyVersion("2.1.0.0")]
[assembly: AssemblyFileVersion("2.1.0.0")]

namespace ClaudeProxyManager
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            try
            {
                // Enable TLS 1.2 and TLS 1.3 across the entire process (SecurityProtocolType 3072 and 12288)
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)12288 | (SecurityProtocolType)3072 | (SecurityProtocolType)768 | SecurityProtocolType.Tls;
                ServicePointManager.ServerCertificateValidationCallback = (sender, cert, chain, sslErrors) => true;
            }
            catch { }

            bool startMinimized = false;
            foreach (string arg in args)
            {
                if (arg.Equals("--tray", StringComparison.OrdinalIgnoreCase) ||
                    arg.Equals("-m", StringComparison.OrdinalIgnoreCase) ||
                    arg.Equals("--minimized", StringComparison.OrdinalIgnoreCase))
                {
                    startMinimized = true;
                }
            }

            Application.Run(new MainForm(startMinimized));
        }
    }

    public class MainForm : Form
    {
        // Colors - Windows 11 Fluent Dark Palette
        static readonly Color BgDark = Color.FromArgb(24, 24, 37);         // #181825
        static readonly Color CardDark = Color.FromArgb(30, 30, 46);       // #1e1e2e
        static readonly Color CardDarker = Color.FromArgb(20, 20, 30);     // #14141e
        static readonly Color BorderDark = Color.FromArgb(49, 50, 68);     // #313244
        static readonly Color TextWhite = Color.FromArgb(240, 242, 250);   // #f0f2fa
        static readonly Color TextMuted = Color.FromArgb(166, 173, 200);   // #a6adc8
        static readonly Color AccentCyan = Color.FromArgb(137, 180, 250);  // #89b4fa
        static readonly Color GreenActive = Color.FromArgb(166, 227, 161); // #a6e3a1
        static readonly Color RedStopped = Color.FromArgb(243, 139, 168);  // #f38ba8
        static readonly Color AmberWarn = Color.FromArgb(249, 226, 175);   // #f9e2af
        static readonly Color InputBg = Color.FromArgb(40, 40, 60);        // #28283c

        const string DEFAULT_BYPASS = "localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,*.local,github.com,*.github.com,raw.githubusercontent.com,objects.githubusercontent.com,gitlab.com,*.gitlab.com,bitbucket.org,*.bitbucket.org,npmjs.org,*.npmjs.org,registry.npmjs.org,yarnpkg.com,*.yarnpkg.com,pypi.org,*.pypi.org,pythonhosted.org,*.pythonhosted.org,files.pythonhosted.org,crates.io,*.crates.io,pkg.go.dev,proxy.golang.org,rubygems.org,*.rubygems.org,packagist.org,*.packagist.org,docker.io,*.docker.io,docker.com,*.docker.com,*.ru,*.xn--p1ai,*.su";

        // System Paths & Config
        string userProfile;
        string currentUser;
        string userConfigDir;
        string userBinDir;
        string proxyEnvFile;
        string bypassFile;
        int proxyPort = 19000;
        string socks5Url = "";
        string bypassList = "";

        // UI Controls
        NotifyIcon trayIcon;
        ContextMenuStrip trayMenu;
        System.Windows.Forms.Timer refreshTimer;
        bool isInitialStartMinimized;

        // Top Banner Controls
        Label lblSubtitle;
        Panel pnlStatusPill;
        Label lblPillText;

        // Cards Status Labels
        Label lblGostStatus;
        Label lblPortStatus;
        Label lblTaskStatus;
        Label lblVsCodeStatus;
        Label lblCliStatus;
        Label lblGuiStatus;

        // Badges
        Label badgeGost;
        Label badgePort;
        Label badgeTask;
        Label badgeVsCode;
        Label badgeCli;
        Label badgeGui;

        // Action Buttons
        Button btnToggleProxy;
        Button btnRepatch;
        Button btnTestLocal;
        Button btnTestSocks5;
        Button btnLaunchClaude;

        // Settings Controls
        TextBox txtSocks5Url;
        TextBox txtPort;
        ListBox lstBypass;
        TextBox txtBypass;
        TextBox txtNewRule;
        Button btnAddRule;
        Button btnDeleteRule;
        Button btnToggleBypassMode;
        Label lblBypassHeader;
        CheckBox chkTaskAutostart;
        CheckBox chkTrayAutostart;
        Button btnSaveSettings;
        Button btnTogglePassword;
        Button btnSettingsTestSocks5;
        Button btnCreateShortcut;
        bool passwordVisible = false;
        bool bypassTextMode = false;

        // Tab Navigation & Views
        Panel pnlTop;
        Panel pnlContent;
        Panel pnlDashboard;
        Panel pnlSettings;
        Panel pnlLogs;
        Button tabBtnDashboard;
        Button tabBtnSettings;
        Button tabBtnLogs;
        TextBox txtLogs;

        public MainForm(bool startMinimized)
        {
            this.isInitialStartMinimized = startMinimized;
            InitializePaths();
            LoadConfig();
            InitializeComponent();
            SetupTray();

            // Refresh timer (every 3 seconds)
            refreshTimer = new System.Windows.Forms.Timer();
            refreshTimer.Interval = 3000;
            refreshTimer.Tick += (s, e) => RefreshStatus();
            refreshTimer.Start();

            // Initial immediate refresh
            RefreshStatus();
        }

        void InitializePaths()
        {
            currentUser = Environment.UserName;
            userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            userConfigDir = Path.Combine(userProfile, ".config", "claude-proxy");
            userBinDir = Path.Combine(userConfigDir, "bin");
            proxyEnvFile = Path.Combine(userConfigDir, "proxy.env");
            bypassFile = Path.Combine(userConfigDir, "bypass.conf");

            try
            {
                Directory.CreateDirectory(userConfigDir);
                Directory.CreateDirectory(userBinDir);
            }
            catch { }
        }

        void LoadConfig()
        {
            if (File.Exists(proxyEnvFile))
            {
                try
                {
                    foreach (string line in File.ReadAllLines(proxyEnvFile))
                    {
                        string trimmed = line.Trim();
                        if (trimmed.StartsWith("PROXY_PORT="))
                        {
                            int p;
                            if (int.TryParse(trimmed.Substring(11).Trim(), out p)) proxyPort = p;
                        }
                        else if (trimmed.StartsWith("SOCKS5_URL="))
                        {
                            socks5Url = trimmed.Substring(11).Trim().Trim('"');
                        }
                        else if (trimmed.StartsWith("NO_PROXY="))
                        {
                            bypassList = trimmed.Substring(9).Trim().Trim('"');
                        }
                    }
                }
                catch { }
            }

            if (string.IsNullOrEmpty(bypassList) && File.Exists(bypassFile))
            {
                try
                {
                    bypassList = File.ReadAllText(bypassFile).Replace("\r", "").Replace("\n", ",").Trim(',');
                }
                catch { }
            }

            if (string.IsNullOrEmpty(bypassList))
            {
                bypassList = DEFAULT_BYPASS;
            }
        }

        void SaveConfig()
        {
            try
            {
                Directory.CreateDirectory(userConfigDir);
                string content = string.Format(
                    "# Claude Code Proxy Configuration\nPROXY_PORT={0}\nSOCKS5_URL=\"{1}\"\nPROXY_MODE=\"anthropic_only\"\nNO_PROXY=\"{2}\"\nTASK_AUTOSTART={3}\n",
                    proxyPort, socks5Url, bypassList, chkTaskAutostart != null && chkTaskAutostart.Checked ? "true" : "false");
                File.WriteAllText(proxyEnvFile, content, Encoding.UTF8);

                File.WriteAllText(bypassFile, bypassList.Replace(",", "\n") + "\n", Encoding.UTF8);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Ошибка сохранения конфигурации: " + ex.Message, "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        void InitializeComponent()
        {
            this.Text = "Claude Proxy Manager";
            this.Size = new Size(820, 710);
            this.MinimumSize = new Size(800, 670);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = BgDark;
            this.ForeColor = TextWhite;
            this.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);
            this.DoubleBuffered = true;

            // Form Icon (from embedded win32 icon or dynamic vector)
            try
            {
                this.Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);
            }
            catch
            {
                this.Icon = CreateAppIcon(GreenActive);
            }

            // Close behavior: minimize to tray
            this.FormClosing += (s, e) =>
            {
                if (e.CloseReason == CloseReason.UserClosing)
                {
                    e.Cancel = true;
                    this.Hide();
                    if (trayIcon != null)
                    {
                        trayIcon.ShowBalloonTip(2000, "Claude Proxy Manager", "Приложение свернуто в системный трей.", ToolTipIcon.Info);
                    }
                }
            };

            // 1. Unified Top Panel (Header + Navigation Tabs) - Height 115
            pnlTop = new Panel
            {
                Dock = DockStyle.Top,
                Height = 115,
                BackColor = CardDark,
                Padding = new Padding(20, 10, 20, 0)
            };

            Label lblTitle = new Label
            {
                Text = "CLAUDE PROXY MANAGER",
                Font = new Font("Segoe UI", 12f, FontStyle.Bold),
                ForeColor = AccentCyan,
                Location = new Point(20, 12),
                AutoSize = true
            };
            pnlTop.Controls.Add(lblTitle);

            lblSubtitle = new Label
            {
                Text = "Пользователь: " + currentUser + " | Мост: 127.0.0.1:" + proxyPort,
                Font = new Font("Segoe UI", 8.5f, FontStyle.Regular),
                ForeColor = TextMuted,
                Location = new Point(20, 38),
                AutoSize = true
            };
            pnlTop.Controls.Add(lblSubtitle);

            // Status Pill badge in header
            pnlStatusPill = new Panel
            {
                Size = new Size(165, 32),
                Location = new Point(pnlTop.Width - 195, 16),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                BackColor = CardDarker
            };
            pnlStatusPill.Paint += (s, e) =>
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen pen = new Pen(BorderDark, 1.5f))
                {
                    e.Graphics.DrawRectangle(pen, 0, 0, pnlStatusPill.Width - 1, pnlStatusPill.Height - 1);
                }
            };
            lblPillText = new Label
            {
                Text = "● ПРОВЕРКА...",
                ForeColor = AmberWarn,
                Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleCenter
            };
            pnlStatusPill.Controls.Add(lblPillText);
            pnlTop.Controls.Add(pnlStatusPill);

            // Navigation Tabs inside Top Panel
            tabBtnDashboard = CreateTabButton("Дашборд", 20, 72);
            tabBtnSettings = CreateTabButton("Настройки", 140, 72);
            tabBtnLogs = CreateTabButton("Журнал", 260, 72);

            tabBtnDashboard.Click += (s, e) => SwitchTab(0);
            tabBtnSettings.Click += (s, e) => SwitchTab(1);
            tabBtnLogs.Click += (s, e) => SwitchTab(2);

            pnlTop.Controls.Add(tabBtnDashboard);
            pnlTop.Controls.Add(tabBtnSettings);
            pnlTop.Controls.Add(tabBtnLogs);

            // 2. Main Content Area (fills below Top Panel)
            pnlContent = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = BgDark,
                Padding = new Padding(20, 15, 20, 20)
            };

            // Order of adding docked controls is critical in WinForms:
            this.Controls.Add(pnlContent); // Dock = Fill (fills remainder)
            this.Controls.Add(pnlTop);     // Dock = Top (docked at top)

            // Views inside Content Area
            pnlDashboard = new Panel { Dock = DockStyle.Fill, BackColor = BgDark, AutoScroll = true };
            pnlContent.Controls.Add(pnlDashboard);
            BuildDashboard(pnlDashboard);

            pnlSettings = new Panel { Dock = DockStyle.Fill, BackColor = BgDark, Visible = false, AutoScroll = true };
            pnlContent.Controls.Add(pnlSettings);
            BuildSettings(pnlSettings);

            pnlLogs = new Panel { Dock = DockStyle.Fill, BackColor = BgDark, Visible = false };
            pnlContent.Controls.Add(pnlLogs);
            BuildLogs(pnlLogs);

            // Switch to Dashboard by default
            SwitchTab(0);
        }

        Button CreateTabButton(string text, int left, int top)
        {
            Button btn = new Button
            {
                Text = text,
                Location = new Point(left, top),
                Size = new Size(110, 36),
                FlatStyle = FlatStyle.Flat,
                BackColor = CardDark,
                ForeColor = TextMuted,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Regular),
                Cursor = Cursors.Hand
            };
            btn.FlatAppearance.BorderSize = 0;
            return btn;
        }

        void SwitchTab(int index)
        {
            pnlDashboard.Visible = (index == 0);
            pnlSettings.Visible = (index == 1);
            pnlLogs.Visible = (index == 2);

            tabBtnDashboard.ForeColor = (index == 0) ? AccentCyan : TextMuted;
            tabBtnDashboard.Font = new Font("Segoe UI", 9.5f, (index == 0) ? FontStyle.Bold : FontStyle.Regular);

            tabBtnSettings.ForeColor = (index == 1) ? AccentCyan : TextMuted;
            tabBtnSettings.Font = new Font("Segoe UI", 9.5f, (index == 1) ? FontStyle.Bold : FontStyle.Regular);

            tabBtnLogs.ForeColor = (index == 2) ? AccentCyan : TextMuted;
            tabBtnLogs.Font = new Font("Segoe UI", 9.5f, (index == 2) ? FontStyle.Bold : FontStyle.Regular);

            if (index == 1)
            {
                // Reload current values into settings view
                LoadConfig();
                if (txtSocks5Url != null) txtSocks5Url.Text = socks5Url;
                if (txtPort != null) txtPort.Text = proxyPort.ToString();
                if (chkTaskAutostart != null) chkTaskAutostart.Checked = CheckTaskSchedulerRegistered();
                if (chkTrayAutostart != null) chkTrayAutostart.Checked = CheckTrayAutostartRegistered();
                PopulateBypassControls();
            }
            else if (index == 2)
            {
                LoadLogs();
            }
        }

        void BuildDashboard(Panel parent)
        {
            // Cards Container
            Panel pnlCards = new Panel
            {
                Location = new Point(0, 0),
                Size = new Size(parent.Width - 10, 280),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = BgDark
            };
            parent.Controls.Add(pnlCards);

            int cardWidth = 365;
            int cardHeight = 82;
            int col1 = 0;
            int col2 = 385;

            // Row 1: GOST Process & Local Port
            Panel c1 = CreateStatusCard("Прокси-мост GOST (Движок)", "gost.exe", out lblGostStatus, out badgeGost, col1, 5, cardWidth, cardHeight);
            Panel c2 = CreateStatusCard("Локальный порт", "127.0.0.1:" + proxyPort, out lblPortStatus, out badgePort, col2, 5, cardWidth, cardHeight);

            // Row 2: Autostart Task & VS Code Extension
            Panel c3 = CreateStatusCard("Планировщик Windows", "ClaudeProxy_" + currentUser, out lblTaskStatus, out badgeTask, col1, 95, cardWidth, cardHeight);
            Panel c4 = CreateStatusCard("Плагин VS Code", "anthropic.claude-code", out lblVsCodeStatus, out badgeVsCode, col2, 95, cardWidth, cardHeight);

            // Row 3: Standalone CLI & Claude Desktop GUI
            Panel c5 = CreateStatusCard("Claude Code CLI", "claude.exe в .local\\bin", out lblCliStatus, out badgeCli, col1, 185, cardWidth, cardHeight);
            Panel c6 = CreateStatusCard("Claude Desktop (GUI)", "WinINet & LoopbackExempt", out lblGuiStatus, out badgeGui, col2, 185, cardWidth, cardHeight);

            pnlCards.Controls.AddRange(new Control[] { c1, c2, c3, c4, c5, c6 });

            // Bottom Action Controls Container (Two rows of buttons)
            Panel pnlActions = new Panel
            {
                Location = new Point(0, 285),
                Size = new Size(parent.Width - 10, 160),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = CardDark,
                Padding = new Padding(15)
            };
            pnlActions.Paint += (s, e) =>
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen p = new Pen(BorderDark, 1f))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, pnlActions.Width - 1, pnlActions.Height - 1);
                }
            };
            parent.Controls.Add(pnlActions);

            Label lblActionsTitle = new Label
            {
                Text = "БЫСТРЫЕ ДЕЙСТВИЯ",
                Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
                ForeColor = TextMuted,
                Location = new Point(15, 10),
                AutoSize = true
            };
            pnlActions.Controls.Add(lblActionsTitle);

            // Row 1: Start/Stop, Re-Patch, Launch Claude
            btnToggleProxy = CreateActionButton("Остановить мост", RedStopped, Color.FromArgb(17, 17, 27), 15, 32, 230);
            btnToggleProxy.Click += (s, e) => ToggleProxyBridge();
            pnlActions.Controls.Add(btnToggleProxy);

            btnRepatch = CreateActionButton("⚡ Перепатчить всё", GreenActive, Color.FromArgb(17, 17, 27), 260, 32, 230);
            btnRepatch.Click += (s, e) => ExecuteRepatch();
            pnlActions.Controls.Add(btnRepatch);

            btnLaunchClaude = CreateActionButton("🚀 Claude Desktop", Color.FromArgb(49, 50, 68), TextWhite, 505, 32, 220);
            btnLaunchClaude.Click += (s, e) => LaunchClaudeDesktop();
            pnlActions.Controls.Add(btnLaunchClaude);

            // Row 2: Two dedicated Test buttons (Local HTTP Bridge & Direct Upstream SOCKS5)
            btnTestLocal = CreateActionButton("🌐 Тест локального моста (127.0.0.1)", Color.FromArgb(49, 50, 68), TextWhite, 15, 80, 345);
            btnTestLocal.Click += (s, e) => TestLocalProxyBridge();
            pnlActions.Controls.Add(btnTestLocal);

            btnTestSocks5 = CreateActionButton("🔒 Тест внешнего SOCKS5 (Прямой)", Color.FromArgb(49, 50, 68), TextWhite, 375, 80, 350);
            btnTestSocks5.Click += (s, e) => TestUpstreamSocks5Direct();
            pnlActions.Controls.Add(btnTestSocks5);

            // Status notice label
            Label lblFooterNotice = new Label
            {
                Text = "Совет: Нажмите «⚡ Перепатчить всё» после любого обновления плагина VS Code или CLI.",
                ForeColor = TextMuted,
                Font = new Font("Segoe UI", 8.5f, FontStyle.Italic),
                Location = new Point(15, 132),
                AutoSize = true
            };
            pnlActions.Controls.Add(lblFooterNotice);
        }

        Panel CreateStatusCard(string title, string subtitle, out Label lblVal, out Label badge, int x, int y, int w, int h)
        {
            Panel card = new Panel
            {
                Location = new Point(x, y),
                Size = new Size(w, h),
                BackColor = CardDark,
                Padding = new Padding(12)
            };
            card.Paint += (s, e) =>
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen p = new Pen(BorderDark, 1f))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, card.Width - 1, card.Height - 1);
                }
            };

            Label lblT = new Label
            {
                Text = title,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                ForeColor = TextWhite,
                Location = new Point(12, 10),
                AutoSize = true
            };
            card.Controls.Add(lblT);

            badge = new Label
            {
                Text = "ПРОВЕРКА",
                Font = new Font("Segoe UI", 7.5f, FontStyle.Bold),
                ForeColor = AmberWarn,
                BackColor = CardDarker,
                Location = new Point(w - 95, 10),
                Size = new Size(85, 20),
                TextAlign = ContentAlignment.MiddleCenter
            };
            card.Controls.Add(badge);

            lblVal = new Label
            {
                Text = subtitle,
                Font = new Font("Segoe UI", 8.5f, FontStyle.Regular),
                ForeColor = TextMuted,
                Location = new Point(12, 36),
                Size = new Size(w - 24, 40)
            };
            card.Controls.Add(lblVal);

            return card;
        }

        Button CreateActionButton(string text, Color bg, Color fg, int x, int y, int w)
        {
            Button btn = new Button
            {
                Text = text,
                Location = new Point(x, y),
                Size = new Size(w, 40),
                FlatStyle = FlatStyle.Flat,
                BackColor = bg,
                ForeColor = fg,
                Font = new Font("Segoe UI", 9f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btn.FlatAppearance.BorderSize = 0;
            return btn;
        }

        void BuildSettings(Panel parent)
        {
            Panel pnlBox = new Panel
            {
                Location = new Point(0, 0),
                Size = new Size(parent.Width - 10, 560),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = CardDark,
                Padding = new Padding(25)
            };
            pnlBox.Paint += (s, e) =>
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen p = new Pen(BorderDark, 1f))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, pnlBox.Width - 1, pnlBox.Height - 1);
                }
            };
            parent.Controls.Add(pnlBox);

            int y = 18;

            // 1. Upstream SOCKS5 Proxy
            Label l1 = new Label
            {
                Text = "Внешний SOCKS5 Прокси (Upstream):",
                ForeColor = TextWhite,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                Location = new Point(25, y),
                AutoSize = true
            };
            pnlBox.Controls.Add(l1);
            y += 24;

            txtSocks5Url = new TextBox
            {
                Text = socks5Url,
                Location = new Point(25, y),
                Size = new Size(460, 28),
                BackColor = InputBg,
                ForeColor = TextWhite,
                Font = new Font("Consolas", 10f),
                BorderStyle = BorderStyle.FixedSingle,
                UseSystemPasswordChar = true
            };
            pnlBox.Controls.Add(txtSocks5Url);

            btnTogglePassword = new Button
            {
                Text = "Показать",
                Location = new Point(495, y),
                Size = new Size(85, 26),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(49, 50, 68),
                ForeColor = TextWhite,
                Font = new Font("Segoe UI", 8.5f),
                Cursor = Cursors.Hand
            };
            btnTogglePassword.FlatAppearance.BorderSize = 0;
            btnTogglePassword.Click += (s, e) =>
            {
                passwordVisible = !passwordVisible;
                txtSocks5Url.UseSystemPasswordChar = !passwordVisible;
                btnTogglePassword.Text = passwordVisible ? "Скрыть" : "Показать";
            };
            pnlBox.Controls.Add(btnTogglePassword);

            btnSettingsTestSocks5 = new Button
            {
                Text = "Проверить",
                Location = new Point(590, y),
                Size = new Size(95, 26),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(49, 50, 68),
                ForeColor = AccentCyan,
                Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnSettingsTestSocks5.FlatAppearance.BorderSize = 0;
            btnSettingsTestSocks5.Click += (s, e) =>
            {
                string target = txtSocks5Url.Text.Trim();
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    string msg;
                    bool ok = TestDirectSocks5Handshake(target, out msg);
                    this.BeginInvoke(new Action(() =>
                    {
                        MessageBox.Show(msg, ok ? "SOCKS5 доступен" : "Ошибка подключения к SOCKS5",
                            MessageBoxButtons.OK, ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
                    }));
                });
            };
            pnlBox.Controls.Add(btnSettingsTestSocks5);
            y += 30;

            Label lblHint = new Label
            {
                Text = "Формат: socks5://USER:PASSWORD@HOST:PORT или socks5://HOST:PORT",
                ForeColor = TextMuted,
                Font = new Font("Segoe UI", 8f, FontStyle.Italic),
                Location = new Point(25, y),
                AutoSize = true
            };
            pnlBox.Controls.Add(lblHint);
            y += 24;

            // 2. Local Port
            Label l2 = new Label
            {
                Text = "Локальный порт прослушивания (Bridge Port):",
                ForeColor = TextWhite,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                Location = new Point(25, y),
                AutoSize = true
            };
            pnlBox.Controls.Add(l2);
            y += 24;

            txtPort = new TextBox
            {
                Text = proxyPort.ToString(),
                Location = new Point(25, y),
                Size = new Size(140, 28),
                BackColor = InputBg,
                ForeColor = TextWhite,
                Font = new Font("Consolas", 10f),
                BorderStyle = BorderStyle.FixedSingle
            };
            pnlBox.Controls.Add(txtPort);

            Label lblPortHint = new Label
            {
                Text = "Порт по умолчанию: 19000 (или 19000-19099 для изоляции пользователей)",
                ForeColor = TextMuted,
                Font = new Font("Segoe UI", 8.5f, FontStyle.Italic),
                Location = new Point(175, y + 4),
                AutoSize = true
            };
            pnlBox.Controls.Add(lblPortHint);
            y += 36;

            // 3. Proxy Exceptions (Bypass Domains) Manager
            lblBypassHeader = new Label
            {
                Text = "Исключения прокси (Bypass Domains):",
                ForeColor = TextWhite,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                Location = new Point(25, y),
                AutoSize = true
            };
            pnlBox.Controls.Add(lblBypassHeader);

            btnToggleBypassMode = new Button
            {
                Text = "📝 Режим текста",
                Location = new Point(545, y - 2),
                Size = new Size(150, 24),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(49, 50, 68),
                ForeColor = AccentCyan,
                Font = new Font("Segoe UI", 8.5f),
                Cursor = Cursors.Hand
            };
            btnToggleBypassMode.FlatAppearance.BorderSize = 0;
            btnToggleBypassMode.Click += (s, e) => ToggleBypassEditMode();
            pnlBox.Controls.Add(btnToggleBypassMode);
            y += 28;

            // Add Rule Row
            txtNewRule = new TextBox
            {
                Location = new Point(25, y),
                Size = new Size(420, 26),
                BackColor = InputBg,
                ForeColor = TextWhite,
                Font = new Font("Consolas", 9.5f),
                BorderStyle = BorderStyle.FixedSingle
            };
            txtNewRule.KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Enter)
                {
                    e.SuppressKeyPress = true;
                    AddSingleBypassRule();
                }
            };
            pnlBox.Controls.Add(txtNewRule);

            btnAddRule = new Button
            {
                Text = "➕ Добавить",
                Location = new Point(455, y),
                Size = new Size(115, 26),
                FlatStyle = FlatStyle.Flat,
                BackColor = AccentCyan,
                ForeColor = Color.FromArgb(17, 17, 27),
                Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnAddRule.FlatAppearance.BorderSize = 0;
            btnAddRule.Click += (s, e) => AddSingleBypassRule();
            pnlBox.Controls.Add(btnAddRule);

            btnDeleteRule = new Button
            {
                Text = "🗑 Удалить",
                Location = new Point(580, y),
                Size = new Size(115, 26),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(49, 50, 68),
                ForeColor = RedStopped,
                Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnDeleteRule.FlatAppearance.BorderSize = 0;
            btnDeleteRule.Click += (s, e) => DeleteSelectedBypassRules();
            pnlBox.Controls.Add(btnDeleteRule);
            y += 30;

            // Rule Display: ListBox (default) or multiline TextBox
            lstBypass = new ListBox
            {
                Location = new Point(25, y),
                Size = new Size(670, 130),
                BackColor = InputBg,
                ForeColor = TextWhite,
                Font = new Font("Consolas", 9.5f),
                BorderStyle = BorderStyle.FixedSingle,
                SelectionMode = SelectionMode.MultiExtended
            };
            lstBypass.KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Delete)
                {
                    DeleteSelectedBypassRules();
                }
            };
            pnlBox.Controls.Add(lstBypass);

            txtBypass = new TextBox
            {
                Location = new Point(25, y),
                Size = new Size(670, 130),
                Multiline = true,
                BackColor = InputBg,
                ForeColor = TextWhite,
                Font = new Font("Consolas", 9.5f),
                BorderStyle = BorderStyle.FixedSingle,
                ScrollBars = ScrollBars.Vertical,
                Visible = false
            };
            pnlBox.Controls.Add(txtBypass);
            y += 136;

            // Presets Toolbar
            Label lblPresets = new Label
            {
                Text = "Быстрые наборы:",
                ForeColor = TextMuted,
                Font = new Font("Segoe UI", 8.5f),
                Location = new Point(25, y + 4),
                AutoSize = true
            };
            pnlBox.Controls.Add(lblPresets);

            Button btnPreRu = CreateSmallButton("🇷🇺 РФ", 135, y, 75);
            btnPreRu.Click += (s, e) => AddPresetRules(new string[] { "*.ru", "*.рф", "*.xn--p1ai", "*.su" });
            pnlBox.Controls.Add(btnPreRu);

            Button btnPreDev = CreateSmallButton("📦 Пакеты (npm/pypi/git)", 218, y, 175);
            btnPreDev.Click += (s, e) => AddPresetRules(new string[] {
                "github.com", "*.github.com", "raw.githubusercontent.com", "objects.githubusercontent.com",
                "gitlab.com", "*.gitlab.com", "bitbucket.org", "*.bitbucket.org", "npmjs.org", "*.npmjs.org",
                "registry.npmjs.org", "yarnpkg.com", "*.yarnpkg.com", "pypi.org", "*.pypi.org",
                "pythonhosted.org", "*.pythonhosted.org", "files.pythonhosted.org", "crates.io", "*.crates.io",
                "pkg.go.dev", "proxy.golang.org", "rubygems.org", "*.rubygems.org", "packagist.org", "*.packagist.org",
                "docker.io", "*.docker.io", "docker.com", "*.docker.com"
            });
            pnlBox.Controls.Add(btnPreDev);

            Button btnPreLan = CreateSmallButton("🏠 LAN / Local", 401, y, 110);
            btnPreLan.Click += (s, e) => AddPresetRules(new string[] { "localhost", "127.0.0.1", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "*.local" });
            pnlBox.Controls.Add(btnPreLan);

            Button btnPreReset = CreateSmallButton("↺ Сброс", 519, y, 90);
            btnPreReset.Click += (s, e) =>
            {
                if (MessageBox.Show("Восстановить стандартный набор исключений разработчика?", "Сброс исключений", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    bypassList = DEFAULT_BYPASS;
                    PopulateBypassControls();
                }
            };
            pnlBox.Controls.Add(btnPreReset);
            y += 36;

            // 4. Autostart Checkboxes
            chkTaskAutostart = new CheckBox
            {
                Text = "Автозапуск службы прокси-моста при старте Windows (Планировщик задач SYSTEM)",
                Location = new Point(25, y),
                Size = new Size(670, 24),
                ForeColor = TextWhite,
                Font = new Font("Segoe UI", 9f),
                Checked = CheckTaskSchedulerRegistered()
            };
            pnlBox.Controls.Add(chkTaskAutostart);
            y += 28;

            chkTrayAutostart = new CheckBox
            {
                Text = "Запускать значок Claude Proxy Manager в трее при входе пользователя",
                Location = new Point(25, y),
                Size = new Size(670, 24),
                ForeColor = TextWhite,
                Font = new Font("Segoe UI", 9f),
                Checked = CheckTrayAutostartRegistered()
            };
            pnlBox.Controls.Add(chkTrayAutostart);
            y += 38;

            // 5. Action Buttons
            btnSaveSettings = CreateActionButton("💾 Сохранить и применить настройки", AccentCyan, Color.FromArgb(17, 17, 27), 25, y, 310);
            btnSaveSettings.Click += (s, e) => SaveAndApplySettings();
            pnlBox.Controls.Add(btnSaveSettings);

            btnCreateShortcut = CreateActionButton("📌 Создать ярлык на рабочем столе", Color.FromArgb(49, 50, 68), TextWhite, 350, y, 290);
            btnCreateShortcut.Click += (s, e) =>
            {
                CreateOrUpdateDesktopShortcut();
                MessageBox.Show("Ярлык 'Claude Proxy Manager' успешно создан на вашем рабочем столе!", "Ярлык создан", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };
            pnlBox.Controls.Add(btnCreateShortcut);

            // Initial populate of bypass list
            PopulateBypassControls();
        }

        Button CreateSmallButton(string text, int x, int y, int w)
        {
            Button btn = new Button
            {
                Text = text,
                Location = new Point(x, y),
                Size = new Size(w, 26),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(40, 40, 60),
                ForeColor = TextWhite,
                Font = new Font("Segoe UI", 8f),
                Cursor = Cursors.Hand
            };
            btn.FlatAppearance.BorderSize = 0;
            return btn;
        }

        void PopulateBypassControls()
        {
            if (lstBypass == null) return;
            lstBypass.BeginUpdate();
            lstBypass.Items.Clear();
            string[] items = bypassList.Split(new char[] { ',', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string raw in items)
            {
                string rule = raw.Trim().ToLowerInvariant();
                if (!string.IsNullOrEmpty(rule) && !lstBypass.Items.Contains(rule))
                {
                    lstBypass.Items.Add(rule);
                }
            }
            lstBypass.EndUpdate();

            if (txtBypass != null)
            {
                StringBuilder sb = new StringBuilder();
                foreach (var it in lstBypass.Items) sb.AppendLine(it.ToString());
                txtBypass.Text = sb.ToString();
            }

            if (lblBypassHeader != null)
            {
                lblBypassHeader.Text = string.Format("Исключения прокси (Bypass Domains) — {0} правил в списке:", lstBypass.Items.Count);
            }
        }

        void AddSingleBypassRule()
        {
            if (txtNewRule == null || lstBypass == null) return;
            string raw = txtNewRule.Text.Trim();
            if (string.IsNullOrEmpty(raw)) return;

            if (raw.StartsWith("http://", StringComparison.OrdinalIgnoreCase)) raw = raw.Substring(7);
            if (raw.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) raw = raw.Substring(8);
            if (raw.Contains("/")) raw = raw.Substring(0, raw.IndexOf('/'));
            if (raw.Contains(":")) raw = raw.Substring(0, raw.IndexOf(':'));
            string rule = raw.Trim().ToLowerInvariant();

            if (string.IsNullOrEmpty(rule)) return;

            if (!lstBypass.Items.Contains(rule))
            {
                lstBypass.Items.Add(rule);
                txtNewRule.Clear();
                lstBypass.SelectedIndex = lstBypass.Items.Count - 1;
                lblBypassHeader.Text = string.Format("Исключения прокси (Bypass Domains) — {0} правил в списке:", lstBypass.Items.Count);
            }
            else
            {
                lstBypass.SelectedItem = rule;
                MessageBox.Show("Правило '" + rule + "' уже присутствует в списке исключений.", "Информация", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        void DeleteSelectedBypassRules()
        {
            if (lstBypass == null || lstBypass.SelectedItems.Count == 0)
            {
                MessageBox.Show("Выберите одно или несколько правил из списка для удаления.", "Удаление", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            List<object> toRemove = new List<object>();
            foreach (var item in lstBypass.SelectedItems) toRemove.Add(item);
            foreach (var item in toRemove) lstBypass.Items.Remove(item);

            lblBypassHeader.Text = string.Format("Исключения прокси (Bypass Domains) — {0} правил в списке:", lstBypass.Items.Count);
        }

        void AddPresetRules(string[] presetRules)
        {
            if (lstBypass == null) return;
            int added = 0;
            lstBypass.BeginUpdate();
            foreach (string r in presetRules)
            {
                string rule = r.Trim().ToLowerInvariant();
                if (!string.IsNullOrEmpty(rule) && !lstBypass.Items.Contains(rule))
                {
                    lstBypass.Items.Add(rule);
                    added++;
                }
            }
            lstBypass.EndUpdate();
            lblBypassHeader.Text = string.Format("Исключения прокси (Bypass Domains) — {0} правил в списке:", lstBypass.Items.Count);
            if (added > 0)
            {
                MessageBox.Show("Добавлено новых правил: " + added, "Набор применен", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show("Все правила из этого набора уже присутствуют в списке.", "Информация", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        void ToggleBypassEditMode()
        {
            bypassTextMode = !bypassTextMode;
            if (bypassTextMode)
            {
                // Switch to text mode
                StringBuilder sb = new StringBuilder();
                foreach (var it in lstBypass.Items) sb.AppendLine(it.ToString());
                txtBypass.Text = sb.ToString();

                lstBypass.Visible = false;
                txtBypass.Visible = true;
                txtNewRule.Visible = false;
                btnAddRule.Visible = false;
                btnDeleteRule.Visible = false;
                btnToggleBypassMode.Text = "📋 Режим списка";
            }
            else
            {
                // Switch to list mode
                lstBypass.BeginUpdate();
                lstBypass.Items.Clear();
                string[] lines = txtBypass.Text.Split(new char[] { '\r', '\n', ',' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (string line in lines)
                {
                    string rule = line.Trim().ToLowerInvariant();
                    if (!string.IsNullOrEmpty(rule) && !lstBypass.Items.Contains(rule))
                    {
                        lstBypass.Items.Add(rule);
                    }
                }
                lstBypass.EndUpdate();

                txtBypass.Visible = false;
                lstBypass.Visible = true;
                txtNewRule.Visible = true;
                btnAddRule.Visible = true;
                btnDeleteRule.Visible = true;
                btnToggleBypassMode.Text = "📝 Режим текста";
                lblBypassHeader.Text = string.Format("Исключения прокси (Bypass Domains) — {0} правил в списке:", lstBypass.Items.Count);
            }
        }

        void BuildLogs(Panel parent)
        {
            Panel pnlLogBox = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = CardDark,
                Padding = new Padding(15)
            };
            parent.Controls.Add(pnlLogBox);

            Panel pnlLogHeader = new Panel { Dock = DockStyle.Top, Height = 40, BackColor = CardDark };
            pnlLogBox.Controls.Add(pnlLogHeader);

            Label lblL = new Label { Text = "Журнал работы GOST:", ForeColor = TextWhite, Font = new Font("Segoe UI", 9.5f, FontStyle.Bold), Location = new Point(5, 8), AutoSize = true };
            pnlLogHeader.Controls.Add(lblL);

            Button btnRefreshLog = new Button
            {
                Text = "Обновить лог",
                Location = new Point(200, 5),
                Size = new Size(110, 28),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(49, 50, 68),
                ForeColor = TextWhite,
                Font = new Font("Segoe UI", 8.5f),
                Cursor = Cursors.Hand
            };
            btnRefreshLog.FlatAppearance.BorderSize = 0;
            btnRefreshLog.Click += (s, e) => LoadLogs();
            pnlLogHeader.Controls.Add(btnRefreshLog);

            txtLogs = new TextBox
            {
                Dock = DockStyle.Fill,
                Multiline = true,
                ReadOnly = true,
                BackColor = CardDarker,
                ForeColor = Color.FromArgb(180, 190, 210),
                Font = new Font("Consolas", 9f),
                BorderStyle = BorderStyle.FixedSingle,
                ScrollBars = ScrollBars.Both,
                WordWrap = false
            };
            pnlLogBox.Controls.Add(txtLogs);
            txtLogs.BringToFront();
        }

        void SetupTray()
        {
            trayMenu = new ContextMenuStrip();
            trayMenu.BackColor = CardDark;
            trayMenu.ForeColor = TextWhite;
            trayMenu.Font = new Font("Segoe UI", 9f);
            trayMenu.ShowImageMargin = false;

            ToolStripMenuItem mOpen = new ToolStripMenuItem("📊 Открыть панель управления");
            mOpen.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
            mOpen.ForeColor = AccentCyan;
            mOpen.Click += (s, e) => ShowAndRestore();

            ToolStripMenuItem mToggle = new ToolStripMenuItem("▶ Запустить / Перезапустить мост");
            mToggle.Click += (s, e) => ToggleProxyBridge();

            ToolStripMenuItem mRepatch = new ToolStripMenuItem("⚡ Перепатчить VS Code & CLI");
            mRepatch.Click += (s, e) => ExecuteRepatch();

            ToolStripMenuItem mTestLocal = new ToolStripMenuItem("🌐 Тест локального моста (127.0.0.1)");
            mTestLocal.Click += (s, e) => TestLocalProxyBridge();

            ToolStripMenuItem mTestSocks5 = new ToolStripMenuItem("🔒 Тест внешнего SOCKS5");
            mTestSocks5.Click += (s, e) => TestUpstreamSocks5Direct();

            ToolStripMenuItem mClaude = new ToolStripMenuItem("🚀 Запустить Claude Desktop");
            mClaude.Click += (s, e) => LaunchClaudeDesktop();

            ToolStripMenuItem mExit = new ToolStripMenuItem("❌ Полный выход");
            mExit.Click += (s, e) =>
            {
                if (trayIcon != null) trayIcon.Visible = false;
                Application.Exit();
            };

            trayMenu.Items.Add(mOpen);
            trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add(mToggle);
            trayMenu.Items.Add(mRepatch);
            trayMenu.Items.Add(mTestLocal);
            trayMenu.Items.Add(mTestSocks5);
            trayMenu.Items.Add(mClaude);
            trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add(mExit);

            trayIcon = new NotifyIcon
            {
                Text = "Claude Proxy Manager",
                ContextMenuStrip = trayMenu,
                Visible = true
            };
            trayIcon.Icon = CreateAppIcon(GreenActive);
            trayIcon.DoubleClick += (s, e) => ShowAndRestore();
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (isInitialStartMinimized)
            {
                this.Hide();
            }
        }

        void ShowAndRestore()
        {
            this.Show();
            if (this.WindowState == FormWindowState.Minimized)
            {
                this.WindowState = FormWindowState.Normal;
            }
            this.BringToFront();
            this.Activate();
        }

        // Status Polling and Diagnostics
        void RefreshStatus()
        {
            ThreadPool.QueueUserWorkItem(_ =>
            {
                bool portActive = CheckPortListening(proxyPort);

                Process[] gosts = Process.GetProcessesByName("gost");
                bool gostRunning = gosts.Length > 0;
                long gostMemMb = 0;
                int gostPid = 0;
                bool isSessionZero = false;
                if (gostRunning)
                {
                    try
                    {
                        gostMemMb = gosts[0].WorkingSet64 / (1024 * 1024);
                        gostPid = gosts[0].Id;
                        isSessionZero = (gosts[0].SessionId == 0);
                    }
                    catch { }
                }

                bool taskRegistered = CheckTaskSchedulerRegistered() || isSessionZero;
                bool vsCodePatched = CheckVsCodeExtensionPatched();
                bool cliInstalled = CheckCliInstalled();
                bool guiConfigured = CheckGuiProxyConfigured();

                // Marshal back to UI thread
                try
                {
                    this.BeginInvoke(new Action(() =>
                    {
                        // Update Header Status Pill
                        if (portActive && gostRunning)
                        {
                            lblPillText.Text = "● МОСТ АКТИВЕН";
                            lblPillText.ForeColor = GreenActive;
                            btnToggleProxy.Text = "Остановить мост";
                            btnToggleProxy.BackColor = RedStopped;
                            if (trayIcon != null)
                            {
                                trayIcon.Icon = CreateAppIcon(GreenActive);
                                trayIcon.Text = string.Format("Claude Proxy: Активен (127.0.0.1:{0})", proxyPort);
                            }
                        }
                        else
                        {
                            lblPillText.Text = "○ МОСТ ОСТАНОВЛЕН";
                            lblPillText.ForeColor = RedStopped;
                            btnToggleProxy.Text = "Запустить мост";
                            btnToggleProxy.BackColor = AccentCyan;
                            if (trayIcon != null)
                            {
                                trayIcon.Icon = CreateAppIcon(RedStopped);
                                trayIcon.Text = string.Format("Claude Proxy: Остановлен (127.0.0.1:{0})", proxyPort);
                            }
                        }

                        // Card 1: GOST
                        if (gostRunning)
                        {
                            lblGostStatus.Text = string.Format("PID: {0} | Память: ~{1} МБ | {2}", gostPid, gostMemMb, isSessionZero ? "Служба (Session 0)" : "В работе");
                            badgeGost.Text = "АКТИВЕН";
                            badgeGost.ForeColor = GreenActive;
                        }
                        else
                        {
                            lblGostStatus.Text = "Процесс gost.exe не запущен";
                            badgeGost.Text = "ОСТАНОВЛЕН";
                            badgeGost.ForeColor = RedStopped;
                        }

                        // Card 2: Port
                        if (portActive)
                        {
                            lblPortStatus.Text = string.Format("127.0.0.1:{0} слушает входящие соединения", proxyPort);
                            badgePort.Text = "СЛУШАЕТ";
                            badgePort.ForeColor = GreenActive;
                        }
                        else
                        {
                            lblPortStatus.Text = string.Format("Порт {0} не отвечает (нет листенера)", proxyPort);
                            badgePort.Text = "НЕДОСТУПЕН";
                            badgePort.ForeColor = RedStopped;
                        }

                        // Card 3: Task Scheduler
                        if (taskRegistered)
                        {
                            lblTaskStatus.Text = "Задача ClaudeProxy_" + currentUser + " зарегистрирована (SYSTEM)";
                            badgeTask.Text = "АКТИВЕН";
                            badgeTask.ForeColor = GreenActive;
                        }
                        else
                        {
                            lblTaskStatus.Text = "Задача ClaudeProxy_" + currentUser + " не найдена";
                            badgeTask.Text = "НЕ АКТИВЕН";
                            badgeTask.ForeColor = AmberWarn;
                        }

                        // Card 4: VS Code
                        if (vsCodePatched)
                        {
                            lblVsCodeStatus.Text = "Враппер claude.exe активен, бинарники синхронизированы";
                            badgeVsCode.Text = "ПРОПАТЧЕН";
                            badgeVsCode.ForeColor = GreenActive;
                        }
                        else
                        {
                            lblVsCodeStatus.Text = "Требуется синхронизация бинарников или обновление";
                            badgeVsCode.Text = "ТРЕБУЕТСЯ ПАТЧ";
                            badgeVsCode.ForeColor = AmberWarn;
                        }

                        // Card 5: Standalone CLI
                        if (cliInstalled)
                        {
                            lblCliStatus.Text = "Бинарник claude.exe найден в профиле пользователя";
                            badgeCli.Text = "УСТАНОВЛЕН";
                            badgeCli.ForeColor = GreenActive;
                        }
                        else
                        {
                            lblCliStatus.Text = "Официальный CLI не обнаружен в .local\\bin";
                            badgeCli.Text = "ОТСУТСТВУЕТ";
                            badgeCli.ForeColor = AmberWarn;
                        }

                        // Card 6: GUI
                        if (guiConfigured)
                        {
                            lblGuiStatus.Text = "WinINet прокси настроен, LoopbackExempt активен";
                            badgeGui.Text = "ГОТОВ";
                            badgeGui.ForeColor = GreenActive;
                        }
                        else
                        {
                            lblGuiStatus.Text = "Системный прокси не указывает на 127.0.0.1:" + proxyPort;
                            badgeGui.Text = "НЕ НАСТРОЕН";
                            badgeGui.ForeColor = AmberWarn;
                        }
                    }));
                }
                catch { }
            });
        }

        bool CheckPortListening(int port)
        {
            try
            {
                using (TcpClient client = new TcpClient())
                {
                    IAsyncResult res = client.BeginConnect("127.0.0.1", port, null, null);
                    bool success = res.AsyncWaitHandle.WaitOne(300);
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

        bool IsPortAvailable(int port)
        {
            TcpListener tcp = null;
            try
            {
                tcp = new TcpListener(IPAddress.Loopback, port);
                tcp.Start();
                tcp.Stop();
                return true;
            }
            catch
            {
                return false;
            }
            finally
            {
                if (tcp != null)
                {
                    try { tcp.Stop(); } catch { }
                }
            }
        }

        bool CheckTaskSchedulerRegistered()
        {
            // 1. If any gost.exe is running in Session 0 (SessionId == 0), it is definitely running via Scheduled Task (SYSTEM)
            try
            {
                Process[] procs = Process.GetProcessesByName("gost");
                foreach (Process p in procs)
                {
                    if (p.SessionId == 0) return true;
                }
            }
            catch { }

            // 2. Direct filesystem check for Windows Task XML file (supports 32-bit/64-bit and WOW64)
            try
            {
                string windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                string[] candidates = new string[] {
                    Path.Combine(windir, "System32", "Tasks", "ClaudeProxy_" + currentUser),
                    Path.Combine(windir, "Sysnative", "Tasks", "ClaudeProxy_" + currentUser),
                    Path.Combine(windir, "System32", "Tasks", "ClaudeProxy_" + Environment.UserName),
                    Path.Combine(windir, "Sysnative", "Tasks", "ClaudeProxy_" + Environment.UserName)
                };
                foreach (string path in candidates)
                {
                    if (File.Exists(path)) return true;
                }
            }
            catch { }

            // 3. Command line query via schtasks.exe
            // When standard user queries a SYSTEM task, schtasks produces "Access is denied" / "Отказано в доступе".
            // A non-existent task produces "The system cannot find the file specified".
            // Therefore, "Access is denied" proves that the task EXISTS!
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("schtasks.exe", string.Format("/query /tn \"ClaudeProxy_{0}\"", currentUser))
                {
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (Process p = Process.Start(psi))
                {
                    if (p != null)
                    {
                        string outStr = p.StandardOutput.ReadToEnd();
                        string errStr = p.StandardError.ReadToEnd();
                        p.WaitForExit(3000);

                        if (p.ExitCode == 0) return true;

                        string combined = (outStr + " " + errStr).ToLowerInvariant();
                        if (combined.Contains("access is denied") || 
                            combined.Contains("отказано в доступе") ||
                            combined.Contains("denied") ||
                            combined.Contains("доступ"))
                        {
                            return true;
                        }
                    }
                }
            }
            catch { }

            // 4. Check runner script in ProgramData (only created by setup during task registration)
            try
            {
                string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
                string runCmd = Path.Combine(programData, "claude-proxy", "bin", "run_" + currentUser + ".cmd");
                if (File.Exists(runCmd)) return true;
            }
            catch { }

            // 5. Check proxy.env flag
            try
            {
                if (File.Exists(proxyEnvFile))
                {
                    string[] lines = File.ReadAllLines(proxyEnvFile);
                    foreach (string l in lines)
                    {
                        if (l.StartsWith("TASK_AUTOSTART="))
                        {
                            string val = l.Substring(15).Trim().Trim('"');
                            if (val.Equals("true", StringComparison.OrdinalIgnoreCase)) return true;
                        }
                    }
                }
            }
            catch { }

            return false;
        }

        bool CheckTrayAutostartRegistered()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", false))
                {
                    if (key != null)
                    {
                        return key.GetValue("ClaudeProxyManager") != null;
                    }
                }
            }
            catch { }
            return false;
        }

        bool CheckVsCodeExtensionPatched()
        {
            try
            {
                string extRoot = Path.Combine(userProfile, ".vscode", "extensions");
                if (!Directory.Exists(extRoot)) return true;

                string[] dirs = Directory.GetDirectories(extRoot, "anthropic.claude-code-*");
                if (dirs.Length == 0) return true;

                foreach (string d in dirs)
                {
                    string b1 = Path.Combine(d, "resources", "native-binary", "claude.exe");
                    string b2 = Path.Combine(d, "resources", "native-binaries", "win32-x64", "claude.exe");
                    if (!File.Exists(b1) && !File.Exists(b2)) return false;
                }
                return true;
            }
            catch { return true; }
        }

        bool CheckCliInstalled()
        {
            string p1 = Path.Combine(userProfile, ".local", "bin", "claude.exe");
            string p2 = Path.Combine(userProfile, ".local", "bin", "claude.real.exe");
            return File.Exists(p1) || File.Exists(p2);
        }

        bool CheckGuiProxyConfigured()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings", false))
                {
                    if (key != null)
                    {
                        object val = key.GetValue("ProxyEnable");
                        object server = key.GetValue("ProxyServer");
                        if (val != null && Convert.ToInt32(val) == 1 && server != null && server.ToString().Contains(proxyPort.ToString()))
                        {
                            return true;
                        }
                    }
                }
            }
            catch { }
            return false;
        }

        // Actions
        void ToggleProxyBridge()
        {
            bool portActive = CheckPortListening(proxyPort);
            if (portActive)
            {
                // Stop proxy
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    try
                    {
                        ProcessStartInfo psi = new ProcessStartInfo("taskkill.exe", "/f /im gost.exe")
                        {
                            CreateNoWindow = true,
                            UseShellExecute = false
                        };
                        Process p = Process.Start(psi);
                        if (p != null) p.WaitForExit(2000);
                    }
                    catch { }
                    RefreshStatus();
                });
            }
            else
            {
                // Start proxy
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    try
                    {
                        string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
                        string runner = Path.Combine(programData, "claude-proxy", "bin", "run_" + currentUser + ".cmd");
                        if (File.Exists(runner))
                        {
                            ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c \"" + runner + "\"")
                            {
                                CreateNoWindow = true,
                                UseShellExecute = false,
                                WindowStyle = ProcessWindowStyle.Hidden
                            };
                            Process.Start(psi);
                        }
                    }
                    catch { }
                    Thread.Sleep(1000);
                    RefreshStatus();
                });
            }
        }

        void ExecuteRepatch()
        {
            btnRepatch.Enabled = false;
            btnRepatch.Text = "Патчинг...";

            ThreadPool.QueueUserWorkItem(_ =>
            {
                try
                {
                    // Run setup.exe --patch if available
                    string appDir = AppDomain.CurrentDomain.BaseDirectory;
                    string setupExe = Path.Combine(appDir, "setup.exe");
                    if (!File.Exists(setupExe)) setupExe = Path.Combine(userBinDir, "setup.exe");

                    if (File.Exists(setupExe))
                    {
                        ProcessStartInfo psi = new ProcessStartInfo(setupExe, "--patch")
                        {
                            CreateNoWindow = true,
                            UseShellExecute = false
                        };
                        using (Process p = Process.Start(psi))
                        {
                            if (p != null) p.WaitForExit(15000);
                        }
                    }
                    else
                    {
                        // Fallback to internal quick patch logic
                        QuickPatchInternal();
                    }
                }
                catch (Exception ex)
                {
                    this.BeginInvoke(new Action(() =>
                    {
                        MessageBox.Show("Ошибка при выполнении патчинга: " + ex.Message, "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }));
                }

                Thread.Sleep(800);
                this.BeginInvoke(new Action(() =>
                {
                    btnRepatch.Enabled = true;
                    btnRepatch.Text = "⚡ Перепатчить всё";
                    RefreshStatus();
                    if (trayIcon != null)
                    {
                        trayIcon.ShowBalloonTip(3000, "Claude Proxy Manager", "Синхронизация бинарников успешно завершена!", ToolTipIcon.Info);
                    }
                }));
            });
        }

        void QuickPatchInternal()
        {
            string extRoot = Path.Combine(userProfile, ".vscode", "extensions");
            string localReal = Path.Combine(userProfile, ".local", "bin", "claude.real.exe");
            if (!File.Exists(localReal)) localReal = Path.Combine(userProfile, ".local", "bin", "claude.exe");
            string wrapper = Path.Combine(userBinDir, "claude_wrapper.exe");

            if (File.Exists(localReal) && Directory.Exists(extRoot))
            {
                foreach (string d in Directory.GetDirectories(extRoot, "anthropic.claude-code-*"))
                {
                    string targetDir = Path.Combine(d, "resources", "native-binaries", "win32-x64");
                    try
                    {
                        Directory.CreateDirectory(targetDir);
                        string realDst = Path.Combine(targetDir, "claude.real.exe");
                        string wrapDst = Path.Combine(targetDir, "claude.exe");
                        File.Copy(localReal, realDst, true);
                        if (File.Exists(wrapper)) File.Copy(wrapper, wrapDst, true);
                    }
                    catch { }
                }
            }
        }

        // Test 1: Local HTTP Bridge (via GOST 127.0.0.1:port)
        void TestLocalProxyBridge()
        {
            btnTestLocal.Enabled = false;
            btnTestLocal.Text = "Проверка...";

            ThreadPool.QueueUserWorkItem(_ =>
            {
                string resultMessage = "";
                bool isSuccess = false;
                string detectedIp = "";
                string successUrl = "";
                string lastError = "";

                try
                {
                    ServicePointManager.SecurityProtocol = (SecurityProtocolType)12288 | (SecurityProtocolType)3072 | (SecurityProtocolType)768 | SecurityProtocolType.Tls;
                    ServicePointManager.ServerCertificateValidationCallback = (sender, cert, chain, sslErrors) => true;
                }
                catch { }

                // List of endpoints to verify proxy connectivity:
                // Plain HTTP endpoints first (fastest, no TLS handshake overhead, 100% proxy compatibility),
                // followed by HTTPS endpoints with modern TLS 1.2/1.3.
                string[] endpoints = new string[]
                {
                    "http://2ip.io",
                    "http://api.ipify.org",
                    "http://ifconfig.me/ip",
                    "http://icanhazip.com",
                    "https://api.ipify.org?format=text",
                    "https://ifconfig.me/ip"
                };

                foreach (string url in endpoints)
                {
                    try
                    {
                        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
                        req.Proxy = new WebProxy("127.0.0.1", proxyPort);
                        req.Timeout = 5000;
                        req.ReadWriteTimeout = 5000;
                        req.UserAgent = "curl/8.0";
                        req.KeepAlive = false;

                        using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                        using (StreamReader sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                        {
                            string body = sr.ReadToEnd().Trim();
                            // Match IPv4 or IPv6 pattern
                            Match m = Regex.Match(body, @"\b(?:\d{1,3}\.){3}\d{1,3}\b|(?:[0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}");
                            if (m.Success)
                            {
                                detectedIp = m.Value;
                                successUrl = url;
                                isSuccess = true;
                                break;
                            }
                            else if (!string.IsNullOrEmpty(body) && body.Length < 60 && !body.Contains("<") && !body.Contains(">"))
                            {
                                detectedIp = body;
                                successUrl = url;
                                isSuccess = true;
                                break;
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        lastError = ex.Message;
                    }
                }

                if (isSuccess)
                {
                    resultMessage = string.Format(
                        "Локальный HTTP-мост работает отлично!\n\n" +
                        "Локальный порт: 127.0.0.1:{0}\n" +
                        "Внешний IP-адрес выхода: {1}\n" +
                        "Проверенный сервис: {2}\n\n" +
                        "Все запросы Claude успешно маршрутизируются через прокси.",
                        proxyPort, detectedIp, successUrl);
                }
                else
                {
                    resultMessage = string.Format(
                        "Не удалось получить ответ через локальный мост (127.0.0.1:{0}):\n{1}\n\n" +
                        "Убедитесь, что процесс gost.exe запущен и upstream SOCKS5 доступен.",
                        proxyPort, lastError);
                }

                this.BeginInvoke(new Action(() =>
                {
                    btnTestLocal.Enabled = true;
                    btnTestLocal.Text = "🌐 Тест локального моста (127.0.0.1)";
                    MessageBox.Show(resultMessage, isSuccess ? "Локальный мост активен" : "Ошибка локального моста",
                        MessageBoxButtons.OK, isSuccess ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
                }));
            });
        }

        // Test 2: Direct Upstream SOCKS5 Handshake (bypassing local GOST)
        void TestUpstreamSocks5Direct()
        {
            btnTestSocks5.Enabled = false;
            btnTestSocks5.Text = "Проверка...";

            ThreadPool.QueueUserWorkItem(_ =>
            {
                string resultMessage;
                bool isSuccess = TestDirectSocks5Handshake(socks5Url, out resultMessage);

                this.BeginInvoke(new Action(() =>
                {
                    btnTestSocks5.Enabled = true;
                    btnTestSocks5.Text = "🔒 Тест внешнего SOCKS5 (Прямой)";
                    MessageBox.Show(resultMessage, isSuccess ? "Внешний SOCKS5 доступен" : "Ошибка внешнего SOCKS5",
                        MessageBoxButtons.OK, isSuccess ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
                }));
            });
        }

        // Direct SOCKS5 Handshake implementation (RFC 1928 & RFC 1929)
        bool TestDirectSocks5Handshake(string rawUrl, out string message)
        {
            try
            {
                if (string.IsNullOrEmpty(rawUrl))
                {
                    message = "SOCKS5 URL не указан в конфигурации!";
                    return false;
                }

                string raw = rawUrl.Trim();
                if (raw.Contains("://")) raw = raw.Substring(raw.IndexOf("://") + 3);

                string user = "", pass = "", host = "";
                int port = 1080;

                if (raw.Contains("@"))
                {
                    int at = raw.IndexOf('@');
                    string creds = raw.Substring(0, at);
                    raw = raw.Substring(at + 1);
                    if (creds.Contains(":"))
                    {
                        int c = creds.IndexOf(':');
                        user = creds.Substring(0, c);
                        pass = creds.Substring(c + 1);
                    }
                    else user = creds;
                }

                if (raw.Contains(":"))
                {
                    int c = raw.LastIndexOf(':');
                    host = raw.Substring(0, c);
                    int.TryParse(raw.Substring(c + 1).TrimEnd('/'), out port);
                }
                else host = raw.TrimEnd('/');

                if (string.IsNullOrEmpty(host) || port <= 0)
                {
                    message = "Некорректный формат SOCKS5 URL. Ожидается:\nsocks5://USER:PASSWORD@HOST:PORT";
                    return false;
                }

                using (TcpClient tcp = new TcpClient())
                {
                    IAsyncResult ar = tcp.BeginConnect(host, port, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(4500))
                    {
                        message = string.Format("Не удалось подключиться к серверу {0}:{1} (Тайм-аут 4.5 сек).\nПроверьте доступность хоста и фаервол.", host, port);
                        return false;
                    }
                    tcp.EndConnect(ar);
                    tcp.SendTimeout = 4000;
                    tcp.ReceiveTimeout = 4000;

                    NetworkStream stream = tcp.GetStream();

                    // 1. Send Handshake greeting (RFC 1928)
                    if (!string.IsNullOrEmpty(user))
                    {
                        // Offer No Auth (0x00) and Username/Password (0x02)
                        stream.Write(new byte[] { 0x05, 0x02, 0x00, 0x02 }, 0, 4);
                    }
                    else
                    {
                        stream.Write(new byte[] { 0x05, 0x01, 0x00 }, 0, 3);
                    }

                    byte[] resp = new byte[2];
                    int read = stream.Read(resp, 0, 2);
                    if (read < 2 || resp[0] != 0x05)
                    {
                        message = string.Format("Сервер {0}:{1} ответил не по протоколу SOCKS5 (байт: 0x{2:X2}).", host, port, resp[0]);
                        return false;
                    }

                    if (resp[1] == 0xFF)
                    {
                        message = "Сервер SOCKS5 отклонил поддерживаемые методы аутентификации (0xFF).";
                        return false;
                    }

                    // 2. Authentication subnegotiation if required (RFC 1929)
                    if (resp[1] == 0x02)
                    {
                        byte[] uBytes = Encoding.UTF8.GetBytes(user);
                        byte[] pBytes = Encoding.UTF8.GetBytes(pass);
                        byte[] authReq = new byte[3 + uBytes.Length + pBytes.Length];
                        authReq[0] = 0x01; // Subnegotiation version 1
                        authReq[1] = (byte)uBytes.Length;
                        Buffer.BlockCopy(uBytes, 0, authReq, 2, uBytes.Length);
                        authReq[2 + uBytes.Length] = (byte)pBytes.Length;
                        Buffer.BlockCopy(pBytes, 0, authReq, 3 + uBytes.Length, pBytes.Length);

                        stream.Write(authReq, 0, authReq.Length);

                        byte[] authResp = new byte[2];
                        read = stream.Read(authResp, 0, 2);
                        if (read < 2 || authResp[1] != 0x00)
                        {
                            message = string.Format("Ошибка авторизации на SOCKS5 сервере {0}:{1} (Неверный логин или пароль).", host, port);
                            return false;
                        }
                    }

                    message = string.Format("Прямое подключение к SOCKS5 успешно!\n\nСервер: {0}:{1}\nАвторизация: {2}\nСтатус: SOCKS5 рукопожатие завершено, сервер готов к работе.",
                        host, port, string.IsNullOrEmpty(user) ? "Без пароля" : "Пройдена (" + user + ")");
                    return true;
                }
            }
            catch (Exception ex)
            {
                message = "Ошибка прямого подключения к SOCKS5:\n" + ex.Message;
                return false;
            }
        }

        void LaunchClaudeDesktop()
        {
            ThreadPool.QueueUserWorkItem(_ =>
            {
                try
                {
                    // Look for UWP / MSIX package
                    ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c start shell:AppsFolder\\Claude_pzs8sxrjxfjjc!Claude")
                    {
                        CreateNoWindow = true,
                        UseShellExecute = false
                    };
                    Process.Start(psi);
                }
                catch
                {
                    try
                    {
                        // Fallback Win32
                        string pf = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                        string claudeExe = Path.Combine(pf, "Programs", "Claude", "Claude.exe");
                        if (File.Exists(claudeExe))
                        {
                            Process.Start(claudeExe, "--proxy-server=\"http://127.0.0.1:" + proxyPort + "\"");
                        }
                    }
                    catch { }
                }
            });
        }

        void SaveAndApplySettings()
        {
            string newSocks5 = txtSocks5Url.Text.Trim();
            if (string.IsNullOrEmpty(newSocks5))
            {
                MessageBox.Show("Укажите адрес SOCKS5 прокси!", "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (!newSocks5.Contains("://"))
            {
                newSocks5 = "socks5://" + newSocks5;
            }

            int newPort;
            if (!int.TryParse(txtPort.Text.Trim(), out newPort) || newPort <= 0 || newPort > 65535)
            {
                MessageBox.Show("Некорректный номер порта! Укажите число от 1 до 65535.", "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Verify requested port is free if port changed
            if (newPort != proxyPort && !IsPortAvailable(newPort))
            {
                MessageBox.Show(
                    string.Format("Локальный порт {0} уже занят другим приложением в системе!\n\nПожалуйста, укажите другой свободный порт.", newPort),
                    "Порт занят", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Collect bypass rules
            List<string> rules = new List<string>();
            if (bypassTextMode && txtBypass != null)
            {
                string[] lines = txtBypass.Text.Split(new char[] { '\r', '\n', ',' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (string line in lines)
                {
                    string trimmed = line.Trim().ToLowerInvariant();
                    if (!string.IsNullOrEmpty(trimmed) && !rules.Contains(trimmed))
                        rules.Add(trimmed);
                }
            }
            else if (lstBypass != null)
            {
                foreach (var item in lstBypass.Items)
                {
                    string rule = item.ToString().Trim().ToLowerInvariant();
                    if (!string.IsNullOrEmpty(rule) && !rules.Contains(rule))
                        rules.Add(rule);
                }
            }
            if (rules.Count == 0)
            {
                rules.AddRange(new string[] { "localhost", "127.0.0.1", "::1", "*.ru", "*.xn--p1ai", "*.su" });
            }
            bypassList = string.Join(",", rules.ToArray());

            socks5Url = newSocks5;
            proxyPort = newPort;

            // 1. Save config files in user profile
            SaveConfig();

            // 2. Update run_<user>.cmd runner script in both ProgramData and user bin dir
            string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            string binDir = Path.Combine(programData, "claude-proxy", "bin");
            Directory.CreateDirectory(binDir);
            string gostExe = Path.Combine(binDir, "gost.exe");
            if (!File.Exists(gostExe)) gostExe = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "gost.exe");
            string logFile = Path.Combine(binDir, "gost_" + currentUser + ".log");
            string runCmdFile = Path.Combine(binDir, "run_" + currentUser + ".cmd");
            string userRunCmd = Path.Combine(userBinDir, "run_" + currentUser + ".cmd");

            string runCmdContent = string.Format(
                "@echo off\r\nchcp 65001 >nul\r\n\"{0}\" -L \"http://127.0.0.1:{1}\" -F \"{2}\" > \"{3}\" 2>&1\r\n",
                gostExe, proxyPort, socks5Url, logFile);
            try { File.WriteAllText(runCmdFile, runCmdContent, new UTF8Encoding(false)); } catch { }
            try { File.WriteAllText(userRunCmd, runCmdContent, new UTF8Encoding(false)); } catch { }

            // 3. Update Scheduled Task if needed
            string taskName = "ClaudeProxy_" + currentUser;
            if (chkTaskAutostart != null && chkTaskAutostart.Checked)
            {
                try
                {
                    string schArgs = string.Format("/create /tn \"{0}\" /tr \"cmd.exe /c \\\"{1}\\\"\" /sc ONSTART /ru \"SYSTEM\" /rl HIGHEST /f", taskName, runCmdFile);
                    ProcessStartInfo psi = new ProcessStartInfo("schtasks.exe", schArgs) { CreateNoWindow = true, UseShellExecute = false };
                    using (Process p = Process.Start(psi))
                    {
                        if (p != null) p.WaitForExit(3000);
                    }
                }
                catch { }
            }
            else if (chkTaskAutostart != null)
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo("schtasks.exe", string.Format("/delete /tn \"{0}\" /f", taskName)) { CreateNoWindow = true, UseShellExecute = false };
                    using (Process p = Process.Start(psi))
                    {
                        if (p != null) p.WaitForExit(3000);
                    }
                }
                catch { }
            }

            // 4. Update Tray Autostart in Registry
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (key != null)
                    {
                        string appPath = Assembly.GetExecutingAssembly().Location;
                        if (chkTrayAutostart != null && chkTrayAutostart.Checked)
                        {
                            key.SetValue("ClaudeProxyManager", "\"" + appPath + "\" --tray");
                        }
                        else
                        {
                            try { key.DeleteValue("ClaudeProxyManager", false); } catch { }
                        }
                    }
                }
            }
            catch { }

            // 5. Update WinINet Proxy Registry for Claude Desktop
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings", true))
                {
                    if (key != null)
                    {
                        key.SetValue("ProxyEnable", 1, RegistryValueKind.DWord);
                        key.SetValue("ProxyServer", string.Format("http=127.0.0.1:{0};https=127.0.0.1:{0}", proxyPort), RegistryValueKind.String);
                    }
                }
            }
            catch { }

            // 6. Refresh Desktop shortcut with icon
            CreateOrUpdateDesktopShortcut();

            // 7. Restart GOST Proxy Bridge with the new upstream SOCKS5 and port
            btnSaveSettings.Enabled = false;
            btnSaveSettings.Text = "Перезапуск моста...";

            ThreadPool.QueueUserWorkItem(_ =>
            {
                bool restartOk = false;
                try
                {
                    // Kill running gost.exe
                    ProcessStartInfo pk = new ProcessStartInfo("taskkill.exe", "/f /im gost.exe") { CreateNoWindow = true, UseShellExecute = false };
                    using (Process pKill = Process.Start(pk))
                    {
                        if (pKill != null) pKill.WaitForExit(2000);
                    }

                    Thread.Sleep(600);

                    // Launch updated runner
                    string runnerToStart = File.Exists(runCmdFile) ? runCmdFile : userRunCmd;
                    if (File.Exists(runnerToStart))
                    {
                        ProcessStartInfo pr = new ProcessStartInfo("cmd.exe", "/c \"" + runnerToStart + "\"")
                        {
                            CreateNoWindow = true,
                            UseShellExecute = false,
                            WindowStyle = ProcessWindowStyle.Hidden
                        };
                        Process.Start(pr);
                    }

                    // Poll for port listening (up to 4 seconds)
                    for (int wait = 0; wait < 10; wait++)
                    {
                        Thread.Sleep(400);
                        if (CheckPortListening(proxyPort))
                        {
                            restartOk = true;
                            break;
                        }
                    }
                }
                catch { }

                this.BeginInvoke(new Action(() =>
                {
                    btnSaveSettings.Enabled = true;
                    btnSaveSettings.Text = "💾 Сохранить и применить настройки";
                    lblSubtitle.Text = "Пользователь: " + currentUser + " | Мост: 127.0.0.1:" + proxyPort;
                    RefreshStatus();

                    if (restartOk)
                    {
                        MessageBox.Show(
                            string.Format("Настройки успешно сохранены!\n\nПрокси-мост перезапущен и активен.\nПорт: 127.0.0.1:{0}\nUpstream SOCKS5: {1}\nВсего правил исключений: {2}", proxyPort, socks5Url, rules.Count),
                            "Настройки применены", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    }
                    else
                    {
                        MessageBox.Show(
                            string.Format("Настройки сохранены в файлах конфигурации, но локальный мост не начал прослушивание на порту 127.0.0.1:{0}.\n\nПроверьте доступность SOCKS5 прокси и лог на вкладке 'Журнал работы'.", proxyPort),
                            "Внимание", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                }));
            });
        }

        void CreateOrUpdateDesktopShortcut()
        {
            try
            {
                string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
                string shortcutPath = Path.Combine(desktop, "Claude Proxy Manager.lnk");
                string appPath = Assembly.GetExecutingAssembly().Location;
                string dir = Path.GetDirectoryName(appPath);

                CreateShortcut(shortcutPath, appPath, "", "Claude Proxy Manager (Dashboard & System Tray)", dir, appPath, 0);
            }
            catch { }
        }

        void LoadLogs()
        {
            ThreadPool.QueueUserWorkItem(_ =>
            {
                string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
                string logFile = Path.Combine(programData, "claude-proxy", "bin", "gost_" + currentUser + ".log");
                string text = "";
                if (File.Exists(logFile))
                {
                    try
                    {
                        using (FileStream fs = new FileStream(logFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                        using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                        {
                            text = sr.ReadToEnd();
                        }
                    }
                    catch (Exception ex) { text = "Ошибка чтения лога: " + ex.Message; }
                }
                else
                {
                    text = "Файл лога пока пуст или отсутствует (" + logFile + ").";
                }

                this.BeginInvoke(new Action(() =>
                {
                    if (txtLogs != null)
                    {
                        txtLogs.Text = text;
                        txtLogs.SelectionStart = txtLogs.Text.Length;
                        txtLogs.ScrollToCaret();
                    }
                }));
            });
        }

        // Generate dynamic modern icon for window & tray
        Icon CreateAppIcon(Color statusColor)
        {
            using (Bitmap bmp = new Bitmap(32, 32))
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);

                // Outer circle (Dark)
                using (Brush b = new SolidBrush(CardDark))
                {
                    g.FillEllipse(b, 1, 1, 30, 30);
                }
                using (Pen p = new Pen(BorderDark, 2f))
                {
                    g.DrawEllipse(p, 1, 1, 30, 30);
                }

                // Letter "C" (Cyan)
                using (Font f = new Font("Segoe UI", 14f, FontStyle.Bold))
                using (Brush b = new SolidBrush(AccentCyan))
                {
                    g.DrawString("C", f, b, new PointF(7, 4));
                }

                // Status Indicator Dot (bottom right)
                using (Brush dot = new SolidBrush(statusColor))
                {
                    g.FillEllipse(dot, 19, 19, 11, 11);
                }
                using (Pen dotBorder = new Pen(CardDark, 2f))
                {
                    g.DrawEllipse(dotBorder, 19, 19, 11, 11);
                }

                IntPtr hIcon = bmp.GetHicon();
                return Icon.FromHandle(hIcon);
            }
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
