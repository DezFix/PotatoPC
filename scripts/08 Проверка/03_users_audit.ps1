# NAME: 03 · Аудит учёток: лишние админы и дыры (только показ)
# DESC: Проверяет членов группы Администраторы, гостя, бессрочные пароли, автовход с паролем в реестре и RDP. Ничего не меняет
# TAGS: 1
# ICON: 👤

$ErrorActionPreference = "Stop"
try {
    Write-Output "=== Аудит учёток (только чтение) ==="
    try {
        $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object { $_.Name })
        Write-Output ("[*] Администраторов: " + $admins.Count + " (" + ($admins -join "; ") + ")")
        if ($admins.Count -gt 2) { Write-Output "[!] Админов больше двух — проверь лишних во вкладке «Пользователи»." }
    } catch { Write-Output "[!] Не смог прочитать группу Администраторы." }
    try {
        $guest = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like '*-501' } | Select-Object -First 1
        if ($guest) { Write-Output ("[*] Гость: " + $(if ($guest.Enabled) { "ВКЛЮЧЁН (риск!)" } else { "отключён (норма)" })) }
    } catch {}
    try {
        $never = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.PasswordNeverExpires })
        if ($never.Count -gt 0) { Write-Output ("[!] Бессрочный пароль у: " + (($never | ForEach-Object { $_.Name }) -join ", ")) }
        else { Write-Output "[*] Бессрочных паролей нет." }
    } catch {}
    try {
        $w = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        $auto = (Get-ItemProperty -Path $w -Name "AutoAdminLogon" -ErrorAction SilentlyContinue).AutoAdminLogon
        if ("$auto" -eq "1") {
            $who = (Get-ItemProperty -Path $w -Name "DefaultUserName" -ErrorAction SilentlyContinue).DefaultUserName
            Write-Output ("[!] Автовход ВКЛЮЧЁН (" + $who + ") — вход без пароля!")
            try {
                $pw = Get-ItemProperty -Path $w -Name "DefaultPassword" -ErrorAction Stop
                if ($pw -and $pw.DefaultPassword) { Write-Output "[!] Пароль лежит в реестре ОТКРЫТЫМ ТЕКСТОМ — убери автовход!" }
            } catch { Write-Output "[*] Пароля в реестре нет (возможно, вход без пароля)." }
        } else { Write-Output "[*] Автовход выключен (норма)." }
    } catch {}
    try {
        $rdp = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
        Write-Output ("[*] Удалённый рабочий стол: " + $(if ($rdp -eq 0) { "РАЗРЕШЁН — нужен ли?" } else { "запрещён (норма)" }))
    } catch {}
    Write-Output "[OK] Аудит закончен, ничего не менялось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
