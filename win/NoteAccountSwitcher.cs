using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Windows.Forms;

namespace NoteAccountSwitcher
{
    [DataContract]
    public class NoteAccount
    {
        [DataMember(Name = "id")] public string Id { get; set; }
        [DataMember(Name = "name")] public string Name { get; set; }
        [DataMember(Name = "colorIndex")] public int ColorIndex { get; set; }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    public sealed class MainForm : Form
    {
        private readonly string appFolder;
        private readonly string profilesFolder;
        private readonly string accountsFile;
        private readonly FlowLayoutPanel accountPanel;
        private List<NoteAccount> accounts;

        private readonly Color[] colors =
        {
            Color.FromArgb(35, 120, 210), Color.FromArgb(35, 155, 90),
            Color.FromArgb(235, 135, 35), Color.FromArgb(140, 80, 200),
            Color.FromArgb(225, 75, 135), Color.FromArgb(20, 155, 165)
        };

        public MainForm()
        {
            appFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NoteAccountSwitcher");
            profilesFolder = Path.Combine(appFolder, "Profiles");
            accountsFile = Path.Combine(appFolder, "accounts.json");
            Directory.CreateDirectory(profilesFolder);
            accounts = LoadAccounts();

            Text = "note アカウントスイッチャー";
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            ClientSize = new Size(640, 450);
            MinimumSize = new Size(656, 489);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Yu Gothic UI", 10F);
            BackColor = Color.White;

            var header = new Panel { Dock = DockStyle.Top, Height = 86, BackColor = Color.White };
            var title = new Label
            {
                Text = "note アカウントスイッチャー",
                Font = new Font("Yu Gothic UI", 16F, FontStyle.Bold),
                Location = new Point(20, 14), Size = new Size(430, 34)
            };
            var subtitle = new Label
            {
                Text = "アカウント専用のChromeでnoteを開きます",
                ForeColor = Color.DimGray,
                Location = new Point(22, 50), Size = new Size(430, 24)
            };
            var addButton = new Button
            {
                Text = "＋ 追加",
                Location = new Point(530, 25), Size = new Size(90, 36),
                BackColor = colors[0], ForeColor = Color.White, FlatStyle = FlatStyle.Flat
            };
            addButton.Click += delegate { AddAccount(); };
            header.SizeChanged += delegate
            {
                addButton.Left = Math.Max(20, header.ClientSize.Width - addButton.Width - 20);
            };
            header.Controls.Add(title);
            header.Controls.Add(subtitle);
            header.Controls.Add(addButton);

            var footer = new Label
            {
                Text = "パスワードは保存しません。ログイン状態はWindows内の専用Chrome領域に保存されます。",
                ForeColor = Color.DimGray, Dock = DockStyle.Bottom, Height = 48,
                Padding = new Padding(14), BackColor = Color.White
            };

            accountPanel = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
                WrapContents = false, AutoScroll = true, Padding = new Padding(16, 12, 16, 12),
                BackColor = Color.White
            };
            accountPanel.SizeChanged += delegate { ResizeRows(); };

            Controls.Add(accountPanel);
            Controls.Add(footer);
            Controls.Add(header);
            RefreshAccounts();
        }

        private List<NoteAccount> LoadAccounts()
        {
            if (!File.Exists(accountsFile)) return new List<NoteAccount>();
            try
            {
                using (var stream = File.OpenRead(accountsFile))
                {
                    var serializer = new DataContractJsonSerializer(typeof(List<NoteAccount>));
                    return (List<NoteAccount>)serializer.ReadObject(stream) ?? new List<NoteAccount>();
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("設定を読み込めませんでした。\n" + ex.Message, "エラー", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return new List<NoteAccount>();
            }
        }

        private void SaveAccounts()
        {
            try
            {
                string temporary = accountsFile + ".tmp";
                using (var stream = File.Create(temporary))
                {
                    var serializer = new DataContractJsonSerializer(typeof(List<NoteAccount>));
                    serializer.WriteObject(stream, accounts);
                }
                if (File.Exists(accountsFile)) File.Replace(temporary, accountsFile, null);
                else File.Move(temporary, accountsFile);
            }
            catch (Exception ex)
            {
                MessageBox.Show("設定を保存できませんでした。\n" + ex.Message, "エラー", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void AddAccount()
        {
            using (var dialog = new AddAccountForm(colors))
            {
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                accounts.Add(new NoteAccount
                {
                    Id = Guid.NewGuid().ToString(), Name = dialog.AccountName, ColorIndex = dialog.ColorIndex
                });
                SaveAccounts();
                RefreshAccounts();
            }
        }

        private void RefreshAccounts()
        {
            accountPanel.SuspendLayout();
            accountPanel.Controls.Clear();
            if (accounts.Count == 0)
            {
                accountPanel.Controls.Add(new Label
                {
                    Text = "アカウントがありません。\n「追加」から最初のアカウントを登録してください。",
                    TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.DimGray,
                    Size = new Size(Math.Max(300, accountPanel.ClientSize.Width - 40), 220)
                });
            }
            else
            {
                foreach (NoteAccount account in accounts) accountPanel.Controls.Add(CreateAccountRow(account));
            }
            ResizeRows();
            accountPanel.ResumeLayout();
        }

        private Control CreateAccountRow(NoteAccount account)
        {
            int colorIndex = Math.Abs(account.ColorIndex) % colors.Length;
            var row = new TableLayoutPanel
            {
                Height = 62, Width = Math.Max(590, accountPanel.ClientSize.Width - 40),
                BackColor = Color.FromArgb(245, 246, 248), Margin = new Padding(0, 0, 0, 8),
                Padding = new Padding(12, 10, 12, 10), RowCount = 1, ColumnCount = 4
            };
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 36));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 86));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 48));

