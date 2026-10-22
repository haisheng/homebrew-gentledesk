# GentleDesk Windows 本机连接器

支持 Windows 10 / 11 自带的 Windows PowerShell 5.1，使用 .NET、Windows Forms 与系统默认应用打开接口，无 Python 依赖。

在当前文件夹运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ExtensionId 扩展ID
```

该策略仅作用于本次进程，不更改全局策略。组织管理的电脑需要遵守管理员的脚本策略。脚本安装在当前用户 LocalAppData/DeskAssit，将该目录 ACL 限制为当前用户和 SYSTEM，并注册 HKCU 下的 Chrome Native Messaging 主机，无需管理员权限。

返回扩展确认权限，选择桌面目录。仅同步所选目录第一层，最多 250 个项目，不读取内容，不修改或删除文件。打开项目时校验 ID 与当前目录枚举结果，调用 ProcessStartInfo.UseShellExecute，不构造命令字符串。Windows 公共桌面可以单独选择，当前不会自动合并用户与公共桌面。

卸载：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1`。

自测：`powershell.exe -NoProfile -File .\host.ps1 -SelfTest`。发布前必须在 Windows 真机验证安装、中文路径、选择目录、快捷方式打开、删除同步与卸载。仓库提供 Windows CI；仅有代码或 CI 配置不代表已在 Windows 完成验证。
