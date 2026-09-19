$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppFolder = Join-Path $env:LOCALAPPDATA 'NoteAccountSwitcher'
$script:ProfilesFolder = Join-Path $script:AppFolder 'Profiles'
$script:AccountsFile = Join-Path $script:AppFolder 'accounts.json'
$script:Accounts = @()
$script:Colors = @(
    [Drawing.Color]::FromArgb(35, 120, 210),
    [Drawing.Color]::FromArgb(35, 155, 90),
    [Drawing.Color]::FromArgb(235, 135, 35),
    [Drawing.Color]::FromArgb(140, 80, 200),
    [Drawing.Color]::FromArgb(225, 75, 135),
    [Drawing.Color]::FromArgb(20, 155, 165)
)

New-Item -ItemType Directory -Path $script:ProfilesFolder -Force | Out-Null

function Load-Accounts {
    if (-not (Test-Path -LiteralPath $script:AccountsFile)) {
        $script:Accounts = @()
        return
    }
    try {
        $loaded = Get-Content -LiteralPath $script:AccountsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:Accounts = @($loaded)
    } catch {
        [Windows.Forms.MessageBox]::Show("設定を読み込めませんでした。`n$($_.Exception.Message)", 'エラー', 'OK', 'Error') | Out-Null
        $script:Accounts = @()
    }
}

function Save-Accounts {
    try {
        $json = ConvertTo-Json -InputObject @($script:Accounts) -Depth 4
        [IO.File]::WriteAllText($script:AccountsFile, $json, [Text.UTF8Encoding]::new($false))
    } catch {
        [Windows.Forms.MessageBox]::Show("設定を保存できませんでした。`n$($_.Exception.Message)", 'エラー', 'OK', 'Error') | Out-Null
    }
}

function Get-ChromePath {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe' }),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    ) | Where-Object { $_ }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Get-ProfilePath($account) {
    Join-Path $script:ProfilesFolder ([string]$account.id)
}