            var dot = new Label
            {
                Text = "●", Font = new Font("Yu Gothic UI", 16F), ForeColor = colors[colorIndex],
                Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft
            };
            var name = new Label
            {
                Text = account.Name, Font = new Font("Yu Gothic UI", 11F, FontStyle.Bold),
                Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true
            };
            var open = new Button
            {
                Text = "開く", Dock = DockStyle.Fill, Margin = new Padding(4),
                BackColor = colors[colorIndex], ForeColor = Color.White, FlatStyle = FlatStyle.Flat
            };
            open.Click += delegate { OpenAccount(account); };
            var menuButton = new Button { Text = "…", Dock = DockStyle.Fill, Margin = new Padding(4) };
            var menu = new ContextMenuStrip();
            menu.Items.Add("保存場所を表示", null, delegate { RevealProfile(account); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("削除…", null, delegate { RemoveAccount(account); });
            menuButton.Click += delegate { menu.Show(menuButton, new Point(0, menuButton.Height)); };

            row.Controls.Add(dot, 0, 0);
            row.Controls.Add(name, 1, 0);
            row.Controls.Add(open, 2, 0);
            row.Controls.Add(menuButton, 3, 0);
            return row;
        }

        private void ResizeRows()
        {
            int width = Math.Max(590, accountPanel.ClientSize.Width - 40);
            foreach (Control control in accountPanel.Controls)
                if (control is TableLayoutPanel) control.Width = width;
        }

        private string ProfilePath(NoteAccount account)
        {
            return Path.Combine(profilesFolder, account.Id);
        }

        private string ChromePath()
        {
            var candidates = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google", "Chrome", "Application", "chrome.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Google", "Chrome", "Application", "chrome.exe")
            };
            return candidates.FirstOrDefault(File.Exists);
        }

        private void OpenAccount(NoteAccount account)
        {
            string chrome = ChromePath();
            if (chrome == null)
            {
                MessageBox.Show("Google Chromeが見つかりません。Chromeをインストールしてから再度お試しください。", "エラー", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            try
            {
                string profile = ProfilePath(account);
                Directory.CreateDirectory(profile);
                Process.Start(new ProcessStartInfo
                {
                    FileName = chrome,
                    Arguments = "--user-data-dir=\"" + profile + "\" --no-first-run --new-window https://note.com/",
                    UseShellExecute = false
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show("Chromeを起動できませんでした。\n" + ex.Message, "エラー", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void RevealProfile(NoteAccount account)
        {
            string profile = ProfilePath(account);
            Directory.CreateDirectory(profile);
            Process.Start("explorer.exe", "\"" + profile + "\"");
        }

        private void RemoveAccount(NoteAccount account)
        {
            DialogResult choice = MessageBox.Show(
                "「" + account.Name + "」を削除します。\n\nはい: 一覧とログイン情報を削除\nいいえ: 一覧からのみ削除\nキャンセル: 何もしない",
                "アカウントの削除", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
            if (choice == DialogResult.Cancel) return;
            if (choice == DialogResult.Yes)
            {
                try
                {
                    string profile = ProfilePath(account);
                    if (Directory.Exists(profile)) Directory.Delete(profile, true);
                }
                catch (Exception ex)
                {
                    MessageBox.Show("ログイン情報を削除できませんでした。Chromeを閉じてから再度お試しください。\n" + ex.Message, "エラー", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
            }
            accounts.RemoveAll(delegate(NoteAccount item) { return item.Id == account.Id; });
            SaveAccounts();
            RefreshAccounts();
        }
    }

    public sealed class AddAccountForm : Form
    {
        private readonly TextBox nameBox;
        private readonly ComboBox colorBox;
        public string AccountName { get { return nameBox.Text.Trim(); } }
        public int ColorIndex { get { return colorBox.SelectedIndex; } }

        public AddAccountForm(Color[] colors)
        {
            Text = "アカウントを追加";
            ClientSize = new Size(410, 225);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Yu Gothic UI", 10F);

            Controls.Add(new Label { Text = "識別名", Location = new Point(20, 20), Size = new Size(370, 24) });
            nameBox = new TextBox { Location = new Point(20, 47), Size = new Size(370, 28) };
            Controls.Add(nameBox);
            Controls.Add(new Label { Text = "識別カラー", Location = new Point(20, 92), Size = new Size(370, 24) });
            colorBox = new ComboBox
            {
                DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(20, 119), Size = new Size(180, 28)
            };
            colorBox.Items.AddRange(new object[] { "ブルー", "グリーン", "オレンジ", "パープル", "ピンク", "ティール" });
            colorBox.SelectedIndex = 0;
            Controls.Add(colorBox);

            var cancel = new Button { Text = "キャンセル", DialogResult = DialogResult.Cancel, Location = new Point(205, 175), Size = new Size(90, 32) };
            var add = new Button { Text = "追加", Location = new Point(300, 175), Size = new Size(90, 32) };
            add.Click += delegate
            {
                if (string.IsNullOrWhiteSpace(nameBox.Text))
                {
                    MessageBox.Show("識別名を入力してください。", "確認", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                DialogResult = DialogResult.OK;
                Close();
            };
            Controls.Add(cancel); Controls.Add(add);
            AcceptButton = add; CancelButton = cancel;
        }
    }
}
