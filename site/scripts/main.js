(function () {
  'use strict';

  var I18N = {
    en: {
      'meta.title': 'Port Tools — Turn localhost ports into projects, apps, and service types',
      'nav.skip': 'Skip to main content',
      'nav.primaryAria': 'Primary navigation',
      'nav.demo': 'Interactive Demo',
      'nav.compare': 'Compare',
      'nav.architecture': 'Architecture',
      'nav.install': 'Install',
      'nav.studio': 'Studio',
      'nav.menuAria': 'Section navigation',
      'nav.mobileAria': 'Mobile section navigation',
      'controls.langLabel': '中文',
      'controls.langAria': '中文 — Switch language to Chinese',
      'controls.toLight': 'Switch to light theme',
      'controls.toDark': 'Switch to dark theme',
      'hero.eyebrow': 'macOS 14+ MENU BAR · APPLE SILICON · MIT',
      'hero.titleMid': ' finds a PID. ',
      'hero.titleEnd': 'Port\u00A0Tools finds the project behind it.',
      'hero.subPre': 'A local-first macOS menu-bar control plane for the development services already running on your Mac. Reconstruct repositories, Git worktrees, application manifests, stable ',
      'hero.subPost': ' routes, and identity-bound Safe Stop without changing how you start your apps.',
      'hero.ctaDownload': 'Download v1.0.6 (.dmg)',
      'hero.ctaDemo': 'Try Menu\u2011Bar Demo',
      'hero.ctaRepo': 'GitHub',
      'common.copy': 'Copy',
      'common.copied': 'Copied',
      'common.copyFailed': 'Copy failed',
      'trust.t1Title': 'SwiftUI + Bundled Go Core',
      'trust.t1Sub': 'Private Unix socket · Zero runtime deps',
      'trust.t2Title': 'Stable *.localhost Routes',
      'trust.t2Sub': ':17890 default · Optional :80 helper',
      'trust.t3Title': 'Revalidated Safe Stop',
      'trust.t3Sub': 'Refuses Docker & unattributed targets',
      'trust.t4Title': 'Local-Only · MIT',
      'trust.t4Sub': 'No accounts, telemetry, or /etc/hosts edits',
      'stage.aria': 'Port Tools real macOS app screenshots',
      'stage.lightAlt': 'Port Tools menu-bar popover in light appearance showing grouped local web projects',
      'stage.darkAlt': 'Port Tools menu-bar popover in dark appearance showing grouped local web projects',
      'stage.liveBadge': '● LIVE',
      'stage.projectsCount': '6 projects',
      'stage.caption': 'Real macOS popover captures',
      'stage.groupAria': 'Screenshot appearance preview',
      'stage.auto': 'Auto',
      'stage.light': 'Light',
      'stage.dark': 'Dark',
      'stage.compare': 'Compare',
      'wb.heading': 'Interactive Menu\u2011Bar Workbench',
      'wb.sub': 'Click any service to inspect reconstructed Git and manifest evidence, edit its *.localhost alias, toggle the port-free helper, or walk through Safe Stop, 3-second Force Stop, and Docker refusal.',
      'wb.popoverAria': 'Simulated Port Tools menu-bar popover',
      'wb.demoBadge': '● DEMO',
      'wb.reset': 'Reset demo',
      'wb.helperOn': 'Port-free addresses are active.',
      'wb.helperOff': 'Port-free addresses are off. Addresses use :17890.',
      'wb.helperBtnOn': 'Helper :80 ON',
      'wb.helperBtnOff': 'Fallback :17890',
      'wb.searchLabel': 'Filter project services',
      'wb.searchPlaceholder': 'Filter projects, branches, or ports…',
      'wb.otherWeb': 'Other Web endpoints',
      'wb.otherWeb1': 'Vite HMR status socket (loopback)',
      'wb.otherWeb2': 'Preview docs health endpoint (HTTP 404)',
      'wb.otherListeners': 'Other listeners',
      'wb.otherLis1': 'redis-server (non-HTTP TCP)',
      'wb.otherLis2': 'postgres (non-HTTP TCP)',
      'wb.otherLis3': 'mDNSResponder (system)',
      'wb.updated': 'Simulated local snapshot',
      'wb.shortcutHint': 'Press / in workbench to search',
      'wb.empty': 'No services match that filter.',
      'wb.inspect': 'Inspect',
      'wb.inspectAria': 'Inspect {name}',
      'wb.selected': 'Selected',
      'wb.selectedAria': 'Selected — View evidence for {name}',
      'wb.stop': 'Stop',
      'wb.stopAria': 'Stop {name}',
      'wb.restart': 'Restart',
      'wb.restartAria': 'Restart {name}',
      'wb.rename': 'Edit alias',
      'wb.copyRouteAria': 'Copy address for {name}',
      'wb.renameAria': 'Edit alias for {name}',
      'wb.aliasInputAria': 'Alias for {name}',
      'wb.save': 'Save',
      'wb.cancel': 'Cancel',
      'wb.supportToggle': '1 supporting',
      'wb.supportAria': '1 supporting — Toggle supporting service details for {name}',
      'wb.supportDetail': 'Supporting API · 127.0.0.1:3001 · HTTP 200 application/json (kept separate from openable Web pages)',
      'wb.shieldDockerSr': 'Docker container, stop refused',
      'wb.shieldStoppedSr': 'Stopped',
      'wb.stoppedLabel': 'Stopped · listener released',
      'wb.aliasError': 'Use 1–39 lowercase letters, digits, or hyphens (start and end with a letter or digit).',
      'wb.aliasDup': 'That alias is already assigned to another service.',
      'ins.kicker': 'EVIDENCE INSPECTOR',
      'ins.kickerStop': 'SAFE STOP REVIEW',
      'ins.kickerForce': 'FORCE STOP REVIEW',
      'ins.kickerRefused': 'STOP REFUSED',
      'ins.badgeRunning': 'Verified Web Page',
      'ins.badgeStopped': 'Stopped',
      'ins.badgeDocker': 'Docker · Refusal Demo',
      'ins.badgeIgnoresSigterm': 'Ignores SIGTERM Demo',
      'ins.pid': 'PID & Ancestry',
      'ins.repo': 'Git Repository',
      'ins.cwd': 'Working Directory',
      'ins.manifest': 'Manifest',
      'ins.bind': 'Bind Scope',
      'ins.probe': 'HTTP Probe',
      'ins.probeStoppedPrefix': 'Last probe before stop: ',
      'ins.route': 'Active Route',
      'ins.stopPolicy': 'Stop Policy',
      'ins.policyOwned': 'Eligible (current user, attributed)',
      'ins.policyForce': 'Eligible (ignores SIGTERM → demos 3s SIGKILL)',
      'ins.policyDocker': 'Refused (Docker published port)',
      'ins.copyRoute': 'Copy address',
      'ins.copyOrig': 'Copy original',
      'ins.reviewStop': 'Review Safe Stop…',
      'ins.restartBtn': 'Restart service',
      'ins.stopTitle': 'Stop this service?',
      'ins.stopSub': 'Simulated Safe Stop — Port Tools revalidates this exact process tree before sending SIGTERM.',
      'ins.planToken': 'Plan token',
      'ins.pidOrder': 'PID order',
      'ins.verifyPort': 'Verify released',
      'ins.confirmStop': 'Stop service',
      'ins.stopping': 'Revalidating and stopping…',
      'ins.stopLog1': '1. Revalidated PID {pid} start time and command line.',
      'ins.stopLog2': '2. Sent SIGTERM to {pid}.',
      'ins.stopLog3': '3. Verified listener 127.0.0.1:{port} released.',
      'ins.stopLogFail': '3. Listener 127.0.0.1:{port} still bound after grace window (process ignored SIGTERM).',
      'ins.forceTitle': 'Force stop this service?',
      'ins.forceSub': 'SIGKILL cannot be handled or postponed by the app. Port Tools will revalidate every PID and listener again.',
      'ins.forceCountdown': 'Force stop available in {n} s…',
      'ins.forceNow': 'Force stop now',
      'ins.forceDone': 'Second single-use plan revalidated PID {pid}, sent SIGKILL, and verified 127.0.0.1:{port} released.',
      'ins.refusedTitle': 'Cannot stop this service safely',
      'ins.refusedBody': 'Docker, other-user, shared-runtime, and unattributed processes are intentionally refused. Manage this container through Docker Desktop or docker compose.',
      'ins.back': 'Back to evidence',
      'ins.backToList': 'Services',
      'ins.emptyTitle': 'No matching services',
      'ins.emptyBody': 'Clear or adjust your filter in the service list to inspect ownership evidence or test Safe Stop.',
      'ins.clearFilter': 'Clear filter',
      'cmp.heading': 'Pain & Solution, in the Same Place',
      'cmp.sub': 'Port Tools does not replace the CLI and OS utilities developers already rely on. It connects the missing project context between them.',
      'cmp.p1Tag': 'OWNERSHIP',
      'cmp.p1Q': '“What project owns port 4178?”',
      'cmp.p1A': 'Follows process ancestry and working directories back to the repository, branch, Git worktree, and nearest application manifest.',
      'cmp.p2Tag': 'GROUPING',
      'cmp.p2Q': '“Why are there four node processes for one repo?”',
      'cmp.p2A': 'Groups applications by repository checkout and separates openable Web pages from background supporting services.',
      'cmp.p3Tag': 'ROUTING',
      'cmp.p3Q': '“The port changed again.”',
      'cmp.p3A': 'Assigns a persistent address such as phone-studio.localhost (or :17890 without the helper), so you never memorize random dev ports.',
      'cmp.p4Tag': 'SAFE STOP',
      'cmp.p4Q': '“Can I safely kill this old server?”',
      'cmp.p4A': 'Shows a reviewed stop plan, revalidates PID identity before SIGTERM, confirms listeners released, and refuses Docker or shared runtimes.',
      'cmp.caption': 'How Port Tools complements existing developer tools',
      'cmp.colTool': 'Tool',
      'cmp.colBest': 'Best at',
      'cmp.colAdd': 'What Port Tools adds',
      'cmp.r1Best': 'Sockets, ports, and PIDs',
      'cmp.r1Add': 'Repository, worktree, application manifest, Web classification, and a usable address',
      'cmp.r2Name': 'Activity Monitor',
      'cmp.r2Best': 'Process and resource inspection',
      'cmp.r2Add': 'A Web-service-first view organized around development projects',
      'cmp.r3Best': 'Freeing a port quickly',
      'cmp.r3Add': 'Ownership evidence, refusal rules, identity revalidation, and listener-release verification',
      'cmp.r4Best': 'Starting apps on stable named URLs',
      'cmp.r4Add': 'Discovery and classification of services that are already running',
      'cmp.r5Best': 'Flexible reverse-proxy infrastructure',
      'cmp.r5Add': 'Automatic local inventory and project-aware route ownership',
      'cmp.r6Best': 'Container and published-port management',
      'cmp.r6Add': 'One view for host processes, worktrees, applications, and conservative Docker handling',
      'arch.heading': 'One Local Workflow & Narrow Guardrails',
      'arch.sub': 'The native SwiftUI menu-bar app talks to a bundled Go core over a private, owner-only Unix socket—keeping scanning, probing, routing, and Safe Stop self-contained on your Mac.',
      'arch.w1Title': 'Discover',
      'arch.w1Body': 'Scan live HTTP/HTTPS listeners without changing how your app was started.',
      'arch.w2Title': 'Identify',
      'arch.w2Body': 'Match process trees and cwd to Git repo, worktree, manifest, and page title.',
      'arch.w3Title': 'Name',
      'arch.w3Body': 'Assign and persist a clean *.localhost route atomically across restarts.',
      'arch.w4Title': 'Open or Copy',
      'arch.w4Body': 'Jump straight to the page or copy either the alias or original :port URL.',
      'arch.w5Title': 'Stop Safely',
      'arch.w5Body': 'Revalidate target PIDs, send SIGTERM, and verify the socket was released.',
      'arch.c1Tag': 'IPC BOUNDARY',
      'arch.c1Title': 'Native SwiftUI + Bundled Go Core',
      'arch.c1Body': 'Communicates over a 0600 owner-only Unix socket (runtime/core.sock inside a 0700 directory). No Python, Node.js, Homebrew, or external proxy needed at runtime.',
      'arch.c2Tag': 'PORT-FREE HELPER',
      'arch.c2Title': 'Loopback-Only :80 Forwarding',
      'arch.c2Body': 'Optional SMAppService LaunchDaemon binds only 127.0.0.1:80 and [::1]:80 and forwards solely to 127.0.0.1:17890, falling back cleanly if busy or unapproved.',
      'arch.c3Tag': 'SAFE STOP',
      'arch.c3Title': 'Single-Use Plan & Refusal Policy',
      'arch.c3Body': 'Docker, other-user, shared-runtime, and unattributed listeners are refused. Only unmanaged owned services ignoring SIGTERM can trigger the 3-second red SIGKILL sheet.',
      'arch.c4Tag': 'V1.0.6 FOOTPRINT',
      'arch.c4Title': 'Quiet Idle Scanning',
      'arch.c4Body': 'Stops re-probing already-classified live listeners, backs off HTTP 501 responses, batches process inspection, and runs background refreshes on a 5-minute cadence.',
      'arch.boundTitle': 'v1.0 Scope & Deliberate Boundaries',
      'arch.b1': 'macOS 14 Sonoma or later; public Release builds target Apple Silicon (arm64).',
      'arch.b2': 'Loopback-only IPv4/IPv6 proxy—no accounts, telemetry, or public tunnels.',
      'arch.b3': 'Zero /etc/hosts edits, zero trusted local CA installation, and no port 443 HTTPS listener.',
      'arch.b4': 'Ordinary routing uses :17890; port-free *.localhost requires one System Settings approval.',
      'inst.heading': 'Install, Build & v1.0.6 Release Notes',
      'inst.sub': 'Install via Homebrew Cask, download the signed and notarized Apple Silicon DMG, or build the self-contained bundle locally with Go and Xcode Command Line Tools.',
      'inst.tablistAria': 'Port Tools installation options',
      'inst.tab1': 'Homebrew Cask',
      'inst.tab2': 'Direct DMG (v1.0.6)',
      'inst.tab3': 'Build from Source',
      'inst.tab4': 'v1.0.6 Release Notes',
      'inst.barBrew': 'zsh · Homebrew Cask (Apple Silicon · macOS 14+)',
      'inst.barDmg': 'zsh · Signed & Notarized v1.0.6 DMG (10.1 MiB)',
      'inst.barBuild': 'zsh · Build & Verify Bundle Locally',
      'inst.codeAriaBrew': 'Homebrew Cask installation commands',
      'inst.codeAriaDmg': 'Direct DMG download and SHA-256 verification commands',
      'inst.codeAriaBuild': 'Build and verify Port Tools from source commands',
      'inst.dlLink': 'Download DMG',
      'inst.cBrew1': '# Install via personal Homebrew tap',
      'inst.cBrew2': '# Upgrade later (Sparkle built in)',
      'inst.cDmg1': '# Download DMG & verify SHA-256',
      'inst.cBuild1': '# Verify bundle & runtime paths',
      'inst.relTitle': 'Port Tools 1.0.6 (Released 2026-11-22)',
      'inst.rel1': 'Stop periodic HTTP re-probing of already-classified live listeners and back off HTTP 501 responses instead of retrying every 3 seconds.',
      'inst.rel2': 'Significantly reduce idle CPU usage, subprocess churn, SSD writes, and log noise with batched process inspection, direct Unix-socket IPC, compact inventory persistence, and a 5-minute background refresh cadence.',
      'inst.rel3': 'Polish menu bar UI contrast, hover quick actions, keyboard search, and Docker service naming.',
      'inst.relDmg': 'Download v1.0.6 DMG',
      'inst.relAll': 'All Releases',
      'inst.relFeed': 'Sparkle Update Feed',
      'footer.brand': 'Port Tools v1.0.6 · MIT',
      'footer.note': ' — Runs locally on your Mac. No accounts, telemetry, or /etc/hosts changes.',
      'footer.aria': 'Footer navigation',
      'footer.releases': 'Releases',
      'footer.updates': 'Updates',
      'footer.issues': 'Issues',
      'msg.themeDark': 'Dark theme enabled',
      'msg.themeLight': 'Light theme enabled',
      'msg.langSwitched': 'Switched to English',
      'msg.demoReset': 'Demo reset',
      'msg.stopped': '{name} stopped',
      'msg.restarted': '{name} restarted',
      'msg.forceStopped': '{name} force stopped',
      'msg.forceReady': 'Force stop is now available for {name}',
      'msg.sigtermIgnored': '{name} ignored SIGTERM and is still listening',
      'msg.aliasUpdated': '{name} route updated to {url}',
      'msg.copiedVal': 'Copied {val}',
      'msg.inspecting': 'Inspecting {name}',
      'msg.clipboardUnavailable': 'Clipboard permission unavailable',
      'msg.copyFallbackTitle': 'Clipboard unavailable — copy manually below:',
      'msg.copyFallbackInputAria': 'Text to copy manually',
      'msg.close': 'Close'
    },
    'zh-Hans': {
      'meta.title': 'Port Tools — 把 localhost 端口还原成项目、应用和服务类型',
      'nav.skip': '跳到正文',
      'nav.primaryAria': '主导航',
      'nav.demo': '交互演示',
      'nav.compare': '对比与方案',
      'nav.architecture': '技术边界',
      'nav.install': '安装与构建',
      'nav.studio': '工作室',
      'nav.menuAria': '页面导航',
      'nav.mobileAria': '移动端页面导航',
      'controls.langLabel': 'EN',
      'controls.langAria': 'EN — Switch language to English',
      'controls.toLight': '切换到浅色模式',
      'controls.toDark': '切换到深色模式',
      'hero.eyebrow': 'macOS 14+ 菜单栏 · APPLE SILICON · MIT',
      'hero.titleMid': ' 找到 PID，',
      'hero.titleEnd': 'Port\u00A0Tools 看清背后的项目',
      'hero.subPre': '本地优先的 macOS 菜单栏工具，无需改变启动方式，即可把运行中的 localhost 端口识别为对应仓库、Git worktree、应用清单与稳定的 ',
      'hero.subPost': ' 地址，并在关闭服务前提供身份复核的安全停止流程。',
      'hero.ctaDownload': '下载 v1.0.6 (.dmg)',
      'hero.ctaDemo': '体验菜单栏演示',
      'hero.ctaRepo': 'GitHub 仓库',
      'common.copy': '复制',
      'common.copied': '已复制',
      'common.copyFailed': '复制失败',
      'trust.t1Title': '原生 SwiftUI + 内置 Go 核心',
      'trust.t1Sub': '私有 Unix socket · 运行时零外部依赖',
      'trust.t2Title': '稳定 *.localhost 路由',
      'trust.t2Sub': '默认 :17890 · 可选 :80 免端口 Helper',
      'trust.t3Title': '身份复核安全停止',
      'trust.t3Sub': '自动拒绝 Docker 与归属不明进程',
      'trust.t4Title': '仅限本机 · MIT 开源',
      'trust.t4Sub': '无账号、无遥测、不改 /etc/hosts',
      'stage.aria': 'Port Tools 真实 macOS 应用界面截图',
      'stage.lightAlt': '浅色外观下的 Port Tools 菜单栏弹窗截图，展示按项目分组的本地 Web 服务',
      'stage.darkAlt': '深色外观下的 Port Tools 菜单栏弹窗截图，展示按项目分组的本地 Web 服务',
      'stage.liveBadge': '● 运行中',
      'stage.projectsCount': '6 个项目',
      'stage.caption': '真实 macOS 菜单栏弹窗截图',
      'stage.groupAria': '截图外观切换',
      'stage.auto': '自动',
      'stage.light': '浅色',
      'stage.dark': '深色',
      'stage.compare': '双模式对比',
      'wb.heading': '交互式菜单栏工作台',
      'wb.sub': '点击任意服务查看还原出的 Git 与应用清单证据、修改 *.localhost 别名、切换免端口 Helper，或体验模拟安全停止、3 秒倒计时强制停止与 Docker 拒绝策略。',
      'wb.popoverAria': 'Port Tools 菜单栏弹窗交互模拟',
      'wb.demoBadge': '● 交互演示',
      'wb.reset': '重置演示',
      'wb.helperOn': '免端口 Helper 已启用（访问地址无需端口号）。',
      'wb.helperOff': '免端口 Helper 未启用，当前使用默认 :17890 回退端口。',
      'wb.helperBtnOn': '免端口 Helper :80',
      'wb.helperBtnOff': '回退端口 :17890',
      'wb.searchLabel': '筛选项目服务',
      'wb.searchPlaceholder': '筛选项目、分支或端口…',
      'wb.otherWeb': '其他 Web 端点',
      'wb.otherWeb1': 'Vite HMR 状态 socket（本机回环）',
      'wb.otherWeb2': '预览文档健康检查端点（HTTP 404）',
      'wb.otherListeners': '其他监听端口',
      'wb.otherLis1': 'redis-server（非 HTTP TCP）',
      'wb.otherLis2': 'postgres（非 HTTP TCP）',
      'wb.otherLis3': 'mDNSResponder（系统服务）',
      'wb.updated': '本地模拟快照',
      'wb.shortcutHint': '工作台内按 / 搜索',
      'wb.empty': '没有匹配当前筛选条件的服务。',
      'wb.inspect': '查看详情',
      'wb.inspectAria': '查看详情：{name}',
      'wb.selected': '已选中',
      'wb.selectedAria': '已选中 — 查看 {name} 证据详情',
      'wb.stop': '停止',
      'wb.stopAria': '停止：{name}',
      'wb.restart': '重启',
      'wb.restartAria': '重启：{name}',
      'wb.rename': '修改别名',
      'wb.copyRouteAria': '复制：{name} 地址',
      'wb.renameAria': '修改别名：{name}',
      'wb.aliasInputAria': '{name} 的本地别名',
      'wb.save': '保存',
      'wb.cancel': '取消',
      'wb.supportToggle': '1 个辅助服务',
      'wb.supportAria': '1 个辅助服务 — 切换 {name} 的辅助服务详情',
      'wb.supportDetail': '辅助服务 · 127.0.0.1:3001 · HTTP 200 application/json（与可打开 Web 页面分层展示）',
      'wb.shieldDockerSr': 'Docker 容器，禁止停止',
      'wb.shieldStoppedSr': '已停止',
      'wb.stoppedLabel': '已停止 · 监听端口已释放',
      'wb.aliasError': '请使用 1–39 位小写字母、数字或连字符（首尾须为字母或数字）。',
      'wb.aliasDup': '该别名已被其他服务占用。',
      'ins.kicker': '归属证据详情',
      'ins.kickerStop': '安全停止审查',
      'ins.kickerForce': '强制停止确认',
      'ins.kickerRefused': '拒绝停止',
      'ins.badgeRunning': '已验证 Web 页面',
      'ins.badgeStopped': '已停止',
      'ins.badgeDocker': 'Docker · 拒绝策略演示',
      'ins.badgeIgnoresSigterm': '忽略 SIGTERM 演示',
      'ins.pid': 'PID 与进程树',
      'ins.repo': 'Git 仓库',
      'ins.cwd': '工作目录',
      'ins.manifest': '应用清单',
      'ins.bind': '监听范围',
      'ins.probe': 'HTTP 探测',
      'ins.probeStoppedPrefix': '停止前最后探测：',
      'ins.route': '当前路由',
      'ins.stopPolicy': '停止策略',
      'ins.policyOwned': '允许停止（当前用户且归属明确）',
      'ins.policyForce': '允许停止（模拟忽略 SIGTERM → 触发 3 秒 SIGKILL）',
      'ins.policyDocker': '拒绝停止（Docker 映射端口）',
      'ins.copyRoute': '复制地址',
      'ins.copyOrig': '复制原始地址',
      'ins.reviewStop': '检查安全停止…',
      'ins.restartBtn': '重新启动演示服务',
      'ins.stopTitle': '停止此服务？',
      'ins.stopSub': '模拟安全停止 — 发送 SIGTERM 前，Port Tools 会再次核对这个进程树。',
      'ins.planToken': '计划令牌',
      'ins.pidOrder': 'PID 顺序',
      'ins.verifyPort': '释放校验',
      'ins.confirmStop': '停止服务',
      'ins.stopping': '正在重新验证并停止…',
      'ins.stopLog1': '1. 已复核 PID {pid} 启动时间与命令行。',
      'ins.stopLog2': '2. 已向 {pid} 发送 SIGTERM。',
      'ins.stopLog3': '3. 已确认 127.0.0.1:{port} 监听端口释放。',
      'ins.stopLogFail': '3. 等待后 127.0.0.1:{port} 仍在监听（目标进程忽略了 SIGTERM）。',
      'ins.forceTitle': '强制停止此服务？',
      'ins.forceSub': '应用无法捕获或延迟 SIGKILL。Port Tools 将再次核对每个 PID 与监听端口。',
      'ins.forceCountdown': '{n} 秒后可强制停止…',
      'ins.forceNow': '立即强制停止',
      'ins.forceDone': '二次复核计划已核对 PID {pid} 并发送 SIGKILL，127.0.0.1:{port} 端口已确认释放。',
      'ins.refusedTitle': '无法安全停止此服务',
      'ins.refusedBody': 'Docker、其他用户进程、共享 runtime 以及无法确认归属的目标会被直接拒绝。请通过 Docker Desktop 或 docker compose 管理容器。',
      'ins.back': '返回证据详情',
      'ins.backToList': '服务列表',
      'ins.emptyTitle': '没有匹配的服务',
      'ins.emptyBody': '清除或调整筛选关键词，即可继续查看归属证据或演示安全停止。',
      'ins.clearFilter': '清除筛选',
      'cmp.heading': '痛点和解决方式，放在一起',
      'cmp.sub': 'Port Tools 不打算替代开发者已经信任的工具，而是补齐它们之间缺少的项目上下文。',
      'cmp.p1Tag': '归属识别',
      'cmp.p1Q': '“4178 端口到底是哪个项目开的？”',
      'cmp.p1A': '顺着进程祖先与工作目录追溯到仓库、分支、Git worktree 与最近的应用清单。',
      'cmp.p2Tag': '项目分组',
      'cmp.p2Q': '“为什么同一个仓库里有四个 node 进程？”',
      'cmp.p2A': '按仓库和 worktree 分组展示应用，并把可直接打开的 Web 页面与后台辅助服务区分开。',
      'cmp.p3Tag': '稳定路由',
      'cmp.p3Q': '“端口又变了，记不住。”',
      'cmp.p3A': '分配持久化地址，例如 phone-studio.localhost（未启用免端口 Helper 时使用 :17890），无需记住随机开发端口。',
      'cmp.p4Tag': '安全停止',
      'cmp.p4Q': '“这个旧服务现在能安全关掉吗？”',
      'cmp.p4A': '展示停止计划，在发送 SIGTERM 前复核进程身份并确认端口释放；Docker 与共享 runtime 一律拒绝。',
      'cmp.caption': 'Port Tools 与常见开发工具的协作定位',
      'cmp.colTool': '工具',
      'cmp.colBest': '最擅长解决',
      'cmp.colAdd': 'Port Tools 补充的部分',
      'cmp.r1Best': 'socket、端口和 PID',
      'cmp.r1Add': '仓库、worktree、应用清单、Web 类型和可直接访问的地址',
      'cmp.r2Name': '活动监视器',
      'cmp.r2Best': '查看进程及资源占用',
      'cmp.r2Add': '只聚焦开发 Web 服务，并围绕项目而不是孤立 PID 组织信息',
      'cmp.r3Best': '快速释放端口',
      'cmp.r3Add': '归属证据、拒绝规则、身份复核和端口释放确认',
      'cmp.r4Best': '用稳定域名启动应用',
      'cmp.r4Add': '直接发现并识别已经通过其他命令、IDE 或 Agent 启动的服务',
      'cmp.r5Best': '灵活的反向代理基础设施',
      'cmp.r5Add': '自动维护本地服务清单，并建立项目语义的路由归属',
      'cmp.r6Best': '容器及其映射端口管理',
      'cmp.r6Add': '把宿主机进程、worktree、应用和保守的 Docker 处理放在同一视图中',
      'arch.heading': '本地工作流与清晰边界',
      'arch.sub': '原生 SwiftUI 菜单栏界面通过私有、仅当前用户可访问的 Unix socket 与内置 Go 核心通信，扫描、探测、路由与安全停止完全在本地完成。',
      'arch.w1Title': '发现',
      'arch.w1Body': '扫描已在运行的 HTTP/HTTPS 服务，不要求修改原来的启动命令。',
      'arch.w2Title': '识别',
      'arch.w2Body': '根据进程树与 cwd 匹配 Git 仓库、worktree、应用清单与网页标题。',
      'arch.w3Title': '命名',
      'arch.w3Body': '原子化持久化 *.localhost 别名，重开项目后依然稳定。',
      'arch.w4Title': '打开或复制',
      'arch.w4Body': '在菜单栏直接打开，或一键复制别名地址与原始端口地址。',
      'arch.w5Title': '安全停止',
      'arch.w5Body': '再次核对进程身份后发送 SIGTERM，并确认监听端口真正释放。',
      'arch.c1Tag': 'IPC 边界',
      'arch.c1Title': '原生 SwiftUI + 内置 Go 核心',
      'arch.c1Body': '通过 0600 权限的私有 Unix socket（位于 0700 目录中的 runtime/core.sock）通信。运行时无需 Python、Node.js、Homebrew 或外部代理。',
      'arch.c2Tag': '免端口 Helper',
      'arch.c2Title': '仅监听回环的 :80 转发',
      'arch.c2Body': '可选 SMAppService LaunchDaemon 仅绑定 127.0.0.1:80 与 [::1]:80 并只转发至 127.0.0.1:17890；未批准或端口被占用时自动退回 :17890。',
      'arch.c3Tag': '安全停止',
      'arch.c3Title': '一次性计划与拒绝策略',
      'arch.c3Body': 'Docker、其他用户、共享 runtime 与归属不明进程一律拒绝；只有明确归属的未托管服务忽略 SIGTERM 时，才会进入 3 秒红色 SIGKILL 确认页。',
      'arch.c4Tag': 'V1.0.6 性能优化',
      'arch.c4Title': '低开销后台扫描',
      'arch.c4Body': '停止对已分类活动监听端口周期性重复 HTTP 探测，对 HTTP 501 进行退避，批量检查进程并将后台刷新节奏降至 5 分钟。',
      'arch.boundTitle': 'v1.0 范围与刻意保持的边界',
      'arch.b1': '支持 macOS 14 Sonoma 及以上系统；公开 Release 构建仅面向 Apple Silicon（arm64）。',
      'arch.b2': '仅在 IPv4/IPv6 loopback 上运行，无账号系统、无遥测、无公网穿透。',
      'arch.b3': '不修改 /etc/hosts、不安装受信任本地根证书、不监听 443 HTTPS 端口。',
      'arch.b4': '默认使用非特权端口 :17890；启用免端口 *.localhost 需在系统设置中批准一次。',
      'inst.heading': '安装、构建与 v1.0.6 更新说明',
      'inst.sub': '可通过 Homebrew Cask 安装、直接下载已签名公证的 Apple Silicon DMG，或使用 Go 与 Xcode Command Line Tools 在本地构建完整应用包。',
      'inst.tablistAria': 'Port Tools 安装方式',
      'inst.tab1': 'Homebrew Cask',
      'inst.tab2': '直接下载 DMG (v1.0.6)',
      'inst.tab3': '从源码构建',
      'inst.tab4': 'v1.0.6 更新日志',
      'inst.barBrew': 'zsh · Homebrew Cask（Apple Silicon · macOS 14+）',
      'inst.barDmg': 'zsh · 已签名并公证的 v1.0.6 DMG（10.1 MiB）',
      'inst.barBuild': 'zsh · 本地构建与校验应用包',
      'inst.codeAriaBrew': 'Homebrew Cask 安装命令',
      'inst.codeAriaDmg': '直接下载 DMG 与 SHA-256 校验命令',
      'inst.codeAriaBuild': '从源码本地构建与校验命令',
      'inst.dlLink': '直接下载 DMG',
      'inst.cBrew1': '# 通过个人 Homebrew tap 安装',
      'inst.cBrew2': '# 后续升级（应用内已集成 Sparkle 更新）',
      'inst.cDmg1': '# 下载 DMG 并校验 SHA-256',
      'inst.cBuild1': '# 校验应用包与运行路径',
      'inst.relTitle': 'Port Tools 1.0.6（2026-11-22 发布）',
      'inst.rel1': '停止对已完成分类的活动监听端口进行周期性 HTTP 重复探测，并对 HTTP 501 响应做退避处理。',
      'inst.rel2': '通过批量进程检查、直连 Unix socket IPC、精简服务清单持久化以及 5 分钟后台刷新节奏，显著降低空闲 CPU 占用、子进程拉起频率、SSD 写入和日志噪声。',
      'inst.rel3': '打磨菜单栏界面对比度、悬停快捷操作、键盘搜索体验及 Docker 服务命名。',
      'inst.relDmg': '下载 v1.0.6 DMG',
      'inst.relAll': '查看全部版本',
      'inst.relFeed': 'Sparkle 更新源',
      'footer.brand': 'Port Tools v1.0.6 · MIT',
      'footer.note': ' — 仅在本机运行。无账号、无遥测、不改 /etc/hosts。',
      'footer.aria': '页脚导航',
      'footer.releases': '版本发布',
      'footer.updates': '更新源',
      'footer.issues': '反馈问题',
      'msg.themeDark': '已切换为深色外观',
      'msg.themeLight': '已切换为浅色外观',
      'msg.langSwitched': '已切换为简体中文',
      'msg.demoReset': '演示已重置',
      'msg.stopped': '{name} 已停止',
      'msg.restarted': '{name} 已重启',
      'msg.forceStopped': '{name} 已强制停止',
      'msg.forceReady': '{name} 现在可以强制停止',
      'msg.sigtermIgnored': '{name} 忽略了 SIGTERM，端口仍在监听',
      'msg.aliasUpdated': '{name} 路由已更新为 {url}',
      'msg.copiedVal': '已复制 {val}',
      'msg.inspecting': '正在查看 {name} 的归属证据',
      'msg.clipboardUnavailable': '剪贴板权限不可用',
      'msg.copyFallbackTitle': '无法自动写入剪贴板，请手动复制：',
      'msg.copyFallbackInputAria': '待手动复制的文本',
      'msg.close': '关闭'
    }
  };

  var INITIAL_SERVICES = [
    {
      id: 'phone3d',
      name: 'Phone 3D UI Studio',
      repo: 'Popcornnnnnnnn/phone-3d-ui-studio',
      branch: 'main',
      alias: 'phone-studio',
      port: 5173,
      pid: 48210,
      ancestry: '48210 (node) ← 48195 (zsh) ← 4102 (Ghostty)',
      cwd: '~/Workspace/phone-3d-ui-studio',
      manifest: 'package.json (Vite · Three.js)',
      bind: '127.0.0.1:5173 (loopback)',
      bindZh: '127.0.0.1:5173（本机回环）',
      probe: '200 OK · text/html · "Phone 3D UI Studio"',
      stopPolicy: 'owned',
      hasSupporting: false
    },
    {
      id: 'reply',
      name: 'Reply Copilot',
      repo: 'Popcornnnnnnnn/reply-copilot',
      branch: 'feature/quick-reply',
      alias: 'reply',
      port: 3000,
      pid: 49104,
      ancestry: '49104 (next-server) ← 49080 (pnpm) ← 4102 (Ghostty)',
      cwd: '~/Workspace/reply-copilot',
      manifest: 'package.json (Next.js)',
      bind: '127.0.0.1:3000 (loopback)',
      bindZh: '127.0.0.1:3000（本机回环）',
      probe: '200 OK · text/html · "Reply Copilot"',
      stopPolicy: 'owned',
      hasSupporting: true
    },
    {
      id: 'ops',
      name: 'Ops Dashboard',
      repo: 'Popcornnnnnnnn/ops-dashboard',
      branch: 'release/v2',
      alias: 'ops',
      port: 4178,
      pid: 51388,
      ancestry: '51388 (ops-web) ← 1 (launchd · unmanaged)',
      ancestryZh: '51388 (ops-web) ← 1 (launchd · 未受托管)',
      cwd: '~/Workspace/ops-dashboard/.worktrees/release-v2',
      manifest: 'go.mod + web/package.json',
      bind: '127.0.0.1:4178 (loopback)',
      bindZh: '127.0.0.1:4178（本机回环）',
      probe: '200 OK · text/html · "Ops Dashboard"',
      stopPolicy: 'ignores-sigterm',
      hasSupporting: false
    },
    {
      id: 'pgadmin',
      name: 'Postgres Admin',
      repo: 'compose/local-stack',
      branch: 'docker',
      alias: 'pg-admin',
      port: 8080,
      pid: 19240,
      ancestry: '19240 (com.docker.backend · published port)',
      ancestryZh: '19240 (com.docker.backend · 容器映射端口)',
      cwd: 'Docker container · dpage/pgadmin4',
      cwdZh: 'Docker 容器 · dpage/pgadmin4',
      manifest: 'docker-compose.yml',
      bind: '0.0.0.0:8080 (all interfaces / LAN)',
      bindZh: '0.0.0.0:8080（全部网卡 / 局域网）',
      probe: '200 OK · text/html · "pgAdmin 4"',
      stopPolicy: 'refused-docker',
      hasSupporting: false
    },
    {
      id: 'api',
      name: 'API Playground',
      repo: 'Popcornnnnnnnn/api-playground',
      branch: 'dev',
      alias: 'api-playground',
      port: 8000,
      pid: 53012,
      ancestry: '53012 (uvicorn) ← 52990 (uv) ← 4102 (Ghostty)',
      cwd: '~/Workspace/api-playground',
      manifest: 'pyproject.toml (FastAPI)',
      bind: '127.0.0.1:8000 (loopback)',
      bindZh: '127.0.0.1:8000（本机回环）',
      probe: '200 OK · text/html · "API Playground — Swagger UI"',
      stopPolicy: 'owned',
      hasSupporting: false
    }
  ];

  var state = {
    lang: document.documentElement.lang === 'zh-Hans' ? 'zh-Hans' : 'en',
    helperEnabled: true,
    query: '',
    selectedId: 'phone3d',
    inspectorMode: 'inspect',
    editingId: null,
    renameDraft: null,
    renameError: null,
    supportExpanded: false,
    forceSeconds: 0,
    forceTimer: null,
    stopAttemptSeq: 0,
    demoSessionSeq: 0,
    stopTargetId: null,
    stopOpenerSelector: null,
    copyFallbackText: null,
    copyFallbackOpener: null,
    services: cloneServices()
  };

  var copyResetTimers = typeof WeakMap === 'function' ? new WeakMap() : null;

  function cloneServices() {
    return INITIAL_SERVICES.map(function (s) {
      return {
        id: s.id,
        name: s.name,
        repo: s.repo,
        branch: s.branch,
        alias: s.alias,
        port: s.port,
        pid: s.pid,
        ancestry: s.ancestry,
        ancestryZh: s.ancestryZh || null,
        cwd: s.cwd,
        cwdZh: s.cwdZh || null,
        manifest: s.manifest,
        bind: s.bind,
        bindZh: s.bindZh || null,
        probe: s.probe,
        stopPolicy: s.stopPolicy,
        hasSupporting: s.hasSupporting,
        stopped: false,
        stopping: false,
        stopTimer: null,
        stopLog: []
      };
    });
  }

  function serviceField(svc, field) {
    if (state.lang === 'zh-Hans' && svc[field + 'Zh']) return svc[field + 'Zh'];
    return svc[field];
  }

  function t(key, vars) {
    var dict = I18N[state.lang] || I18N.en;
    var val = Object.prototype.hasOwnProperty.call(dict, key) ? dict[key] : (I18N.en[key] || key);
    if (vars) {
      Object.keys(vars).forEach(function (k) {
        val = val.replace(new RegExp('\\{' + k + '\\}', 'g'), String(vars[k]));
      });
    }
    return val;
  }

  function formatSummary(projects, apps) {
    if (state.lang === 'zh-Hans') {
      return projects + ' 个项目 · ' + apps + ' 个 Web 应用';
    }
    var pUnit = projects === 1 ? 'project' : 'projects';
    var aUnit = apps === 1 ? 'Web app' : 'Web apps';
    return projects + ' ' + pUnit + ' · ' + apps + ' ' + aUnit;
  }

  function routeUrl(svc) {
    return 'http://' + svc.alias + '.localhost' + (state.helperEnabled ? '' : ':17890');
  }

  function announce(msg) {
    var region = document.getElementById('live-status');
    if (!region) return;
    region.textContent = '';
    window.setTimeout(function () {
      region.textContent = msg;
    }, 20);
  }

  function restoreButtonLabel(btn, prev) {
    if (copyResetTimers && copyResetTimers.has(btn)) {
      window.clearTimeout(copyResetTimers.get(btn));
      copyResetTimers.delete(btn);
    }
    var timerId = window.setTimeout(function () {
      if (copyResetTimers) copyResetTimers.delete(btn);
      if (btn.getAttribute('data-i18n')) {
        btn.textContent = t(btn.getAttribute('data-i18n'));
      } else {
        btn.textContent = prev;
      }
    }, 1500);
    if (copyResetTimers) copyResetTimers.set(btn, timerId);
  }

  function isFocusableVisible(el) {
    if (!el || !el.isConnected || el.disabled || typeof el.focus !== 'function') return false;
    if (typeof el.closest === 'function' && el.closest('[hidden]')) return false;
    return true;
  }

  function describeCopyOpener(btn) {
    if (!btn) return null;
    var selector = null;
    var fallback = '#wb-search';
    var copyTarget = typeof btn.getAttribute === 'function' ? btn.getAttribute('data-copy-target') : null;
    if (copyTarget) {
      selector = '[data-copy-target="' + copyTarget + '"]';
      fallback = copyTarget === 'brew-hero-cmd'
        ? '#main-content'
        : '#install [role="tab"][aria-selected="true"]';
    } else if (typeof btn.closest === 'function') {
      var insRoot = btn.closest('#wb-inspector');
      var act = typeof btn.getAttribute === 'function' ? btn.getAttribute('data-action') : null;
      if (insRoot && act) {
        selector = '#wb-inspector [data-action="' + act + '"]';
        fallback = '#wb-inspector-heading';
      } else {
        var rowCard = btn.closest('[data-svc-id]');
        if (rowCard && act) {
          var sid = rowCard.getAttribute('data-svc-id');
          if (sid) {
            selector = '[data-svc-id="' + sid + '"] [data-action="' + act + '"]';
            fallback = '#wb-search';
          }
        }
      }
    }
    return { el: btn, selector: selector, fallback: fallback };
  }

  function hideCopyFallback(restoreFocus) {
    var box = document.getElementById('copy-fallback');
    var opener = state.copyFallbackOpener;
    state.copyFallbackText = null;
    state.copyFallbackOpener = null;
    if (box) {
      box.hidden = true;
      box.removeAttribute('aria-labelledby');
      box.replaceChildren();
    }
    if (!restoreFocus) return;
    var target = null;
    if (opener) {
      if (isFocusableVisible(opener.el)) {
        target = opener.el;
      } else if (opener.selector) {
        var reQueried = document.querySelector(opener.selector);
        if (isFocusableVisible(reQueried)) target = reQueried;
      }
      if (!target && opener.fallback) {
        var fbEl = document.querySelector(opener.fallback);
        if (isFocusableVisible(fbEl)) target = fbEl;
      }
    }
    if (!target) {
      var searchFallback = document.getElementById('wb-search');
      if (isFocusableVisible(searchFallback)) target = searchFallback;
    }
    if (target) target.focus();
  }

  function showCopyFallback(text, openerBtn, preserveFocus) {
    var box = document.getElementById('copy-fallback');
    if (!box) return;
    state.copyFallbackText = text;
    if (openerBtn !== undefined && openerBtn !== null) {
      state.copyFallbackOpener = describeCopyOpener(openerBtn);
    }

    if (preserveFocus && !box.hidden) {
      var existingTitle = document.getElementById('copy-fallback-title');
      var existingInp = box.querySelector('.copy-fallback-input');
      var existingClose = box.querySelector('.copy-fallback-close');
      if (existingTitle && existingInp && existingClose) {
        existingTitle.textContent = t('msg.copyFallbackTitle');
        existingClose.textContent = t('msg.close');
        existingInp.setAttribute('aria-label', t('msg.copyFallbackInputAria'));
        if (existingInp.value !== text) existingInp.value = text;
        return;
      }
    }

    box.replaceChildren();

    var titleSpan = createEl('span', 'copy-fallback-title', t('msg.copyFallbackTitle'));
    titleSpan.id = 'copy-fallback-title';
    box.appendChild(titleSpan);

    var inp = createEl('textarea', 'copy-fallback-input');
    inp.readOnly = true;
    inp.value = text;
    var lines = String(text).split('\n').length;
    inp.rows = Math.min(6, Math.max(2, lines));
    inp.setAttribute('aria-label', t('msg.copyFallbackInputAria'));
    inp.addEventListener('focus', function () {
      inp.select();
    });
    box.appendChild(inp);

    var closeBtn = createEl('button', 'row-btn copy-fallback-close', t('msg.close'));
    closeBtn.type = 'button';
    closeBtn.addEventListener('click', function () {
      hideCopyFallback(true);
    });
    box.appendChild(closeBtn);

    box.setAttribute('aria-labelledby', 'copy-fallback-title');
    box.hidden = false;
    if (!preserveFocus) {
      inp.focus();
      inp.select();
    }
  }

  function legacyExecCopy(text) {
    if (typeof document.execCommand !== 'function') return false;
    var prevFocus = document.activeElement;
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.setAttribute('aria-hidden', 'true');
    ta.tabIndex = -1;
    ta.className = 'copy-scratch';
    document.body.appendChild(ta);
    var ok = false;
    try {
      ta.focus({ preventScroll: true });
      ta.select();
      ok = document.execCommand('copy');
    } catch (e) {
      ok = false;
    } finally {
      document.body.removeChild(ta);
      if (prevFocus && prevFocus.isConnected && typeof prevFocus.focus === 'function') {
        prevFocus.focus({ preventScroll: true });
      }
    }
    return ok;
  }

  function copyText(text, btn, restoreText) {
    var prev = restoreText || btn.textContent;
    function onCopied() {
      hideCopyFallback(false);
      btn.textContent = t('common.copied');
      announce(t('msg.copiedVal', { val: text }));
      restoreButtonLabel(btn, prev);
    }
    function onFailed() {
      if (legacyExecCopy(text)) {
        onCopied();
        return;
      }
      btn.textContent = t('common.copyFailed');
      restoreButtonLabel(btn, prev);
      announce(t('msg.clipboardUnavailable'));
      showCopyFallback(text, btn, false);
    }
    if (!navigator.clipboard || typeof navigator.clipboard.writeText !== 'function') {
      onFailed();
      return;
    }
    try {
      navigator.clipboard.writeText(text).then(onCopied).catch(onFailed);
    } catch (e) {
      onFailed();
    }
  }

  function clearForceTimer() {
    if (state.forceTimer) {
      window.clearInterval(state.forceTimer);
      state.forceTimer = null;
    }
  }

  function clearAllPendingStops() {
    state.demoSessionSeq += 1;
    state.services.forEach(function (svc) {
      if (svc.stopTimer) {
        window.clearTimeout(svc.stopTimer);
        svc.stopTimer = null;
      }
      svc.stopping = false;
      svc.stopLog = [];
    });
  }

  function cancelStopFlow() {
    clearForceTimer();
    state.stopAttemptSeq += 1;
    state.stopTargetId = null;
    state.forceSeconds = 0;
    state.inspectorMode = 'inspect';
  }

  function dismissStopReview() {
    if (state.inspectorMode === 'stopping') return;
    var restore = state.stopOpenerSelector;
    var svc = selectedService();
    cancelStopFlow();
    renderWorkbench(restore || (svc ? '[data-svc-id="' + svc.id + '"] [data-action="select"]' : null));
  }

  function focusSelector(selector, opts) {
    var el = selector ? document.querySelector(selector) : null;
    if (el && typeof el.focus === 'function') {
      if (opts) el.focus(opts);
      else el.focus();
    }
  }

  function initThemeToggle() {
    var btn = document.getElementById('theme-toggle');
    var meta = document.querySelector('meta[name="color-scheme"]');
    if (!btn) return;
    var mq = window.matchMedia('(prefers-color-scheme: dark)');

    function currentTheme() {
      var explicit = document.documentElement.dataset.theme;
      if (explicit === 'light' || explicit === 'dark') return explicit;
      return mq.matches ? 'dark' : 'light';
    }

    btn.addEventListener('click', function () {
      var sys = mq.matches ? 'dark' : 'light';
      var next = currentTheme() === 'dark' ? 'light' : 'dark';
      try {
        if (next !== sys) {
          localStorage.setItem('port-tools.theme', next);
          document.documentElement.dataset.theme = next;
          if (meta) meta.content = next;
        } else {
          localStorage.removeItem('port-tools.theme');
          delete document.documentElement.dataset.theme;
          if (meta) meta.content = 'light dark';
        }
      } catch (e) {
        document.documentElement.dataset.theme = next;
        if (meta) meta.content = next;
      }
      announce(t(next === 'dark' ? 'msg.themeDark' : 'msg.themeLight'));
    });
  }

  function applyLanguage(lang) {
    state.lang = lang === 'zh-Hans' ? 'zh-Hans' : 'en';
    document.documentElement.lang = state.lang;
    document.title = t('meta.title');

    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-i18n');
      if (key) el.textContent = t(key);
    });
    document.querySelectorAll('[data-i18n-aria]').forEach(function (el) {
      var key = el.getAttribute('data-i18n-aria');
      if (key) el.setAttribute('aria-label', t(key));
    });
    document.querySelectorAll('[data-i18n-alt]').forEach(function (el) {
      var key = el.getAttribute('data-i18n-alt');
      if (key) el.setAttribute('alt', t(key));
    });
    document.querySelectorAll('[data-col-key]').forEach(function (el) {
      var key = el.getAttribute('data-col-key');
      if (key) el.setAttribute('data-col-label', t(key));
    });

    var searchInput = document.getElementById('wb-search');
    if (searchInput) searchInput.placeholder = t('wb.searchPlaceholder');

    var inspectorEl = document.getElementById('wb-inspector');
    var focusInInspector = Boolean(inspectorEl && document.activeElement && inspectorEl.contains(document.activeElement));

    syncHelperControls();
    renderWorkbench();
    if (focusInInspector) {
      focusSelector(state.inspectorMode !== 'inspect' ? '#wb-sheet-title' : '#wb-inspector-heading', { preventScroll: true });
    }
    if (state.copyFallbackText !== null) {
      showCopyFallback(state.copyFallbackText, null, true);
    }
  }

  function initLanguageToggle() {
    var btn = document.getElementById('lang-toggle');
    applyLanguage(state.lang);
    if (!btn) return;
    btn.addEventListener('click', function () {
      var next = state.lang === 'zh-Hans' ? 'en' : 'zh-Hans';
      try {
        localStorage.setItem('port-tools.lang', next);
      } catch (e) {}
      applyLanguage(next);
      announce(t('msg.langSwitched'));
    });
  }

  function initHeroStage() {
    var frame = document.getElementById('hero-shot-frame');
    var btns = Array.prototype.slice.call(document.querySelectorAll('[data-shot-btn]'));
    if (!frame || !btns.length) return;
    var lightFig = frame.querySelector('.shot-light');
    var darkFig = frame.querySelector('.shot-dark');

    function setMode(mode) {
      frame.setAttribute('data-shot-mode', mode);
      frame.classList.toggle('is-compare', mode === 'compare');
      if (mode === 'light') {
        lightFig.hidden = false;
        darkFig.hidden = true;
      } else if (mode === 'dark') {
        lightFig.hidden = true;
        darkFig.hidden = false;
      } else {
        lightFig.hidden = false;
        darkFig.hidden = false;
      }
      btns.forEach(function (b) {
        b.setAttribute('aria-pressed', b.getAttribute('data-shot-btn') === mode ? 'true' : 'false');
      });
    }

    btns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        setMode(btn.getAttribute('data-shot-btn') || 'auto');
      });
    });
    setMode('auto');
  }

  function initTabs() {
    document.querySelectorAll('[data-tabs-widget]').forEach(function (widget) {
      var tabs = Array.prototype.slice.call(widget.querySelectorAll('[role="tab"]'));
      var panels = Array.prototype.slice.call(widget.querySelectorAll('[role="tabpanel"]'));

      function selectTab(targetTab, focusTab) {
        if (!targetTab) return;
        tabs.forEach(function (tab) {
          var isSel = tab === targetTab;
          tab.setAttribute('aria-selected', isSel ? 'true' : 'false');
          tab.tabIndex = isSel ? 0 : -1;
        });
        panels.forEach(function (panel) {
          var match = panel.getAttribute('aria-labelledby') === targetTab.id;
          if (match) {
            panel.removeAttribute('hidden');
            if (panel.id === 'inst-panel-notes') {
              panel.tabIndex = 0;
            } else {
              panel.removeAttribute('tabindex');
            }
          } else {
            panel.setAttribute('hidden', 'until-found');
            panel.removeAttribute('tabindex');
          }
        });
        if (focusTab) targetTab.focus();
      }

      tabs.forEach(function (tab, idx) {
        tab.addEventListener('click', function () {
          selectTab(tab, false);
        });
        tab.addEventListener('keydown', function (ev) {
          var nextIdx = -1;
          if (ev.key === 'ArrowRight') nextIdx = (idx + 1) % tabs.length;
          else if (ev.key === 'ArrowLeft') nextIdx = (idx - 1 + tabs.length) % tabs.length;
          else if (ev.key === 'Home') nextIdx = 0;
          else if (ev.key === 'End') nextIdx = tabs.length - 1;
          if (nextIdx >= 0) {
            ev.preventDefault();
            selectTab(tabs[nextIdx], true);
          }
        });
      });

      panels.forEach(function (panel) {
        panel.addEventListener('beforematch', function () {
          var owner = tabs.find(function (tab) {
            return tab.id === panel.getAttribute('aria-labelledby');
          });
          if (owner) selectTab(owner, false);
        });
      });
    });
  }

  function extractCommandText(el) {
    var clone = el.cloneNode(true);
    clone.querySelectorAll('.code-comment').forEach(function (node) {
      node.remove();
    });
    return (clone.textContent || '')
      .split('\n')
      .map(function (line) { return line.replace(/\s+$/, ''); })
      .filter(function (line, idx, arr) {
        if (line.trim() !== '') return true;
        return idx > 0 && idx < arr.length - 1 && arr[idx - 1].trim() !== '';
      })
      .join('\n')
      .trim();
  }

  function initStaticCopyButtons() {
    document.querySelectorAll('[data-copy-target]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var id = btn.getAttribute('data-copy-target');
        var el = id ? document.getElementById(id) : null;
        if (!el) return;
        copyText(extractCommandText(el), btn);
      });
    });
  }

  function syncHelperControls() {
    var statusEl = document.getElementById('wb-helper-status');
    var toggleEl = document.getElementById('wb-helper-toggle');
    if (statusEl) statusEl.textContent = t(state.helperEnabled ? 'wb.helperOn' : 'wb.helperOff');
    if (toggleEl) {
      toggleEl.setAttribute('aria-pressed', state.helperEnabled ? 'true' : 'false');
      toggleEl.textContent = t(state.helperEnabled ? 'wb.helperBtnOn' : 'wb.helperBtnOff');
    }
  }

  function createEl(tag, className, text) {
    var el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function filteredServices() {
    var q = state.query.trim().toLowerCase();
    if (!q) return state.services;
    return state.services.filter(function (s) {
      var hay = [s.name, s.repo, s.branch, s.alias, String(s.port), s.manifest].join(' ').toLowerCase();
      return hay.indexOf(q) !== -1;
    });
  }

  function selectedService() {
    var found = state.services.find(function (s) { return s.id === state.selectedId; });
    return found || state.services[0];
  }

  function reconcileVisibleSelection() {
    var vis = filteredServices();
    var prevSelected = state.selectedId;
    if (vis.length && !vis.some(function (s) { return s.id === state.selectedId; })) {
      state.selectedId = vis[0].id;
    }
    if (state.inspectorMode !== 'inspect' && (!vis.length || !vis.some(function (s) { return s.id === state.stopTargetId; }) || state.stopTargetId !== state.selectedId || prevSelected !== state.selectedId)) {
      cancelStopFlow();
    }
    if (state.editingId && !vis.some(function (s) { return s.id === state.editingId; })) {
      state.editingId = null;
      state.renameDraft = null;
      state.renameError = null;
    }
    return vis;
  }

  function isStackedWorkbench() {
    var shell = document.querySelector('.wb-shell');
    return !shell || shell.clientWidth < 860;
  }

  function revealInspectorOnStacked() {
    if (!isStackedWorkbench()) return false;
    var card = document.getElementById('wb-inspector');
    var heading = document.getElementById('wb-inspector-heading');
    if (card && typeof card.scrollIntoView === 'function') {
      var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      card.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' });
    }
    if (heading && typeof heading.focus === 'function') {
      heading.focus({ preventScroll: true });
    }
    return true;
  }

  function initMobileNavMenu() {
    var menu = document.getElementById('mobile-nav');
    if (!menu) return;
    menu.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        menu.open = false;
      });
    });
    document.addEventListener('click', function (ev) {
      if (menu.open && !menu.contains(ev.target)) {
        menu.open = false;
      }
    });
    document.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape' && menu.open) {
        ev.preventDefault();
        ev.stopPropagation();
        menu.open = false;
        var summary = menu.querySelector('summary');
        if (summary && typeof summary.focus === 'function') summary.focus();
      }
    });
    menu.addEventListener('focusout', function (ev) {
      if (!menu.open) return;
      if (ev.relatedTarget && !menu.contains(ev.relatedTarget)) {
        menu.open = false;
      }
    });
  }

  function startStopFlow(svc, openerSelector) {
    cancelStopFlow();
    state.selectedId = svc.id;
    state.editingId = null;
    state.renameDraft = null;
    state.renameError = null;
    if (svc.stopping) {
      state.stopTargetId = svc.id;
      state.stopOpenerSelector = openerSelector || ('[data-svc-id="' + svc.id + '"] [data-action="select"]');
      state.inspectorMode = 'stopping';
      var stackedBusy = isStackedWorkbench();
      renderWorkbench();
      focusSelector('#wb-inspector #wb-sheet-title', { preventScroll: stackedBusy });
      return;
    }
    if (svc.stopped) {
      svc.stopped = false;
      svc.stopLog = [];
      state.stopOpenerSelector = null;
      announce(t('msg.restarted', { name: svc.name }));
      renderWorkbench(openerSelector || '[data-svc-id="' + svc.id + '"] [data-action="stop"]');
      return;
    }
    svc.stopLog = [];
    state.stopTargetId = svc.id;
    state.stopOpenerSelector = openerSelector || ('[data-svc-id="' + svc.id + '"] [data-action="stop"]');
    state.inspectorMode = svc.stopPolicy === 'refused-docker' ? 'refused' : 'confirm-stop';
    var stacked = isStackedWorkbench();
    renderWorkbench();
    focusSelector('#wb-inspector #wb-sheet-title', { preventScroll: stacked });
    if (stacked) {
      var card = document.getElementById('wb-inspector');
      if (card && typeof card.scrollIntoView === 'function') {
        var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        card.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' });
      }
    }
  }

  function updateForceCountdownButton() {
    var forceBtn = document.getElementById('wb-force-btn');
    if (!forceBtn) return;
    if (state.forceSeconds > 0) {
      forceBtn.textContent = t('ins.forceCountdown', { n: state.forceSeconds });
      forceBtn.disabled = true;
    } else {
      forceBtn.textContent = t('ins.forceNow');
      forceBtn.disabled = false;
    }
  }

  function executeSigtermStop(svc) {
    if (!svc || svc.id !== state.stopTargetId || svc.stopPolicy === 'refused-docker' || svc.stopped || svc.stopping) {
      return;
    }
    clearForceTimer();
    var sessionSeq = state.demoSessionSeq;
    var targetId = svc.id;
    svc.stopping = true;
    state.inspectorMode = 'stopping';
    svc.stopLog = [
      { key: 'ins.stopLog1', vars: { pid: svc.pid, port: svc.port } },
      { key: 'ins.stopLog2', vars: { pid: svc.pid, port: svc.port } }
    ];
    renderWorkbench();
    focusSelector('#wb-sheet-title', { preventScroll: true });

    svc.stopTimer = window.setTimeout(function () {
      svc.stopTimer = null;
      if (sessionSeq !== state.demoSessionSeq || !svc.stopping || svc.stopped || svc.stopPolicy === 'refused-docker') {
        svc.stopping = false;
        return;
      }
      svc.stopping = false;
      var vis = filteredServices();
      var isViewing = state.selectedId === targetId && vis.some(function (item) { return item.id === targetId; });

      if (svc.stopPolicy === 'ignores-sigterm') {
        svc.stopLog = svc.stopLog.concat([{ key: 'ins.stopLogFail', vars: { pid: svc.pid, port: svc.port } }]);
        if (isViewing) {
          state.stopAttemptSeq += 1;
          var attempt = state.stopAttemptSeq;
          state.stopTargetId = targetId;
          state.inspectorMode = 'force-stop';
          state.forceSeconds = 3;
          renderWorkbench();
          focusSelector('#wb-sheet-title', { preventScroll: true });
          state.forceTimer = window.setInterval(function () {
            if (attempt !== state.stopAttemptSeq || state.stopTargetId !== targetId || state.inspectorMode !== 'force-stop') {
              clearForceTimer();
              return;
            }
            state.forceSeconds -= 1;
            if (state.forceSeconds <= 0) {
              state.forceSeconds = 0;
              clearForceTimer();
              updateForceCountdownButton();
              announce(t('msg.forceReady', { name: svc.name }));
            } else {
              updateForceCountdownButton();
            }
          }, 1000);
        } else {
          announce(t('msg.sigtermIgnored', { name: svc.name }));
          renderWorkbench();
        }
      } else {
        svc.stopped = true;
        svc.stopLog = svc.stopLog.concat([{ key: 'ins.stopLog3', vars: { pid: svc.pid, port: svc.port } }]);
        announce(t('msg.stopped', { name: svc.name }));
        if (isViewing && state.stopTargetId === targetId) {
          cancelStopFlow();
          state.stopOpenerSelector = null;
          renderWorkbench('#wb-inspector-heading');
        } else {
          renderWorkbench();
        }
      }
    }, 350);
  }

  function executeForceKill(svc) {
    if (!svc || state.inspectorMode !== 'force-stop' || state.forceSeconds > 0 || svc.id !== state.stopTargetId || svc.stopPolicy === 'refused-docker' || svc.stopped) {
      return;
    }
    svc.stopped = true;
    svc.stopLog = [{ key: 'ins.forceDone', vars: { pid: svc.pid, port: svc.port } }];
    cancelStopFlow();
    state.stopOpenerSelector = null;
    announce(t('msg.forceStopped', { name: svc.name }));
    renderWorkbench('#wb-inspector-heading');
  }

  function renderServiceList(restoreFocusSelector) {
    var listEl = document.getElementById('wb-list');
    var emptyEl = document.getElementById('wb-empty');
    var summaryEl = document.getElementById('wb-summary');
    if (!listEl) return;
    listEl.replaceChildren();

    var visible = filteredServices();
    var activeCount = visible.filter(function (s) { return !s.stopped; }).length;
    if (summaryEl) {
      summaryEl.textContent = formatSummary(visible.length, activeCount);
    }

    if (!visible.length) {
      listEl.hidden = true;
      if (emptyEl) {
        emptyEl.textContent = t('wb.empty');
        emptyEl.hidden = false;
      }
      return;
    }
    listEl.hidden = false;
    if (emptyEl) {
      emptyEl.textContent = '';
      emptyEl.hidden = true;
    }

    visible.forEach(function (svc) {
      var isSelected = svc.id === state.selectedId;
      var card = createEl('div', 'svc-card' + (isSelected ? ' is-selected' : '') + (svc.stopped ? ' is-stopped' : ''));
      card.setAttribute('role', 'listitem');
      card.setAttribute('data-svc-id', svc.id);

      var head = createEl('div', 'svc-head');
      var titleGroup = createEl('div', 'svc-title-group');
      var namePair = createEl('span', 'svc-name-pair');

      var nameBtn = createEl('button', 'svc-name-btn', svc.name);
      nameBtn.type = 'button';
      nameBtn.setAttribute('data-action', 'select');
      if (isSelected) nameBtn.setAttribute('aria-current', 'true');
      nameBtn.addEventListener('click', function () {
        cancelStopFlow();
        state.selectedId = svc.id;
        announce(t('msg.inspecting', { name: svc.name }));
        renderWorkbench('[data-svc-id="' + svc.id + '"] [data-action="select"]');
        revealInspectorOnStacked();
      });
      namePair.appendChild(nameBtn);

      var shield = createEl('span', 'shield-dot' + (svc.stopped ? ' is-stopped' : (svc.stopPolicy === 'refused-docker' ? ' is-warn' : '')), svc.stopped ? '–' : (svc.stopPolicy === 'refused-docker' ? '!' : '✓'));
      shield.setAttribute('aria-hidden', 'true');
      namePair.appendChild(shield);
      if (svc.stopped) {
        namePair.appendChild(createEl('span', 'visually-hidden', t('wb.shieldStoppedSr')));
      } else if (svc.stopPolicy === 'refused-docker') {
        namePair.appendChild(createEl('span', 'visually-hidden', t('wb.shieldDockerSr')));
      }
      titleGroup.appendChild(namePair);

      if (svc.hasSupporting && !svc.stopped) {
        var supBtn = createEl('button', 'support-pill', t('wb.supportToggle'));
        supBtn.type = 'button';
        supBtn.setAttribute('data-action', 'support');
        supBtn.setAttribute('aria-label', t('wb.supportAria', { name: svc.name }));
        supBtn.setAttribute('aria-controls', 'wb-support-' + svc.id);
        supBtn.setAttribute('aria-expanded', state.supportExpanded ? 'true' : 'false');
        supBtn.addEventListener('click', function () {
          state.supportExpanded = !state.supportExpanded;
          renderServiceList('[data-svc-id="' + svc.id + '"] [data-action="support"]');
        });
        titleGroup.appendChild(supBtn);
      }

      head.appendChild(titleGroup);

      var actions = createEl('div', 'svc-actions');
      if (isSelected) {
        var selectedBtn = createEl('button', 'selected-tag', t('wb.selected'));
        selectedBtn.type = 'button';
        selectedBtn.setAttribute('data-action', 'inspect');
        selectedBtn.setAttribute('aria-label', t('wb.selectedAria', { name: svc.name }));
        selectedBtn.addEventListener('click', function () {
          cancelStopFlow();
          announce(t('msg.inspecting', { name: svc.name }));
          renderWorkbench();
          focusSelector('#wb-inspector-heading', { preventScroll: isStackedWorkbench() });
          revealInspectorOnStacked();
        });
        actions.appendChild(selectedBtn);
      } else {
        var inspectBtn = createEl('button', 'row-btn', t('wb.inspect'));
        inspectBtn.type = 'button';
        inspectBtn.setAttribute('data-action', 'inspect');
        inspectBtn.setAttribute('aria-label', t('wb.inspectAria', { name: svc.name }));
        inspectBtn.addEventListener('click', function () {
          cancelStopFlow();
          state.selectedId = svc.id;
          announce(t('msg.inspecting', { name: svc.name }));
          renderWorkbench();
          focusSelector('#wb-inspector-heading', { preventScroll: isStackedWorkbench() });
          revealInspectorOnStacked();
        });
        actions.appendChild(inspectBtn);
      }

      var stopBtn = createEl('button', 'row-btn' + (svc.stopped ? '' : ' is-danger'), t(svc.stopped ? 'wb.restart' : 'wb.stop'));
      stopBtn.type = 'button';
      stopBtn.setAttribute('data-action', 'stop');
      stopBtn.setAttribute('aria-label', t(svc.stopped ? 'wb.restartAria' : 'wb.stopAria', { name: svc.name }));
      stopBtn.disabled = Boolean(svc.stopping);
      stopBtn.addEventListener('click', function () {
        startStopFlow(svc, '[data-svc-id="' + svc.id + '"] [data-action="stop"]');
      });
      actions.appendChild(stopBtn);
      head.appendChild(actions);
      card.appendChild(head);

      var gitLine = createEl('div', 'svc-git');
      gitLine.appendChild(createEl('span', 'svc-git-repo', '⑂ ' + svc.branch + ' · ' + svc.repo));
      var gitSep = createEl('span', 'svc-git-sep', '·');
      gitSep.setAttribute('aria-hidden', 'true');
      gitLine.appendChild(gitSep);
      gitLine.appendChild(createEl('span', 'svc-git-port', ':' + svc.port));
      card.appendChild(gitLine);

      if (svc.stopped) {
        card.appendChild(createEl('div', 'svc-route-row', t('wb.stoppedLabel')));
      } else {
        var routeRow = createEl('div', 'svc-route-row');
        var urlText = routeUrl(svc);
        var routeSpan = createEl('span', 'svc-route', urlText);
        routeRow.appendChild(routeSpan);

        var routeActions = createEl('div', 'svc-route-actions');
        var copyBtn = createEl('button', 'row-btn', t('common.copy'));
        copyBtn.type = 'button';
        copyBtn.setAttribute('data-action', 'copy');
        copyBtn.setAttribute('aria-label', t('wb.copyRouteAria', { name: svc.name }));
        copyBtn.addEventListener('click', function () {
          copyText(urlText, copyBtn, t('common.copy'));
        });
        routeActions.appendChild(copyBtn);

        var renameBtn = createEl('button', 'row-btn', t('wb.rename'));
        renameBtn.type = 'button';
        renameBtn.setAttribute('data-action', 'rename');
        renameBtn.setAttribute('aria-expanded', state.editingId === svc.id ? 'true' : 'false');
        renameBtn.setAttribute('aria-label', t('wb.renameAria', { name: svc.name }));
        if (state.editingId === svc.id) {
          renameBtn.setAttribute('aria-controls', 'wb-edit-' + svc.id);
        }
        renameBtn.addEventListener('click', function () {
          if (state.editingId === svc.id) {
            state.editingId = null;
            state.renameDraft = null;
            state.renameError = null;
            renderServiceList('[data-svc-id="' + svc.id + '"] [data-action="rename"]');
          } else {
            state.editingId = svc.id;
            state.renameDraft = svc.alias;
            state.renameError = null;
            renderServiceList('[data-svc-id="' + svc.id + '"] .inline-edit-input');
          }
        });
        routeActions.appendChild(renameBtn);
        routeRow.appendChild(routeActions);
        card.appendChild(routeRow);

        if (state.editingId === svc.id) {
          var editRow = createEl('form', 'inline-edit-row');
          editRow.id = 'wb-edit-' + svc.id;
          var input = createEl('input', 'inline-edit-input');
          input.type = 'text';
          input.value = state.renameDraft !== null ? state.renameDraft : svc.alias;
          input.setAttribute('aria-label', t('wb.aliasInputAria', { name: svc.name }));
          if (state.renameError) {
            input.setAttribute('aria-invalid', 'true');
            input.setAttribute('aria-describedby', 'wb-rename-err');
          }
          input.addEventListener('input', function () {
            state.renameDraft = input.value;
            if (state.renameError) {
              state.renameError = null;
              input.removeAttribute('aria-invalid');
              input.removeAttribute('aria-describedby');
              var existingErr = document.getElementById('wb-rename-err');
              if (existingErr) existingErr.remove();
            }
          });
          editRow.addEventListener('keydown', function (ev) {
            if (ev.key !== 'Escape') return;
            ev.preventDefault();
            ev.stopPropagation();
            state.editingId = null;
            state.renameDraft = null;
            state.renameError = null;
            renderServiceList('[data-svc-id="' + svc.id + '"] [data-action="rename"]');
          });
          editRow.appendChild(input);

          var saveBtn = createEl('button', 'row-btn', t('wb.save'));
          saveBtn.type = 'submit';
          editRow.appendChild(saveBtn);

          var cancelBtn = createEl('button', 'row-btn', t('wb.cancel'));
          cancelBtn.type = 'button';
          cancelBtn.addEventListener('click', function () {
            state.editingId = null;
            state.renameDraft = null;
            state.renameError = null;
            renderServiceList('[data-svc-id="' + svc.id + '"] [data-action="rename"]');
          });
          editRow.appendChild(cancelBtn);

          editRow.addEventListener('submit', function (ev) {
            ev.preventDefault();
            var nextAlias = input.value.trim().toLowerCase();
            state.renameDraft = input.value;
            if (!/^[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?$/.test(nextAlias)) {
              state.renameError = { key: 'wb.aliasError' };
              renderServiceList('[data-svc-id="' + svc.id + '"] .inline-edit-input');
              return;
            }
            var dup = state.services.some(function (other) {
              return other.id !== svc.id && other.alias === nextAlias;
            });
            if (dup) {
              state.renameError = { key: 'wb.aliasDup' };
              renderServiceList('[data-svc-id="' + svc.id + '"] .inline-edit-input');
              return;
            }
            svc.alias = nextAlias;
            state.editingId = null;
            state.renameDraft = null;
            state.renameError = null;
            var visAfterRename = reconcileVisibleSelection();
            var stillVisible = visAfterRename.some(function (item) { return item.id === svc.id; });
            announce(t('msg.aliasUpdated', { name: svc.name, url: routeUrl(svc) }));
            renderWorkbench(stillVisible ? '[data-svc-id="' + svc.id + '"] [data-action="rename"]' : '#wb-search');
            if (!stillVisible) focusSelector('#wb-search');
          });
          card.appendChild(editRow);

          if (state.renameError) {
            var errEl = createEl('div', 'inline-error', t(state.renameError.key));
            errEl.id = 'wb-rename-err';
            errEl.setAttribute('role', 'alert');
            card.appendChild(errEl);
          }
        }

        if (svc.hasSupporting && state.supportExpanded) {
          var drawer = createEl('div', 'support-drawer', t('wb.supportDetail'));
          drawer.id = 'wb-support-' + svc.id;
          card.appendChild(drawer);
        }
      }

      listEl.appendChild(card);
    });

    if (restoreFocusSelector) {
      focusSelector(restoreFocusSelector);
    }
  }

  function addEvidenceRow(grid, label, value, mono) {
    var row = createEl('div', 'evidence-row');
    row.appendChild(createEl('span', 'evidence-label', label));
    row.appendChild(createEl('span', 'evidence-val' + (mono ? ' mono' : ''), value));
    grid.appendChild(row);
  }

  function renderInspector() {
    var root = document.getElementById('wb-inspector');
    if (!root) return;
    root.replaceChildren();

    var visible = filteredServices();
    if (!visible.length) {
      var emptyHead = createEl('div', 'inspector-head');
      var emptyBox = createEl('div');
      emptyBox.appendChild(createEl('div', 'inspector-kicker', t('ins.kicker')));
      var emptyH3 = createEl('h3', '', t('ins.emptyTitle'));
      emptyH3.id = 'wb-inspector-heading';
      emptyH3.tabIndex = -1;
      emptyBox.appendChild(emptyH3);
      emptyHead.appendChild(emptyBox);
      root.appendChild(emptyHead);

      var emptySheet = createEl('div', 'stop-sheet');
      emptySheet.setAttribute('role', 'group');
      emptySheet.setAttribute('aria-labelledby', 'wb-inspector-heading');
      emptySheet.appendChild(createEl('p', '', t('ins.emptyBody')));
      var emptyActions = createEl('div', 'inspector-actions');
      var clearBtn = createEl('button', 'action-btn', t('ins.clearFilter'));
      clearBtn.type = 'button';
      clearBtn.addEventListener('click', function () {
        var searchEl = document.getElementById('wb-search');
        state.query = '';
        if (searchEl) searchEl.value = '';
        cancelStopFlow();
        renderWorkbench('#wb-search');
      });
      emptyActions.appendChild(clearBtn);
      emptySheet.appendChild(emptyActions);
      root.appendChild(emptySheet);
      return;
    }

    var svc = selectedService();
    if (svc.stopping) {
      state.stopTargetId = svc.id;
      state.inspectorMode = 'stopping';
    } else if (state.inspectorMode !== 'inspect' && state.stopTargetId !== svc.id) {
      cancelStopFlow();
    }

    var head = createEl('div', 'inspector-head');
    var titleBox = createEl('div');

    var kickerKey = 'ins.kicker';
    if (state.inspectorMode === 'confirm-stop' || state.inspectorMode === 'stopping') kickerKey = 'ins.kickerStop';
    else if (state.inspectorMode === 'force-stop') kickerKey = 'ins.kickerForce';
    else if (state.inspectorMode === 'refused') kickerKey = 'ins.kickerRefused';

    titleBox.appendChild(createEl('div', 'inspector-kicker', t(kickerKey)));
    var headingEl = createEl('h3', '', svc.name);
    headingEl.id = 'wb-inspector-heading';
    headingEl.tabIndex = -1;
    titleBox.appendChild(headingEl);
    head.appendChild(titleBox);

    var pillClass = 'status-pill';
    var pillText = t('ins.badgeRunning');
    if (svc.stopped) {
      pillClass += ' is-muted';
      pillText = t('ins.badgeStopped');
    } else if (svc.stopPolicy === 'refused-docker') {
      pillClass += ' is-warn';
      pillText = t('ins.badgeDocker');
    } else if (svc.stopPolicy === 'ignores-sigterm') {
      pillClass += ' is-danger';
      pillText = t('ins.badgeIgnoresSigterm');
    }

    var headActions = createEl('div', 'inspector-head-actions');
    headActions.appendChild(createEl('span', pillClass, pillText));
    var backListBtn = createEl('button', 'row-btn back-to-list-btn');
    backListBtn.type = 'button';
    var backArrow = createEl('span', 'back-arrow', '↑');
    backArrow.setAttribute('aria-hidden', 'true');
    backListBtn.appendChild(backArrow);
    backListBtn.appendChild(createEl('span', '', t('ins.backToList')));
    backListBtn.addEventListener('click', function () {
      var targetRow = document.querySelector('[data-svc-id="' + svc.id + '"]');
      if (targetRow && typeof targetRow.scrollIntoView === 'function') {
        var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        targetRow.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'center' });
      }
      focusSelector('[data-svc-id="' + svc.id + '"] [data-action="select"]');
    });
    headActions.appendChild(backListBtn);
    head.appendChild(headActions);
    root.appendChild(head);

    if (state.inspectorMode === 'confirm-stop' || state.inspectorMode === 'stopping') {
      var sheet = createEl('div', 'stop-sheet');
      sheet.setAttribute('role', 'group');
      sheet.setAttribute('aria-labelledby', 'wb-sheet-title');
      var stopH4 = createEl('h4', '', t('ins.stopTitle'));
      stopH4.id = 'wb-sheet-title';
      stopH4.tabIndex = -1;
      sheet.appendChild(stopH4);
      sheet.appendChild(createEl('p', '', t('ins.stopSub')));

      var stopGrid = createEl('div', 'evidence-grid');
      addEvidenceRow(stopGrid, t('ins.planToken'), 'plan_' + svc.id + '_' + svc.pid, true);
      addEvidenceRow(stopGrid, t('ins.pidOrder'), String(svc.pid), true);
      addEvidenceRow(stopGrid, t('ins.verifyPort'), '127.0.0.1:' + svc.port, true);
      sheet.appendChild(stopGrid);

      if (svc.stopLog && svc.stopLog.length) {
        var ul = createEl('ul', 'stop-log');
        svc.stopLog.forEach(function (entry) {
          ul.appendChild(createEl('li', '', t(entry.key, entry.vars)));
        });
        sheet.appendChild(ul);
      }

      var stopActions = createEl('div', 'inspector-actions');
      var cancelBtn = createEl('button', 'action-btn', t('wb.cancel'));
      cancelBtn.type = 'button';
      cancelBtn.disabled = state.inspectorMode === 'stopping';
      cancelBtn.addEventListener('click', dismissStopReview);
      stopActions.appendChild(cancelBtn);

      var confirmBtn = createEl('button', 'action-btn is-danger', state.inspectorMode === 'stopping' ? t('ins.stopping') : t('ins.confirmStop'));
      confirmBtn.type = 'button';
      confirmBtn.disabled = state.inspectorMode === 'stopping';
      confirmBtn.addEventListener('click', function () {
        executeSigtermStop(svc);
      });
      stopActions.appendChild(confirmBtn);
      sheet.appendChild(stopActions);
      root.appendChild(sheet);
      return;
    }

    if (state.inspectorMode === 'force-stop') {
      var forceSheet = createEl('div', 'stop-sheet is-danger');
      forceSheet.setAttribute('role', 'group');
      forceSheet.setAttribute('aria-labelledby', 'wb-sheet-title');
      var forceH4 = createEl('h4', '', t('ins.forceTitle'));
      forceH4.id = 'wb-sheet-title';
      forceH4.tabIndex = -1;
      forceSheet.appendChild(forceH4);
      forceSheet.appendChild(createEl('p', '', t('ins.forceSub')));

      if (svc.stopLog && svc.stopLog.length) {
        var logUl = createEl('ul', 'stop-log');
        svc.stopLog.forEach(function (entry) {
          logUl.appendChild(createEl('li', '', t(entry.key, entry.vars)));
        });
        forceSheet.appendChild(logUl);
      }

      var forceGrid = createEl('div', 'evidence-grid');
      addEvidenceRow(forceGrid, t('ins.planToken'), 'plan_kill_' + svc.id + '_' + svc.pid, true);
      addEvidenceRow(forceGrid, t('ins.pidOrder'), String(svc.pid), true);
      addEvidenceRow(forceGrid, t('ins.verifyPort'), '127.0.0.1:' + svc.port, true);
      forceSheet.appendChild(forceGrid);

      var forceActions = createEl('div', 'inspector-actions');
      var cancelForce = createEl('button', 'action-btn', t('wb.cancel'));
      cancelForce.type = 'button';
      cancelForce.addEventListener('click', dismissStopReview);
      forceActions.appendChild(cancelForce);

      var forceBtn = createEl('button', 'action-btn is-danger', '');
      forceBtn.id = 'wb-force-btn';
      forceBtn.type = 'button';
      forceBtn.addEventListener('click', function () {
        executeForceKill(svc);
      });
      forceActions.appendChild(forceBtn);
      forceSheet.appendChild(forceActions);
      root.appendChild(forceSheet);
      updateForceCountdownButton();
      return;
    }

    if (state.inspectorMode === 'refused') {
      var refSheet = createEl('div', 'stop-sheet is-warn');
      refSheet.setAttribute('role', 'group');
      refSheet.setAttribute('aria-labelledby', 'wb-sheet-title');
      var refH4 = createEl('h4', '', t('ins.refusedTitle'));
      refH4.id = 'wb-sheet-title';
      refH4.tabIndex = -1;
      refSheet.appendChild(refH4);
      refSheet.appendChild(createEl('p', '', t('ins.refusedBody')));

      var refGrid = createEl('div', 'evidence-grid');
      addEvidenceRow(refGrid, t('ins.pid'), serviceField(svc, 'ancestry'), true);
      addEvidenceRow(refGrid, t('ins.bind'), serviceField(svc, 'bind'), true);
      refSheet.appendChild(refGrid);

      var refActions = createEl('div', 'inspector-actions');
      var backBtn = createEl('button', 'action-btn', t('ins.back'));
      backBtn.type = 'button';
      backBtn.addEventListener('click', dismissStopReview);
      refActions.appendChild(backBtn);
      refSheet.appendChild(refActions);
      root.appendChild(refSheet);
      return;
    }

    var grid = createEl('div', 'evidence-grid');
    addEvidenceRow(grid, t('ins.pid'), serviceField(svc, 'ancestry'), true);
    addEvidenceRow(grid, t('ins.repo'), svc.repo + ' (' + svc.branch + ')', true);
    addEvidenceRow(grid, t('ins.cwd'), serviceField(svc, 'cwd'), true);
    addEvidenceRow(grid, t('ins.manifest'), svc.manifest, false);
    addEvidenceRow(grid, t('ins.bind'), serviceField(svc, 'bind'), true);
    addEvidenceRow(grid, t('ins.probe'), svc.stopped ? (t('ins.probeStoppedPrefix') + svc.probe) : svc.probe, false);
    addEvidenceRow(grid, t('ins.route'), svc.stopped ? t('wb.stoppedLabel') : (routeUrl(svc) + ' → 127.0.0.1:' + svc.port), true);

    var policyKey = 'ins.policyOwned';
    if (svc.stopPolicy === 'refused-docker') policyKey = 'ins.policyDocker';
    else if (svc.stopPolicy === 'ignores-sigterm') policyKey = 'ins.policyForce';
    addEvidenceRow(grid, t('ins.stopPolicy'), t(policyKey), false);
    root.appendChild(grid);

    if (svc.stopLog && svc.stopLog.length) {
      var doneBox = createEl('div', 'stop-sheet stop-log-box');
      var doneUl = createEl('ul', 'stop-log');
      svc.stopLog.forEach(function (entry) {
        doneUl.appendChild(createEl('li', '', t(entry.key, entry.vars)));
      });
      doneBox.appendChild(doneUl);
      root.appendChild(doneBox);
    }

    var insActions = createEl('div', 'inspector-actions');
    if (svc.stopped) {
      var restartBtn = createEl('button', 'action-btn is-primary', t('ins.restartBtn'));
      restartBtn.type = 'button';
      restartBtn.setAttribute('data-action', 'restart');
      restartBtn.addEventListener('click', function () {
        svc.stopped = false;
        svc.stopLog = [];
        announce(t('msg.restarted', { name: svc.name }));
        renderWorkbench('#wb-inspector .action-btn');
      });
      insActions.appendChild(restartBtn);
    } else {
      var copyRouteBtn = createEl('button', 'action-btn', t('ins.copyRoute'));
      copyRouteBtn.type = 'button';
      copyRouteBtn.setAttribute('data-action', 'copy-route');
      copyRouteBtn.addEventListener('click', function () {
        copyText(routeUrl(svc), copyRouteBtn, t('ins.copyRoute'));
      });
      insActions.appendChild(copyRouteBtn);

      var copyOrigBtn = createEl('button', 'action-btn', t('ins.copyOrig'));
      copyOrigBtn.type = 'button';
      copyOrigBtn.setAttribute('data-action', 'copy-orig');
      copyOrigBtn.addEventListener('click', function () {
        copyText('http://127.0.0.1:' + svc.port, copyOrigBtn, t('ins.copyOrig'));
      });
      insActions.appendChild(copyOrigBtn);

      var stopTrigger = createEl('button', 'action-btn is-danger', t('ins.reviewStop'));
      stopTrigger.type = 'button';
      stopTrigger.setAttribute('data-action', 'stop');
      stopTrigger.addEventListener('click', function () {
        startStopFlow(svc, '#wb-inspector .action-btn.is-danger');
      });
      insActions.appendChild(stopTrigger);
    }
    root.appendChild(insActions);
  }

  function renderWorkbench(restoreFocusSelector) {
    renderServiceList(restoreFocusSelector);
    renderInspector();
    if (restoreFocusSelector && restoreFocusSelector.indexOf('#wb-inspector') === 0) {
      focusSelector(restoreFocusSelector);
    }
  }

  function initWorkbench() {
    var helperBtn = document.getElementById('wb-helper-toggle');
    var searchEl = document.getElementById('wb-search');
    var resetBtn = document.getElementById('wb-reset-btn');
    var webToggle = document.getElementById('wb-toggle-web-other');
    var webList = document.getElementById('wb-other-web-list');
    var lisToggle = document.getElementById('wb-toggle-listeners');
    var lisList = document.getElementById('wb-other-listeners-list');

    if (helperBtn) {
      helperBtn.addEventListener('click', function () {
        state.helperEnabled = !state.helperEnabled;
        syncHelperControls();
        renderWorkbench();
        announce(t(state.helperEnabled ? 'wb.helperOn' : 'wb.helperOff'));
      });
    }

    if (searchEl) {
      searchEl.addEventListener('input', function () {
        state.query = searchEl.value;
        reconcileVisibleSelection();
        renderWorkbench();
      });

      document.addEventListener('keydown', function (ev) {
        if (ev.key === '/' && !ev.metaKey && !ev.ctrlKey && !ev.altKey) {
          var wb = document.getElementById('workbench');
          if (!wb || !document.activeElement || !wb.contains(document.activeElement)) return;
          var tag = document.activeElement.tagName;
          if (tag !== 'INPUT' && tag !== 'TEXTAREA' && tag !== 'SELECT') {
            ev.preventDefault();
            searchEl.focus();
          }
        } else if (ev.key === 'Escape' && document.activeElement === searchEl) {
          ev.preventDefault();
          searchEl.value = '';
          state.query = '';
          cancelStopFlow();
          renderWorkbench();
        }
      });
    }

    function setDisclosure(btn, list, expanded) {
      if (!btn || !list) return;
      btn.setAttribute('aria-expanded', expanded ? 'true' : 'false');
      list.hidden = !expanded;
    }

    if (resetBtn) {
      resetBtn.addEventListener('click', function () {
        clearAllPendingStops();
        cancelStopFlow();
        state.services = cloneServices();
        state.query = '';
        if (searchEl) searchEl.value = '';
        state.selectedId = 'phone3d';
        state.editingId = null;
        state.renameDraft = null;
        state.renameError = null;
        state.supportExpanded = false;
        state.stopOpenerSelector = null;
        state.helperEnabled = true;
        setDisclosure(webToggle, webList, false);
        setDisclosure(lisToggle, lisList, false);
        hideCopyFallback(false);
        syncHelperControls();
        renderWorkbench();
        announce(t('msg.demoReset'));
      });
    }

    function wireDisclosure(btn, list) {
      if (!btn || !list) return;
      btn.addEventListener('click', function () {
        var expanded = btn.getAttribute('aria-expanded') === 'true';
        setDisclosure(btn, list, !expanded);
      });
    }

    wireDisclosure(webToggle, webList);
    wireDisclosure(lisToggle, lisList);

    document.addEventListener('keydown', function (ev) {
      if (ev.key !== 'Escape' || ev.defaultPrevented) return;
      var fb = document.getElementById('copy-fallback');
      if (fb && !fb.hidden) {
        ev.preventDefault();
        hideCopyFallback(true);
        return;
      }
      var nav = document.getElementById('mobile-nav');
      if (nav && nav.open) return;
      if (searchEl && document.activeElement === searchEl) return;
      if (state.inspectorMode === 'confirm-stop' || state.inspectorMode === 'force-stop' || state.inspectorMode === 'refused') {
        ev.preventDefault();
        dismissStopReview();
      }
    });

    syncHelperControls();
    renderWorkbench();
  }

  document.addEventListener('DOMContentLoaded', function () {
    initThemeToggle();
    initMobileNavMenu();
    initHeroStage();
    initTabs();
    initStaticCopyButtons();
    initWorkbench();
    initLanguageToggle();
  });
})();
