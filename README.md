# VeeamNotify

Send Veeam Backup & Replication session summary notifications to Discord, Microsoft Teams, Slack, WeCom (企业微信), and Feishu (飞书), detailing session result and statistics and optionally alerting you via mention when a job finishes in a warning or failed state.

VeeamNotify is a replacement for [VeeamDiscordNotifications](https://github.com/tigattack/VeeamDiscordNotifications) and the respective [Teams](https://github.com/tigattack/VeeamTeamsNotifications) and [Slack](https://github.com/tigattack/VeeamSlackNotifications) projects, featuring improvements across the board and support for all the aforementioned messaging services in one, easy to use project.

<img src="https://github.com/6547709/VeeamNotify/blob/main/asset/discord.png?raw=true" width="30%"></img> <img src="https://github.com/6547709/VeeamNotify/blob/main/asset/slack.png?raw=true" width="30%"></img> <img src="https://github.com/6547709/VeeamNotify/blob/main/asset/teams.png?raw=true" width="30%"></img>

## Supported Notification Services

* Discord
* Slack
* Microsoft Teams
* Telegram
* WeCom (企业微信群机器人, `template_card` text notice)
* Feishu (飞书自定义机器人, Card 2.0)

Please create a [feature request](https://github.com/6547709/VeeamNotify/issues) if your preferred service isn't listed here.

## Supported Veeam Job Types

* VM Backup
* VM Replication
* Windows & Linux Agent Backup jobs*

### *Agent job support

Due to limitations in Veeam, only some types of Agent jobs are supported.

**Supported** jobs are known as "Agent Backup" or "Managed by backup server". **Unsupported** jobs are known as "Agent policy" or "Managed by agent". See the spoilered illustration below if this isn't clear to you.

<details>
<summary>Illustrated screenshot showing an example of supported types</summary>
<img src="asset/agent-types.png" width="75%"></img>

**Note:** Linux Agent Backup jobs are also supported, this image is only an example.
</details>

You can read about the difference between these two Agent job types [here](https://helpcenter.veeam.com/docs/backup/agents/agent_job_protection_mode.html?ver=110#selecting-job-mode).

Unfortunately, even supported Agent jobs return a reduced amount of session information, so you won't see as much detail in the notification (see the example screenshots at the top).  
As much relevant information as I've been able to discover from such backup sessions is included in the notifications, but I welcome any suggestions for improvement in this area.

## Installation

Requirements:
* Veeam Backup & Replication 12 or higher.
* PowerShell 5.1 or higher.

Run PowerShell as Administrator on the Veeam server.

**Option 1: install from a release (recommended)**

1. Download the latest `VeeamNotify-vX.Y.Z.zip` from [Releases](https://github.com/6547709/VeeamNotify/releases).
2. Extract it so the project lives at `C:\VeeamScripts\VeeamNotify`.
3. Run the installer:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
C:\VeeamScripts\VeeamNotify\Installer.ps1
```

**Option 2: install from source**

```powershell
git clone https://github.com/6547709/VeeamNotify.git C:\VeeamScripts\VeeamNotify
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
C:\VeeamScripts\VeeamNotify\Installer.ps1
```

The installer prompts for the notification service and webhook, writes `config\conf.json`, and can optionally configure supported Veeam jobs to call `Bootstrap.ps1` after each session.

## Configuration

Default configuration can be found in `C:\VeeamScripts\VeeamNotify\config\conf.example.json`.

All available options, including mentions, logging, and update settings, are shown in the example file and validated by `config\schema.json`.

Minimal WeCom / Feishu configuration:

```json
"wecom":  { "enabled": true, "webhook": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=..." },
"feishu": { "enabled": true, "webhook": "https://open.feishu.cn/open-apis/bot/v2/hook/..." }
```

Both services only need `enabled` and `webhook`. Mentions are not supported for these two services.

---

## Credits

[MelonSmasher](https://github.com/MelonSmasher)//[TheSageColleges](https://github.com/TheSageColleges) for [the project](https://github.com/TheSageColleges/VeeamSlackNotifications) which inspired me to make this.  
[dantho281](https://github.com/dantho281) for various things - Assistance with silly little issues, the odd bugfix here and there, and the inspiration for and first works on the `Updater.ps1` script.  
[Lee_Dailey](https://reddit.com/u/Lee_Dailey) for general pointers and the [first revision](https://pastebin.com/srN5CKty) of the `Format-ByteUnit` function.  
[philenst](https://github.com/philenst) for committing or assisting with a number of core components of the project.  
[s0yun](https://github.com/s0yun) for the `Installer.ps1` script.  

Thank you all.