function Open-Account($account) {
    $chrome = Get-ChromePath
    if (-not $chrome) {
        [Windows.Forms.MessageBox]::Show('Google Chromeが見つかりません。Chromeをインストールしてから再度お試しください。', 'エラー', 'OK', 'Error') | Out-Null
        return
    }
    $profile = Get-ProfilePath $account
    New-Item -ItemType Directory -Path $profile -Force | Out-Null
    try {
        Start-Process -FilePath $chrome -ArgumentList @("--user-data-dir=`"$profile`"", '--no-first-run', '--new-window', 'https://note.com/')
    } catch {
        [Windows.Forms.MessageBox]::Show("Chromeを起動できませんでした。`n$($_.Exception.Message)", 'エラー', 'OK', 'Error') | Out-Null
    }
}

function Show-AddDialog {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'アカウントを追加'
    $dialog.ClientSize = [Drawing.Size]::new(410, 225)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = [Drawing.Font]::new('Yu Gothic UI', 10)

    $nameLabel = New-Object Windows.Forms.Label
    $nameLabel.Text = '識別名'
    $nameLabel.SetBounds(20, 20, 370, 24)
    $dialog.Controls.Add($nameLabel)

    $nameBox = New-Object Windows.Forms.TextBox
    $nameBox.SetBounds(20, 47, 370, 28)
    $dialog.Controls.Add($nameBox)

    $colorLabel = New-Object Windows.Forms.Label
    $colorLabel.Text = '識別カラー'
    $colorLabel.SetBounds(20, 92, 370, 24)
    $dialog.Controls.Add($colorLabel)

    $colorBox = New-Object Windows.Forms.ComboBox
    $colorBox.DropDownStyle = 'DropDownList'
    @('ブルー', 'グリーン', 'オレンジ', 'パープル', 'ピンク', 'ティール') | ForEach-Object { [void]$colorBox.Items.Add($_) }
    $colorBox.SelectedIndex = 0
    $colorBox.SetBounds(20, 119, 180, 28)
    $dialog.Controls.Add($colorBox)

    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'キャンセル'
    $cancel.DialogResult = 'Cancel'
    $cancel.SetBounds(205, 175, 90, 32)
    $dialog.Controls.Add($cancel)

    $add = New-Object Windows.Forms.Button
    $add.Text = '追加'
    $add.SetBounds(300, 175, 90, 32)
    $add.Add_Click({
        if ([string]::IsNullOrWhiteSpace($nameBox.Text)) {
            [Windows.Forms.MessageBox]::Show('識別名を入力してください。', '確認', 'OK', 'Information') | Out-Null
            return
        }
        $dialog.Tag = [PSCustomObject]@{
            id = [Guid]::NewGuid().ToString()
            name = $nameBox.Text.Trim()
            colorIndex = $colorBox.SelectedIndex
        }
        $dialog.DialogResult = 'OK'
        $dialog.Close()
    })
    $dialog.Controls.Add($add)
    $dialog.AcceptButton = $add
    $dialog.CancelButton = $cancel

    if ($dialog.ShowDialog($script:Form) -eq 'OK') { return $dialog.Tag }
    return $null
}

function Remove-Account($account) {
    $choice = [Windows.Forms.MessageBox]::Show(
        "「$($account.name)」を削除します。`n`nはい: 一覧とログイン情報を削除`nいいえ: 一覧からのみ削除`nキャンセル: 何もしない",
        'アカウントの削除', 'YesNoCancel', 'Warning'
    )
    if ($choice -eq 'Cancel') { return }
    if ($choice -eq 'Yes') {
        $profile = Get-ProfilePath $account
        if (Test-Path -LiteralPath $profile) {
            try { Remove-Item -LiteralPath $profile -Recurse -Force }
            catch {
                [Windows.Forms.MessageBox]::Show("ログイン情報を削除できませんでした。Chromeを閉じてから再度お試しください。`n$($_.Exception.Message)", 'エラー', 'OK', 'Error') | Out-Null
                return
            }
        }
    }
    $script:Accounts = @($script:Accounts | Where-Object { $_.id -ne $account.id })
    Save-Accounts
    Refresh-AccountList
}

function Refresh-AccountList {
    $script:AccountPanel.SuspendLayout()
    $script:AccountPanel.Controls.Clear()
    if ($script:Accounts.Count -eq 0) {
        $empty = New-Object Windows.Forms.Label
        $empty.Text = "アカウントがありません。`n「追加」から最初のアカウントを登録してください。"
        $empty.TextAlign = 'MiddleCenter'
        $empty.ForeColor = [Drawing.Color]::DimGray
        $empty.Dock = 'Fill'
        $script:AccountPanel.Controls.Add($empty)
    } else {
        foreach ($account in $script:Accounts) {
            $row = New-Object Windows.Forms.Panel
            $row.Height = 62
            $row.Dock = 'Top'
            $row.Padding = [Windows.Forms.Padding]::new(12, 10, 12, 10)
            $row.BackColor = [Drawing.Color]::FromArgb(245, 246, 248)
            $row.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 8)

            $dot = New-Object Windows.Forms.Label
            $dot.Text = '●'
            $dot.Font = [Drawing.Font]::new('Yu Gothic UI', 16)
            $dot.ForeColor = $script:Colors[[int]$account.colorIndex % $script:Colors.Count]
            $dot.SetBounds(12, 14, 30, 34)
            $row.Controls.Add($dot)

            $label = New-Object Windows.Forms.Label
            $label.Text = [string]$account.name
            $label.Font = [Drawing.Font]::new('Yu Gothic UI', 11, [Drawing.FontStyle]::Bold)
            $label.AutoEllipsis = $true
            $label.Anchor = 'Top,Left,Right'
            $label.SetBounds(48, 19, 410, 28)
            $row.Controls.Add($label)

            $menuButton = New-Object Windows.Forms.Button
            $menuButton.Text = '⋯'
            $menuButton.Anchor = 'Top,Right'
            $menuButton.SetBounds(542, 14, 42, 34)
            $row.Controls.Add($menuButton)

            $openButton = New-Object Windows.Forms.Button
            $openButton.Text = '開く'
            $openButton.Anchor = 'Top,Right'
            $openButton.SetBounds(458, 14, 78, 34)
            $openButton.BackColor = $script:Colors[[int]$account.colorIndex % $script:Colors.Count]
            $openButton.ForeColor = [Drawing.Color]::White
            $openButton.FlatStyle = 'Flat'
            $openButton.Tag = $account
            $openButton.Add_Click({ Open-Account $this.Tag })
            $row.Controls.Add($openButton)

            $menu = New-Object Windows.Forms.ContextMenuStrip
            $showFolder = $menu.Items.Add('保存場所を表示')
            $showFolder.Tag = $account
            $showFolder.Add_Click({
                $path = Get-ProfilePath $this.Tag
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Start-Process explorer.exe -ArgumentList @("`"$path`"")
            })
            [void]$menu.Items.Add('-')
            $remove = $menu.Items.Add('削除…')
            $remove.Tag = $account
            $remove.Add_Click({ Remove-Account $this.Tag })
            $menuButton.Tag = $menu
            $menuButton.Add_Click({ $this.Tag.Show($this, [Drawing.Point]::new(0, $this.Height)) })

            $script:AccountPanel.Controls.Add($row)
            $script:AccountPanel.Controls.SetChildIndex($row, 0)
        }
    }
    $script:AccountPanel.ResumeLayout()
}

Load-Accounts

$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = 'note アカウントスイッチャー'
$script:Form.ClientSize = [Drawing.Size]::new(640, 450)
$script:Form.MinimumSize = [Drawing.Size]::new(656, 489)
$script:Form.StartPosition = 'CenterScreen'
$script:Form.Font = [Drawing.Font]::new('Yu Gothic UI', 10)
$script:Form.BackColor = [Drawing.Color]::White

$header = New-Object Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 86
$header.Padding = [Windows.Forms.Padding]::new(20)
$script:Form.Controls.Add($header)

$title = New-Object Windows.Forms.Label
$title.Text = 'note アカウントスイッチャー'
$title.Font = [Drawing.Font]::new('Yu Gothic UI', 16, [Drawing.FontStyle]::Bold)
$title.SetBounds(20, 14, 410, 34)
$header.Controls.Add($title)

$subtitle = New-Object Windows.Forms.Label
$subtitle.Text = 'アカウント専用のChromeでnoteを開きます'
$subtitle.ForeColor = [Drawing.Color]::DimGray
$subtitle.SetBounds(22, 50, 410, 24)
$header.Controls.Add($subtitle)

$addButton = New-Object Windows.Forms.Button
$addButton.Text = '＋ 追加'
$addButton.Anchor = 'Top,Right'
$addButton.SetBounds(530, 25, 90, 36)
$addButton.BackColor = [Drawing.Color]::FromArgb(35, 120, 210)
$addButton.ForeColor = [Drawing.Color]::White
$addButton.FlatStyle = 'Flat'
$addButton.Add_Click({
    $newAccount = Show-AddDialog
    if ($newAccount) {
        $script:Accounts += $newAccount
        Save-Accounts
        Refresh-AccountList
    }
})
$header.Controls.Add($addButton)

$footer = New-Object Windows.Forms.Label
$footer.Text = '🔒 パスワードは保存しません。ログイン状態はWindows内の専用Chrome領域に保存されます。'
$footer.ForeColor = [Drawing.Color]::DimGray
$footer.Dock = 'Bottom'
$footer.Height = 48
$footer.Padding = [Windows.Forms.Padding]::new(14)
$script:Form.Controls.Add($footer)

$script:AccountPanel = New-Object Windows.Forms.FlowLayoutPanel
$script:AccountPanel.Dock = 'Fill'
$script:AccountPanel.FlowDirection = 'TopDown'
$script:AccountPanel.WrapContents = $false
$script:AccountPanel.AutoScroll = $true
$script:AccountPanel.Padding = [Windows.Forms.Padding]::new(16, 12, 16, 12)
$script:AccountPanel.Add_SizeChanged({
    foreach ($control in $this.Controls) {
        if ($control -is [Windows.Forms.Panel]) { $control.Width = [Math]::Max(590, $this.ClientSize.Width - 36) }
    }
})
$script:Form.Controls.Add($script:AccountPanel)
$script:AccountPanel.BringToFront()

Refresh-AccountList
[void][Windows.Forms.Application]::Run($script:Form)
